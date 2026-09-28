import Foundation
import Combine

struct RecurringTaskRule: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date?
    var duration: TimeInterval
    var color: TaskColor
    var weekdays: [Int]
    var isFlexible: Bool
    var estimatedDuration: TimeInterval?
}

struct RecurringTaskOverride: Codable, Equatable {
    var ruleID: UUID
    var day: Date
    var task: DayTask?
    var isDeleted: Bool
}

enum SeriesDeletionScope {
    case thisDay
    case thisAndFollowing
    case wholeSeries
}

private struct TaskStoreSnapshot: Codable {
    var version = 2
    var oneTimeTasks: [DayTask]
    var recurringRules: [RecurringTaskRule]
    var overrides: [RecurringTaskOverride]
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published var selectedDate = Date()
    @Published private(set) var storageError: String?

    private(set) var oneTimeTasks: [DayTask] = []
    private(set) var recurringRules: [RecurringTaskRule] = []
    private(set) var occurrenceOverrides: [RecurringTaskOverride] = []

    var tasks: [DayTask] {
        oneTimeTasks + occurrenceOverrides.compactMap { $0.isDeleted ? nil : $0.task }
    }

    private let calendar: Calendar
    private let fileURL: URL
    private var didCreateSessionBackup = false

    private static let maximumStorageBytes = 20 * 1024 * 1024
    private static let maximumRecordCount = 50_000
    /// Сколько дней истории повторяющихся задач хранить. Более старые дни не показываются.
    static let historyRetentionDays = 60

    init(calendar: Calendar = .autoupdatingCurrent, fileURL: URL? = nil) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func menuBarTitle(at now: Date) -> String {
        let active = tasksForDay(now).first { $0.start <= now && now < $0.end && !$0.isCompleted }
        return active.map { "\($0.title) · \(Self.timeFormatter.string(from: $0.end))" } ?? Self.timeFormatter.string(from: now)
    }

    func tasksForDay(_ date: Date) -> [DayTask] {
        let day = calendar.startOfDay(for: date)
        let concrete = oneTimeTasks.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let repeated = recurringRules.compactMap { occurrence(for: $0, on: day, now: Date()) }
        return (concrete + repeated).sorted { $0.start < $1.start }
    }

    func add(_ task: DayTask, repeatWeekdays: Set<Int>? = nil) {
        let task = normalized(task)
        if let repeatWeekdays {
            recurringRules.append(makeRule(from: task, weekdays: repeatWeekdays))
        } else {
            oneTimeTasks.append(asOneTime(task))
        }
        changed()
    }

    func update(_ task: DayTask) {
        update(task, repeatWeekdays: task.repeatWeekdays.map(Set.init))
    }

    func update(_ task: DayTask, repeatWeekdays: Set<Int>?) {
        let task = normalized(task)
        if let ruleID = task.seriesID,
           let ruleIndex = recurringRules.firstIndex(where: { $0.id == ruleID }) {
            let occurrenceDay = calendar.startOfDay(for: task.occurrenceDate ?? task.start)
            if let repeatWeekdays {
                if occurrenceDay <= calendar.startOfDay(for: recurringRules[ruleIndex].startDate) {
                    recurringRules[ruleIndex] = makeRule(from: task, weekdays: repeatWeekdays, id: ruleID)
                } else {
                    recurringRules[ruleIndex].endDate = occurrenceDay
                    recurringRules.append(makeRule(from: task, weekdays: repeatWeekdays))
                }
                occurrenceOverrides.removeAll { $0.ruleID == ruleID && $0.day >= occurrenceDay }
            } else {
                markDeleted(ruleID: ruleID, day: occurrenceDay)
                oneTimeTasks.append(asOneTime(task))
            }
            changed()
            return
        }

        guard let index = oneTimeTasks.firstIndex(where: { $0.id == task.id }) else { return }
        if let repeatWeekdays {
            oneTimeTasks.remove(at: index)
            recurringRules.append(makeRule(from: task, weekdays: repeatWeekdays))
        } else {
            oneTimeTasks[index] = asOneTime(task)
        }
        changed()
    }

    func delete(_ task: DayTask) {
        if let ruleID = task.seriesID {
            markDeleted(ruleID: ruleID, day: occurrenceDay(for: task))
        } else {
            oneTimeTasks.removeAll { $0.id == task.id }
        }
        changed()
    }

