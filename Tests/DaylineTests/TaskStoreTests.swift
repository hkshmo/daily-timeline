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
        let backupTasks = try JSONDecoder().decode([DayTask].self, from: Data(contentsOf: backups[0]))
        XCTAssertEqual(backupTasks, [first])
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
}
