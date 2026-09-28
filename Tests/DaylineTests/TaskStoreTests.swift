import XCTest
@testable import Dayline

@MainActor
final class TaskStoreTests: XCTestCase {
    func testPersistsAndLoadsTasks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let now = Date()
        let task = DayTask(title: "Focus", start: now, end: now.addingTimeInterval(3600))

        let store = TaskStore(fileURL: url)
        store.add(task)

        let restored = TaskStore(fileURL: url)
        XCTAssertEqual(restored.tasks, [task])
    }

    func testTasksAreFilteredAndSortedByDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(calendar: calendar, fileURL: url)
        let late = DayTask(title: "Late", start: day.addingTimeInterval(3600), end: day.addingTimeInterval(7200))
        let early = DayTask(title: "Early", start: day, end: day.addingTimeInterval(1800))
        store.add(late)
        store.add(early)

        XCTAssertEqual(store.tasksForDay(day).map(\.title), ["Early", "Late"])
    }

    func testOnlyOneTaskCanBeStarted() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        let now = Date()
        let first = DayTask(title: "First", start: now, end: now.addingTimeInterval(3600))
        let second = DayTask(title: "Second", start: now, end: now.addingTimeInterval(3600))
        store.add(first)
        store.add(second)

        store.toggleStart(first)
        store.toggleStart(second)

        XCTAssertNil(store.tasks.first(where: { $0.id == first.id })?.startedAt)
        XCTAssertNotNil(store.tasks.first(where: { $0.id == second.id })?.startedAt)
    }

    func testScheduledTaskStartsAutomaticallyAndManualUndoIsRespected() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        let now = Date()
        let task = DayTask(title: "Scheduled", start: now.addingTimeInterval(-10), end: now.addingTimeInterval(3600))
        store.add(task)

        XCTAssertEqual(store.startCurrentScheduledTask(at: now)?.id, task.id)
        XCTAssertNotNil(store.tasks.first?.startedAt)

        store.toggleStart(task)

        XCTAssertNil(store.startCurrentScheduledTask(at: now.addingTimeInterval(1)))
        XCTAssertNil(store.tasks.first?.startedAt)
    }

    func testPostponeKeepsEndAndCancelsAutomaticStart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        let now = Date()
        let task = DayTask(title: "Scheduled", start: now, end: now.addingTimeInterval(3600))
        store.add(task)
        store.startCurrentScheduledTask(at: now)

        store.postpone(task, by: 10)

        let postponed = store.tasks.first
        XCTAssertEqual(postponed?.start, now.addingTimeInterval(600))
        XCTAssertEqual(postponed?.end, task.end)
        XCTAssertNil(postponed?.startedAt)
    }

    func testStorageUsesPrivatePermissionsAndCreatesBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        let first = DayTask(title: "First", start: Date(), end: Date().addingTimeInterval(3600))
        let second = DayTask(title: "Second", start: Date(), end: Date().addingTimeInterval(3600))

        let firstStore = TaskStore(fileURL: url)
        firstStore.add(first)
        let secondStore = TaskStore(fileURL: url)
        secondStore.add(second)

        let directoryPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        )
        let filePermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(directoryPermissions.intValue & 0o777, 0o700)
        XCTAssertEqual(filePermissions.intValue & 0o777, 0o600)

        let backups = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backups.count, 1)
        let backupStore = TaskStore(fileURL: backups[0])
        XCTAssertEqual(backupStore.tasks, [first])
    }

    func testCorruptedStorageIsPreservedAndReported() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)

        let store = TaskStore(fileURL: url)

        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNotNil(store.storageError)
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), Data("not-json".utf8))
    }

    func testTaskTitleIsLimitedBeforePersistence() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        let task = DayTask(
            title: String(repeating: "a", count: DayTask.maximumTitleLength + 50),
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )

        store.add(task)

        XCTAssertEqual(store.tasks.first?.title.count, DayTask.maximumTitleLength)
    }

    func testNextScheduledEventUsesNearestStartOrEnd() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        let now = Date()
        store.add(DayTask(title: "Later", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200)))
        store.add(DayTask(title: "Soon", start: now.addingTimeInterval(120), end: now.addingTimeInterval(300)))

        XCTAssertEqual(store.nextScheduledEvent(after: now), now.addingTimeInterval(120))
    }

    func testFreeTimeRangesForEmptyDay() {
        XCTAssertEqual(
            TimelineFreeTimeCalculator.ranges(tasks: [], day: Date(), startHour: 9, endHour: 18),
            [CGFloat(0)...CGFloat(1)]
        )
    }

    func testFreeTimeRangesMergeOverlappingTasksAndClipToScale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let tasks = [
            DayTask(title: "Before", start: at(8), end: at(10)),
            DayTask(title: "Overlap", start: at(9, 30), end: at(11)),
            DayTask(title: "After", start: at(17), end: at(20))
        ]

        let ranges = TimelineFreeTimeCalculator.ranges(
            tasks: tasks, day: day, startHour: 9, endHour: 18, calendar: calendar
        )

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].lowerBound, CGFloat(2.0 / 9.0), accuracy: 0.0001)
        XCTAssertEqual(ranges[0].upperBound, CGFloat(8.0 / 9.0), accuracy: 0.0001)
    }

    func testFreeTimeRangesHandleTaskCrossingMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        func at(_ hour: Int, dayOffset: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: dayOffset, to: day)!
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
        }
        // 22:00 → 02:00 следующего дня на шкале 18–24: занято с 22:00 до конца шкалы.
        let tasks = [DayTask(title: "Night", start: at(22), end: at(2, dayOffset: 1))]

        let ranges = TimelineFreeTimeCalculator.ranges(
            tasks: tasks, day: day, startHour: 18, endHour: 24, calendar: calendar
        )

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(ranges[0].upperBound, CGFloat(4.0 / 6.0), accuracy: 0.0001)
    }

    func testFreeTimeRangesIgnoreTasksFromOtherDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let task = DayTask(
            title: "Tomorrow",
            start: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDay)!,
            end: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: nextDay)!
        )

        XCTAssertEqual(
            TimelineFreeTimeCalculator.ranges(tasks: [task], day: day, startHour: 9, endHour: 18, calendar: calendar),
            [CGFloat(0)...CGFloat(1)]
        )
    }

    func testRepeatingTaskIsStoredAsOneRuleAndGeneratedForEachDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        let day = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .hour, value: 9, to: day)!
        let task = DayTask(title: "Daily", start: start, end: start.addingTimeInterval(3600))
        let store = TaskStore(calendar: calendar, fileURL: url)

        store.add(task, repeatWeekdays: Set(1...7))

        XCTAssertEqual(store.recurringRules.count, 1)
        XCTAssertEqual(store.occurrenceOverrides.count, 0)
        XCTAssertEqual(store.tasksForDay(day).map(\.title), ["Daily"])
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        XCTAssertEqual(store.tasksForDay(tomorrow).map(\.title), ["Daily"])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((json["recurringRules"] as? [Any])?.count, 1)
        XCTAssertEqual((json["overrides"] as? [Any])?.count, 0)
    }

    func testDeletingOneOccurrenceKeepsRestOfSeries() {
        let calendar = Calendar(identifier: .gregorian)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let day = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .hour, value: 9, to: day)!
        let store = TaskStore(calendar: calendar, fileURL: url)
        store.add(DayTask(title: "Daily", start: start, end: start.addingTimeInterval(3600)), repeatWeekdays: Set(1...7))

        store.delete(store.tasksForDay(day)[0])

        XCTAssertTrue(store.tasksForDay(day).isEmpty)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        XCTAssertEqual(store.tasksForDay(tomorrow).map(\.title), ["Daily"])
        XCTAssertEqual(store.recurringRules.count, 1)
        XCTAssertEqual(store.occurrenceOverrides.count, 1)
    }

    func testLegacySeriesMigratesToCompactRule() throws {
        let calendar = Calendar(identifier: .gregorian)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let firstDay = calendar.startOfDay(for: Date())
        let seriesID = UUID()
        let legacy = (0..<365).map { offset -> DayTask in
            let day = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            return DayTask(
                title: "Daily", start: start, end: start.addingTimeInterval(3600),
                seriesID: seriesID, repeatWeekdays: Array(1...7)
            )
        }
        try JSONEncoder().encode(legacy).write(to: url)

        let store = TaskStore(calendar: calendar, fileURL: url)

        XCTAssertEqual(store.recurringRules.count, 1)
        XCTAssertEqual(store.occurrenceOverrides.count, 0)
        XCTAssertEqual(store.tasksForDay(firstDay).map(\.title), ["Daily"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
    }

    // MARK: - Повторяющиеся задачи

    private func makeStore(calendar: Calendar) -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("tasks.json")
        return TaskStore(calendar: calendar, fileURL: url)
    }

    private func at(_ hour: Int, dayOffset: Int, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func addDailyTask(to store: TaskStore, fromDayOffset offset: Int, calendar: Calendar) {
        store.add(
            DayTask(
                title: "Daily",
                start: at(9, dayOffset: offset, calendar: calendar),
                end: at(10, dayOffset: offset, calendar: calendar)
            ),
            repeatWeekdays: Set(1...7)
        )
    }

    func testStartingRecurringOccurrenceTwiceUsesCurrentState() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        let now = Date()
        store.add(
            DayTask(title: "Daily", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(3000)),
            repeatWeekdays: Set(1...7)
        )
        let stale = try XCTUnwrap(store.tasksForDay(now).first)

        store.toggleStart(stale)
        XCTAssertNotNil(store.tasksForDay(now).first?.startedAt)

        // Второе нажатие приходит со старой копией строки (startedAt == nil) — должно остановить задачу.
        store.toggleStart(stale)
        XCTAssertNil(store.tasksForDay(now).first?.startedAt)
        XCTAssertEqual(store.tasksForDay(now).first?.isAutoStartSuppressed, true)
    }

    func testEditingSeriesFromMiddleKeepsEarlierDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        addDailyTask(to: store, fromDayOffset: 0, calendar: calendar)

        var edited = try XCTUnwrap(store.tasksForDay(at(12, dayOffset: 3, calendar: calendar)).first)
        edited.start = at(11, dayOffset: 3, calendar: calendar)
        edited.end = at(12, dayOffset: 3, calendar: calendar)
        store.update(edited, repeatWeekdays: Set(1...7))

        func startHour(_ offset: Int) -> Int? {
            store.tasksForDay(at(12, dayOffset: offset, calendar: calendar)).first
                .map { calendar.component(.hour, from: $0.start) }
        }
        XCTAssertEqual(store.recurringRules.count, 2)
        XCTAssertEqual(startHour(1), 9)
        XCTAssertEqual(startHour(3), 11)
        XCTAssertEqual(startHour(5), 11)
        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: 3, calendar: calendar)).count, 1)
    }

    func testChangingOneOccurrenceToOneTimeKeepsRestOfSeries() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        addDailyTask(to: store, fromDayOffset: 0, calendar: calendar)

        var single = try XCTUnwrap(store.tasksForDay(at(12, dayOffset: 2, calendar: calendar)).first)
        single.title = "Special"
        store.update(single, repeatWeekdays: nil)

        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: 2, calendar: calendar)).map(\.title), ["Special"])
        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: 3, calendar: calendar)).map(\.title), ["Daily"])
        XCTAssertEqual(store.recurringRules.count, 1)
    }

    func testNextScheduledEventIncludesRecurringOccurrences() {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        addDailyTask(to: store, fromDayOffset: 1, calendar: calendar)

        XCTAssertEqual(store.nextScheduledEvent(after: Date()), at(9, dayOffset: 1, calendar: calendar))
    }

    func testCompletedPastOccurrencesDoNotAccumulate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        addDailyTask(to: store, fromDayOffset: -3, calendar: calendar)
        let past = try XCTUnwrap(store.tasksForDay(at(12, dayOffset: -2, calendar: calendar)).first)

        store.toggleStart(past)
        XCTAssertEqual(store.occurrenceOverrides.count, 1)

        // Обычный день: запустили → время вышло → завершилось. Отдельная запись больше не нужна.
        store.completeExpiredTasks(at: Date())
        XCTAssertEqual(store.occurrenceOverrides.count, 0)
        XCTAssertEqual(store.tasksForDay(past.start).first?.isCompleted, true)
    }

    func testHistoryOlderThanRetentionIsPruned() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        let retention = TaskStore.historyRetentionDays
        addDailyTask(to: store, fromDayOffset: -(retention + 40), calendar: calendar)
        let oldDay = at(12, dayOffset: -(retention + 10), calendar: calendar)
        let oldTask = try XCTUnwrap(store.tasksForDay(oldDay).first)
        store.delete(oldTask)
        XCTAssertEqual(store.occurrenceOverrides.count, 1)

        store.pruneHistory()

        XCTAssertEqual(store.occurrenceOverrides.count, 0)
        XCTAssertTrue(store.tasksForDay(oldDay).isEmpty)
        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: -10, calendar: calendar)).map(\.title), ["Daily"])
    }

    func testLegacyMigrationKeepsDeletedDaysDeleted() throws {
        let calendar = Calendar(identifier: .gregorian)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let seriesID = UUID()
        let legacy = (0..<30).filter { $0 != 5 }.map { offset in
            DayTask(
                title: "Daily",
                start: at(9, dayOffset: offset, calendar: calendar),
                end: at(10, dayOffset: offset, calendar: calendar),
                seriesID: seriesID,
                repeatWeekdays: Array(1...7)
            )
        }
        try JSONEncoder().encode(legacy).write(to: url)

        let store = TaskStore(calendar: calendar, fileURL: url)

        XCTAssertEqual(store.recurringRules.count, 1)
        XCTAssertTrue(store.tasksForDay(at(12, dayOffset: 5, calendar: calendar)).isEmpty)
        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: 6, calendar: calendar)).map(\.title), ["Daily"])
        XCTAssertEqual(store.occurrenceOverrides.filter(\.isDeleted).count, 1)
    }

    func testLegacyMigrationKeepsDaysFromOldWeekdaysAsOneTimeTasks() throws {
        let calendar = Calendar(identifier: .gregorian)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let seriesID = UUID()
        let yesterday = at(9, dayOffset: -1, calendar: calendar)
        let yesterdayWeekday = calendar.component(.weekday, from: yesterday)
        let otherWeekdays = (1...7).filter { $0 != yesterdayWeekday }
        // Вчерашний день остался от старого расписания; с сегодняшнего дня серия идёт по другим дням.
        var legacy = [DayTask(
            title: "Old", start: yesterday, end: yesterday.addingTimeInterval(3600),
            isCompleted: true, seriesID: seriesID, repeatWeekdays: [yesterdayWeekday]
        )]
        for offset in 0..<14 {
            let start = at(9, dayOffset: offset, calendar: calendar)
            guard otherWeekdays.contains(calendar.component(.weekday, from: start)) else { continue }
            legacy.append(DayTask(
                title: "New", start: start, end: start.addingTimeInterval(3600),
                seriesID: seriesID, repeatWeekdays: otherWeekdays
            ))
        }
        try JSONEncoder().encode(legacy).write(to: url)

        let store = TaskStore(calendar: calendar, fileURL: url)

        XCTAssertEqual(store.tasksForDay(yesterday).map(\.title), ["Old"])
        XCTAssertEqual(store.recurringRules.first?.weekdays, otherWeekdays)
        XCTAssertTrue(store.occurrenceOverrides.filter(\.isDeleted).isEmpty)
    }

    func testDeletingThisAndFollowingDaysKeepsEarlierDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        addDailyTask(to: store, fromDayOffset: -2, calendar: calendar)
        let tomorrow = try XCTUnwrap(store.tasksForDay(at(12, dayOffset: 1, calendar: calendar)).first)

        store.delete(tomorrow, scope: .thisAndFollowing)

        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: 0, calendar: calendar)).map(\.title), ["Daily"])
        XCTAssertTrue(store.tasksForDay(at(12, dayOffset: 1, calendar: calendar)).isEmpty)
        XCTAssertTrue(store.tasksForDay(at(12, dayOffset: 30, calendar: calendar)).isEmpty)
        XCTAssertEqual(store.recurringRules.count, 1)
    }

    func testDeletingWholeSeriesRemovesEveryDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let store = makeStore(calendar: calendar)
        addDailyTask(to: store, fromDayOffset: -2, calendar: calendar)
        let today = try XCTUnwrap(store.tasksForDay(at(12, dayOffset: 0, calendar: calendar)).first)
        store.toggleStart(today)

        store.delete(today, scope: .wholeSeries)

        XCTAssertTrue(store.recurringRules.isEmpty)
        XCTAssertTrue(store.occurrenceOverrides.isEmpty)
        XCTAssertTrue(store.tasksForDay(at(12, dayOffset: -2, calendar: calendar)).isEmpty)
        XCTAssertTrue(store.tasksForDay(at(12, dayOffset: 5, calendar: calendar)).isEmpty)
    }

    func testLunchKindIsKeptForRepeatingTasksAndAfterReload() throws {
        let calendar = Calendar(identifier: .gregorian)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("tasks.json")
        let store = TaskStore(calendar: calendar, fileURL: url)
        store.add(
            DayTask(
                title: "Обед",
                start: at(13, dayOffset: 0, calendar: calendar),
                end: at(14, dayOffset: 0, calendar: calendar),
                kind: .lunch
            ),
            repeatWeekdays: Set(1...7)
        )
        store.add(DayTask(
            title: "Work",
            start: at(9, dayOffset: 0, calendar: calendar),
            end: at(10, dayOffset: 0, calendar: calendar)
        ))

        let reloaded = TaskStore(calendar: calendar, fileURL: url)
        let tomorrow = reloaded.tasksForDay(at(12, dayOffset: 1, calendar: calendar))
        XCTAssertEqual(tomorrow.first?.isLunch, true)
        let today = reloaded.tasksForDay(at(12, dayOffset: 0, calendar: calendar))
        XCTAssertEqual(today.map(\.isLunch), [false, true])
    }

    func testWarmupReminderComesIntervalAfterLastBreak() {
        let lastBreak = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            WarmupReminderPlan.nextReminder(lastBreakAt: lastBreak, snoozedUntil: nil, intervalMinutes: 60),
            lastBreak.addingTimeInterval(3600)
        )
    }

    func testWarmupReminderRespectsSnooze() {
        let lastBreak = Date(timeIntervalSince1970: 1_000_000)
        let snoozed = lastBreak.addingTimeInterval(3600 + 600)
        XCTAssertEqual(
            WarmupReminderPlan.nextReminder(lastBreakAt: lastBreak, snoozedUntil: snoozed, intervalMinutes: 60),
            snoozed
        )
        // Отложили на момент раньше срока — срок важнее.
        XCTAssertEqual(
            WarmupReminderPlan.nextReminder(
                lastBreakAt: lastBreak, snoozedUntil: lastBreak.addingTimeInterval(60), intervalMinutes: 60
            ),
            lastBreak.addingTimeInterval(3600)
        )
    }

    func testLegacyMigrationKeepsMealKind() throws {
        let calendar = Calendar(identifier: .gregorian)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let seriesID = UUID()
        let legacy = (0..<14).map { offset in
            DayTask(
                title: "Обед",
                start: at(13, dayOffset: offset, calendar: calendar),
                end: at(14, dayOffset: offset, calendar: calendar),
                seriesID: seriesID,
                repeatWeekdays: Array(1...7),
                kind: .lunch
            )
        }
        try JSONEncoder().encode(legacy).write(to: url)

        let store = TaskStore(calendar: calendar, fileURL: url)

        XCTAssertEqual(store.recurringRules.first?.kind, .lunch)
        XCTAssertEqual(store.tasksForDay(at(12, dayOffset: 3, calendar: calendar)).first?.kind, .lunch)
        // Правило генерирует тот же тип — отдельные записи на каждый день не нужны.
        XCTAssertTrue(store.occurrenceOverrides.isEmpty)
    }
}