    /// Удаление дня повторяющейся задачи с выбором охвата. Для разовой задачи — обычное удаление.
    func delete(_ task: DayTask, scope: SeriesDeletionScope) {
        guard let ruleID = task.seriesID,
              let index = recurringRules.firstIndex(where: { $0.id == ruleID }) else {
            delete(task)
            return
        }
        let day = occurrenceDay(for: task)
        let removesWholeRule = scope == .wholeSeries
            || (scope == .thisAndFollowing && day <= calendar.startOfDay(for: recurringRules[index].startDate))

        switch scope {
        case .thisDay:
            delete(task)
            return
        case .thisAndFollowing where !removesWholeRule:
            recurringRules[index].endDate = day
            occurrenceOverrides.removeAll { $0.ruleID == ruleID && $0.day >= day }
        default:
            recurringRules.remove(at: index)
            occurrenceOverrides.removeAll { $0.ruleID == ruleID }
        }
        changed()
    }

    func toggle(_ task: DayTask) {
        guard var updated = storedTask(for: task) else { return }
        updated.isCompleted.toggle()
        save(updated)
    }

    func toggleStart(_ task: DayTask) {
        guard var updated = storedTask(for: task) else { return }
        if updated.startedAt == nil {
            stopOtherStartedTasks(except: updated.id)
            let now = Date()
            if updated.isFlexible == true {
                let duration = updated.estimatedDuration ?? 3600
                updated.start = now
                updated.end = now.addingTimeInterval(duration)
            }
            updated.startedAt = now
            updated.isCompleted = false
            updated.isAutoStartSuppressed = false
        } else {
            updated.startedAt = nil
            updated.isAutoStartSuppressed = true
        }
        save(updated)
    }

    @discardableResult
    func startCurrentScheduledTask(at date: Date) -> DayTask? {
        guard var task = tasksForDay(date)
            .filter({
                !$0.isCompleted && $0.isFlexible != true && $0.isAutoStartSuppressed != true
                    && $0.start <= date && date < $0.end
            })
            .max(by: { $0.start < $1.start }), task.startedAt == nil else { return nil }

        stopOtherStartedTasks(except: task.id)
        task.startedAt = date
        task.isCompleted = false
        task.isAutoStartSuppressed = false
        save(task)
        return task
    }

    func complete(_ task: DayTask) {
        guard var updated = storedTask(for: task) else { return }
        updated.isCompleted = true
        save(updated)
    }

    func postpone(_ task: DayTask, by minutes: Int) {
        guard var updated = storedTask(for: task) else { return }
        let latestStart = updated.end.addingTimeInterval(-60)
        updated.start = min(updated.start.addingTimeInterval(TimeInterval(minutes * 60)), latestStart)
        updated.startedAt = nil
        updated.isCompleted = false
        updated.isAutoStartSuppressed = false
        save(updated)
    }

    func completeExpiredTasks(at date: Date) {
        var didChange = false
        for index in oneTimeTasks.indices where
            !oneTimeTasks[index].isCompleted && oneTimeTasks[index].end <= date
            && (oneTimeTasks[index].isFlexible != true || oneTimeTasks[index].startedAt != nil) {
            oneTimeTasks[index].isCompleted = true
            didChange = true
        }
        for index in occurrenceOverrides.indices {
            guard var task = occurrenceOverrides[index].task, !task.isCompleted, task.end <= date,
                  task.isFlexible != true || task.startedAt != nil else { continue }
            task.isCompleted = true
            occurrenceOverrides[index].task = task
            didChange = true
        }
        if pruneHistory(now: date) { didChange = true }
        if didChange { changed() }
    }

    /// Не даёт файлу расти бесконечно:
    /// - удаляет записи о днях старше `historyRetentionDays` и правила, закончившиеся до этого срока;
    /// - удаляет записи о завершённых днях, которые ничем не отличаются от того, что и так сгенерирует
    ///   правило (обычный день: автозапуск → завершение).
    /// Возвращает true, если что-то изменилось; сохранение — на вызывающем.
    @discardableResult
    func pruneHistory(now: Date = Date()) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.historyRetentionDays, to: today) else {
            return false
        }
        let rulesBefore = recurringRules
        let overridesBefore = occurrenceOverrides

        recurringRules.removeAll { rule in
            rule.endDate.map { calendar.startOfDay(for: $0) <= cutoff } ?? false
        }
        for index in recurringRules.indices where calendar.startOfDay(for: recurringRules[index].startDate) < cutoff {
            let time = calendar.dateComponents([.hour, .minute, .second], from: recurringRules[index].startDate)
            recurringRules[index].startDate = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: cutoff
            ) ?? cutoff
        }

        let rulesByID = Dictionary(recurringRules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // filter, а не removeAll: замыкание вызывает occurrence(), и изменять массив в этот момент нельзя.
        let keptOverrides = occurrenceOverrides.filter { override in
            guard let rule = rulesByID[override.ruleID], override.day >= cutoff else { return false }
            guard !override.isDeleted, let task = override.task,
                  let base = occurrence(for: rule, on: override.day, now: now, applyOverrides: false) else {
                return true
            }
            return !(task.isCompleted && base.isCompleted && Self.hasSameSchedule(task, base))
        }
        occurrenceOverrides = keptOverrides

        return rulesBefore != recurringRules || overridesBefore != occurrenceOverrides
    }

    func nextScheduledEvent(after date: Date) -> Date? {
        var candidates = oneTimeTasks.flatMap { eventDates(for: $0, after: date) }
        let firstDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            for rule in recurringRules {
                if let task = occurrence(for: rule, on: day, now: date) {
                    candidates.append(contentsOf: eventDates(for: task, after: date))
                }
            }
        }
        return candidates.min()
    }

    func clearStorageError() { storageError = nil }

    private func eventDates(for task: DayTask, after date: Date) -> [Date] {
        guard !task.isCompleted else { return [] }
        var dates: [Date] = []
        if task.isFlexible != true, task.isAutoStartSuppressed != true,
           task.startedAt == nil, task.start > date { dates.append(task.start) }
        if (task.isFlexible != true || task.startedAt != nil), task.end > date { dates.append(task.end) }
        return dates
    }

    private func occurrence(
        for rule: RecurringTaskRule,
        on rawDay: Date,
        now: Date,
        applyOverrides: Bool = true
    ) -> DayTask? {
        let day = calendar.startOfDay(for: rawDay)
        let firstDay = calendar.startOfDay(for: rule.startDate)
        guard day >= firstDay,
              rule.endDate.map({ day < calendar.startOfDay(for: $0) }) ?? true,
              rule.weekdays.contains(calendar.component(.weekday, from: day)) else { return nil }

        if applyOverrides, let override = occurrenceOverrides.first(where: {
            $0.ruleID == rule.id && calendar.isDate($0.day, inSameDayAs: day)
        }) {
            return override.isDeleted ? nil : override.task
        }

        let components = calendar.dateComponents([.hour, .minute, .second], from: rule.startDate)
        let start = rule.isFlexible ? day : calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: day
        ) ?? day
        let end = start.addingTimeInterval(rule.duration)
        return DayTask(
            id: occurrenceID(ruleID: rule.id, day: day),
            title: rule.title,
            start: start,
            end: end,
            color: rule.color,
            isCompleted: !rule.isFlexible && end <= now,
            seriesID: rule.id,
            repeatWeekdays: rule.weekdays,
            isFlexible: rule.isFlexible,
            estimatedDuration: rule.estimatedDuration,
            occurrenceDate: day
        )
    }

    private func occurrenceID(ruleID: UUID, day: Date) -> UUID {
        var bytes = withUnsafeBytes(of: ruleID.uuid) { Array($0) }
        var dayNumber = Int64(calendar.startOfDay(for: day).timeIntervalSinceReferenceDate / 86_400).bigEndian
        withUnsafeBytes(of: &dayNumber) { dayBytes in
            for index in 0..<8 { bytes[index + 8] ^= dayBytes[index] }
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func occurrenceDay(for task: DayTask) -> Date {
        calendar.startOfDay(for: task.occurrenceDate ?? task.start)
    }

    private func storedTask(for task: DayTask) -> DayTask? {
        if task.seriesID != nil {
            return tasksForDay(occurrenceDay(for: task)).first { $0.id == task.id }
        }
        return oneTimeTasks.first { $0.id == task.id }
    }

    private func save(_ task: DayTask) {
        if let ruleID = task.seriesID {
            let day = occurrenceDay(for: task)
            let value = RecurringTaskOverride(ruleID: ruleID, day: day, task: task, isDeleted: false)
            if let index = occurrenceOverrides.firstIndex(where: {
                $0.ruleID == ruleID && calendar.isDate($0.day, inSameDayAs: day)
            }) { occurrenceOverrides[index] = value } else { occurrenceOverrides.append(value) }
        } else if let index = oneTimeTasks.firstIndex(where: { $0.id == task.id }) {
            oneTimeTasks[index] = task
        } else { return }
        changed()
    }

    private func markDeleted(ruleID: UUID, day: Date) {
        let value = RecurringTaskOverride(ruleID: ruleID, day: day, task: nil, isDeleted: true)
        if let index = occurrenceOverrides.firstIndex(where: {
            $0.ruleID == ruleID && calendar.isDate($0.day, inSameDayAs: day)
        }) { occurrenceOverrides[index] = value } else { occurrenceOverrides.append(value) }
    }

    private func stopOtherStartedTasks(except id: UUID) {
        for index in oneTimeTasks.indices where oneTimeTasks[index].id != id && oneTimeTasks[index].startedAt != nil {
            oneTimeTasks[index].startedAt = nil
            oneTimeTasks[index].isAutoStartSuppressed = true
        }
        for index in occurrenceOverrides.indices {
            guard var task = occurrenceOverrides[index].task, task.id != id, task.startedAt != nil else { continue }
            task.startedAt = nil
            task.isAutoStartSuppressed = true
            occurrenceOverrides[index].task = task
        }
    }

    private func makeRule(from task: DayTask, weekdays: Set<Int>, id: UUID = UUID()) -> RecurringTaskRule {
        RecurringTaskRule(
            id: id,
            title: task.title,
            startDate: task.start,
            endDate: nil,
            duration: max(60, task.end.timeIntervalSince(task.start)),
            color: task.color,
            weekdays: weekdays.sorted(),
            isFlexible: task.isFlexible == true,
            estimatedDuration: task.estimatedDuration
        )
    }

    private func asOneTime(_ task: DayTask) -> DayTask {
        var result = task
        result.seriesID = nil
        result.repeatWeekdays = nil
        result.occurrenceDate = nil
        return result
    }

    private func changed() {
        revision &+= 1
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= Self.maximumStorageBytes else { throw StorageError.fileTooLarge(fileSize) }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            if let snapshot = try? JSONDecoder().decode(TaskStoreSnapshot.self, from: data), snapshot.version == 2 {
                oneTimeTasks = snapshot.oneTimeTasks
                recurringRules = snapshot.recurringRules
                occurrenceOverrides = snapshot.overrides
                try validateRecordCount()
                if pruneHistory() { persist() }
            } else {
                let legacy = try JSONDecoder().decode([DayTask].self, from: data)
                guard legacy.count <= Self.maximumRecordCount else { throw StorageError.tooManyTasks(legacy.count) }
                migrate(legacy)
                pruneHistory()
                secureExistingStorage()
                persist()
                return
            }
            secureExistingStorage()
        } catch {
            let backupResult = preserveCurrentFile(prefix: "tasks-corrupt")
            storageError = ["Не удалось прочитать файл задач: \(error.localizedDescription)", backupResult]
                .compactMap { $0 }.joined(separator: "\n")
        }
    }

    private func migrate(_ legacy: [DayTask]) {
        let now = Date()
        let cutoff = calendar.date(
            byAdding: .day, value: -Self.historyRetentionDays, to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)
        oneTimeTasks = legacy.filter { $0.seriesID == nil }.map(asOneTime)
        let pairs = legacy.compactMap { task in task.seriesID.map { ($0, task) } }
        let grouped = Dictionary(grouping: pairs, by: { $0.0 })

        for (seriesID, values) in grouped {
            // Дни старше срока хранения всё равно были бы удалены очисткой.
            let occurrences = values.map(\.1)
                .filter { calendar.startOfDay(for: $0.start) >= cutoff }
                .sorted { $0.start < $1.start }
            guard let earliest = occurrences.first, let latest = occurrences.last else { continue }
            let template = occurrences.first(where: { $0.start >= now }) ?? latest
            let firstDay = calendar.startOfDay(for: earliest.start)
            let time = calendar.dateComponents([.hour, .minute, .second], from: template.start)
            let ruleStart = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: firstDay
            ) ?? earliest.start
            let rule = RecurringTaskRule(
                id: seriesID,
                title: template.title,
                startDate: ruleStart,
                endDate: nil,
                duration: max(60, template.end.timeIntervalSince(template.start)),
                color: template.color,
                weekdays: (template.repeatWeekdays ?? Array(1...7)).sorted(),
                isFlexible: template.isFlexible == true,
                estimatedDuration: template.estimatedDuration
            )
            recurringRules.append(rule)

            var coveredDays = Set<Date>()
            for old in occurrences {
                let day = calendar.startOfDay(for: old.start)
                guard !coveredDays.contains(day),
                      let generated = occurrence(for: rule, on: day, now: now, applyOverrides: false) else {
                    // День не подходит под правило (другой день недели после смены расписания)
                    // или это второй экземпляр в тот же день — сохраняем как разовую задачу.
                    oneTimeTasks.append(asOneTime(old))
                    continue
                }
                coveredDays.insert(day)

                // Задача с фиксированным временем, которая уже закончилась, считается выполненной
                // (так же делает completeExpiredTasks), даже если в старом файле флаг не успел проставиться.
                let isCompleted = old.isCompleted || (old.isFlexible != true && old.end <= now)
                let stateDiffers: Bool
                if isCompleted && generated.isCompleted {
                    stateDiffers = false // закончившийся день: флаги запуска больше не важны
                } else {
                    stateDiffers = isCompleted != generated.isCompleted
                        || old.startedAt != nil
                        || old.isAutoStartSuppressed == true
                }

                if stateDiffers || !Self.hasSameSchedule(old, generated) {
                    var migrated = old
                    migrated.id = generated.id
                    migrated.isCompleted = isCompleted
                    migrated.seriesID = seriesID
                    migrated.repeatWeekdays = rule.weekdays
                    migrated.occurrenceDate = day
                    occurrenceOverrides.append(
                        RecurringTaskOverride(ruleID: seriesID, day: day, task: migrated, isDeleted: false)
                    )
                }
            }

            // В старом формате удалённый день серии — это просто отсутствующая копия.
            // Правило сгенерировало бы его снова, поэтому помечаем такие дни удалёнными.
            var day = firstDay
            let lastDay = calendar.startOfDay(for: latest.start)
            while day <= lastDay {
                if !coveredDays.contains(day),
                   occurrence(for: rule, on: day, now: now, applyOverrides: false) != nil {
                    markDeleted(ruleID: seriesID, day: day)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
    }

    /// Совпадает ли расписание (название, цвет, время, тип) — без учёта состояния выполнения.
    private static func hasSameSchedule(_ lhs: DayTask, _ rhs: DayTask) -> Bool {
        lhs.title == rhs.title
            && lhs.color == rhs.color
            && abs(lhs.start.timeIntervalSince(rhs.start)) <= 1
            && abs(lhs.end.timeIntervalSince(rhs.end)) <= 1
            && (lhs.isFlexible == true) == (rhs.isFlexible == true)
            && lhs.estimatedDuration == rhs.estimatedDuration
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try createSecureDirectory(at: directory)
            try createSessionBackupIfNeeded()
            try validateRecordCount()
            let snapshot = TaskStoreSnapshot(
                oneTimeTasks: oneTimeTasks,
                recurringRules: recurringRules,
                overrides: occurrenceOverrides
            )
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= Self.maximumStorageBytes else { throw StorageError.fileTooLarge(data.count) }
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            storageError = nil
        } catch {
            storageError = "Не удалось сохранить задачи: \(error.localizedDescription)"
        }
    }

    private func validateRecordCount() throws {
        let count = oneTimeTasks.count + recurringRules.count + occurrenceOverrides.count
        guard count <= Self.maximumRecordCount else { throw StorageError.tooManyTasks(count) }
    }

    private func normalized(_ task: DayTask) -> DayTask {
        var result = task
        result.title = String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(DayTask.maximumTitleLength))
        return result
    }

    private func createSecureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func secureExistingStorage() {
        do {
            try createSecureDirectory(at: fileURL.deletingLastPathComponent())
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            storageError = "Не удалось применить безопасные права доступа: \(error.localizedDescription)"
        }
    }

    private func createSessionBackupIfNeeded() throws {
        guard !didCreateSessionBackup, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let directory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try createSecureDirectory(at: directory)
        let backupURL = directory.appendingPathComponent("tasks-\(Self.backupTimestamp()).json")
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        didCreateSessionBackup = true
    }

    @discardableResult
    private func preserveCurrentFile(prefix: String) -> String? {
        do {
            let directory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
            try createSecureDirectory(at: directory)
            let backupURL = directory.appendingPathComponent("\(prefix)-\(Self.backupTimestamp()).json")
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            didCreateSessionBackup = true
            return "Исходный файл сохранён: \(backupURL.path)"
        } catch { return "Не удалось создать резервную копию: \(error.localizedDescription)" }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Dayline", isDirectory: true).appendingPathComponent("tasks.json")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum StorageError: LocalizedError {
    case fileTooLarge(Int)
    case tooManyTasks(Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let bytes): return "Файл слишком большой (\(bytes) байт)"
        case .tooManyTasks(let count): return "Слишком много записей (\(count))"
        }
    }
}
