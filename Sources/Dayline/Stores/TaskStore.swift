import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [DayTask] = []
    @Published var selectedDate = Date()
    @Published private(set) var storageError: String?
    @Published private(set) var syncError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?

    private let calendar: Calendar
    private let fileURL: URL
    private let syncService: (any TaskSyncing)?
    private var didCreateSessionBackup = false
    private var scheduledSync: Task<Void, Never>?

    private static let maximumStorageBytes = 20 * 1024 * 1024
    private static let maximumTaskCount = 50_000

    init(
        calendar: Calendar = .current,
        fileURL: URL? = nil,
        syncService: (any TaskSyncing)? = nil
    ) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.syncService = syncService
        load()
    }

    func menuBarTitle(at now: Date) -> String {
        let active = tasksForDay(now).first { $0.start <= now && now < $0.end && !$0.isCompleted }
        return active.map { "\($0.title) · \(Self.timeFormatter.string(from: $0.end))" } ?? Self.timeFormatter.string(from: now)
    }

    func tasksForDay(_ date: Date) -> [DayTask] {
        tasks
            .filter { $0.isDeleted != true && calendar.isDate($0.start, inSameDayAs: date) }
            .sorted { $0.start < $1.start }
    }

    func add(_ task: DayTask, repeatWeekdays: Set<Int>? = nil) {
        let task = normalized(task, touch: task.modifiedAt == nil)
        if let repeatWeekdays {
            tasks.append(contentsOf: makeSeries(from: task, weekdays: repeatWeekdays))
        } else {
            tasks.append(task)
        }
        persist()
    }

    func update(_ task: DayTask) {
        let existingDays = tasks.first(where: { $0.id == task.id })?.repeatWeekdays.map(Set.init)
        update(task, repeatWeekdays: existingDays)
    }

    func update(_ task: DayTask, repeatWeekdays: Set<Int>?) {
        let task = normalized(task, touch: true)
        guard let oldTask = tasks.first(where: { $0.id == task.id }) else { return }

        if let repeatWeekdays {
            let seriesID = oldTask.seriesID ?? UUID()
            if let oldSeriesID = oldTask.seriesID {
                replaceWithTombstones { $0.seriesID == oldSeriesID && $0.start >= oldTask.start }
            } else {
                replaceWithTombstones { $0.id == oldTask.id }
            }
            tasks.removeAll { $0.id == task.id }
            tasks.append(contentsOf: makeSeries(from: task, weekdays: repeatWeekdays, seriesID: seriesID))
        } else if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            var oneTimeTask = task
            oneTimeTask.seriesID = nil
            oneTimeTask.repeatWeekdays = nil
            tasks[index] = oneTimeTask
        }
        persist()
    }

    func delete(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDeleted = true
        tasks[index].modifiedAt = Date()
        tasks[index].startedAt = nil
        persist()
    }

    func toggle(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()
        tasks[index].modifiedAt = Date()
        persist()
    }

    func toggleStart(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = tasks
        if updated[index].startedAt == nil {
            let now = Date()
            for otherIndex in updated.indices where otherIndex != index && updated[otherIndex].startedAt != nil {
                updated[otherIndex].startedAt = nil
                updated[otherIndex].modifiedAt = now
            }
            if updated[index].isFlexible == true {
                let duration = updated[index].estimatedDuration ?? 3600
                updated[index].start = now
                updated[index].end = now.addingTimeInterval(duration)
            }
            updated[index].startedAt = now
            updated[index].isCompleted = false
            updated[index].isAutoStartSuppressed = false
        } else {
            updated[index].startedAt = nil
            updated[index].isAutoStartSuppressed = true
        }
        updated[index].modifiedAt = Date()
        tasks = updated
        persist()
    }

    @discardableResult
    func startCurrentScheduledTask(at date: Date) -> DayTask? {
        guard let index = tasks.indices
            .filter({
                !tasks[$0].isCompleted
                    && tasks[$0].isDeleted != true
                    && tasks[$0].isFlexible != true
                    && tasks[$0].isAutoStartSuppressed != true
                    && tasks[$0].start <= date
                    && date < tasks[$0].end
            })
            .max(by: { tasks[$0].start < tasks[$1].start }),
              tasks[index].startedAt == nil else { return nil }

        var updated = tasks
        let now = Date()
        for otherIndex in updated.indices where otherIndex != index && updated[otherIndex].startedAt != nil {
            updated[otherIndex].startedAt = nil
            updated[otherIndex].modifiedAt = now
        }
        updated[index].startedAt = date
        updated[index].isCompleted = false
        updated[index].isAutoStartSuppressed = false
        updated[index].modifiedAt = now
        tasks = updated
        persist()
        return updated[index]
    }

    func complete(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted = true
        tasks[index].modifiedAt = Date()
        persist()
    }

    func postpone(_ task: DayTask, by minutes: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let offset = TimeInterval(minutes * 60)
        let latestStart = tasks[index].end.addingTimeInterval(-60)
        tasks[index].start = min(tasks[index].start.addingTimeInterval(offset), latestStart)
        tasks[index].startedAt = nil
        tasks[index].isCompleted = false
        tasks[index].isAutoStartSuppressed = false
        tasks[index].modifiedAt = Date()
        persist()
    }

    func completeExpiredTasks(at date: Date) {
        var updated = tasks
        var changed = false
        for index in updated.indices where
            !updated[index].isCompleted
            && updated[index].isDeleted != true
            && updated[index].end <= date
            && (updated[index].isFlexible != true || updated[index].startedAt != nil) {
            updated[index].isCompleted = true
            updated[index].modifiedAt = date
            changed = true
        }
        if changed {
            tasks = updated
            persist()
        }
    }

    func clearStorageError() {
        storageError = nil
    }

    func clearSyncError() {
        syncError = nil
    }

    func synchronizeNow() async {
        guard let syncService, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var merged = try await syncService.merge(localTasks: tasks)
            let reconciledConcurrentStarts = reconcileConcurrentStarts(in: &merged)
            tasks = merged
            persist(shouldSync: reconciledConcurrentStarts)
            syncError = nil
            lastSyncedAt = Date()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let decoded: [DayTask]
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = values.fileSize ?? 0
            guard fileSize <= Self.maximumStorageBytes else {
                throw StorageError.fileTooLarge(fileSize)
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            decoded = try JSONDecoder().decode([DayTask].self, from: data)
            guard decoded.count <= Self.maximumTaskCount else {
                throw StorageError.tooManyTasks(decoded.count)
            }
        } catch {
            let backupResult = preserveCurrentFile(prefix: "tasks-corrupt")
            storageError = [
                "Не удалось прочитать файл задач: \(error.localizedDescription)",
                backupResult
            ].compactMap { $0 }.joined(separator: "\n")
            return
        }

        tasks = decoded
        secureExistingStorage()
        var changed = false
        for index in tasks.indices where tasks[index].seriesID != nil && tasks[index].repeatWeekdays == nil {
            tasks[index].repeatWeekdays = Array(1...7)
            changed = true
        }
        for index in tasks.indices where tasks[index].modifiedAt == nil {
            tasks[index].modifiedAt = Date()
            changed = true
        }
        if extendRepeatingSeriesIfNeeded() { changed = true }
        if changed { persist() }
    }

    private func persist(shouldSync: Bool = true) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try createSecureDirectory(at: directory)
            try createSessionBackupIfNeeded()
            guard tasks.count <= Self.maximumTaskCount else {
                throw StorageError.tooManyTasks(tasks.count)
            }
            let data = try JSONEncoder().encode(tasks)
            guard data.count <= Self.maximumStorageBytes else {
                throw StorageError.fileTooLarge(data.count)
            }
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            storageError = nil
            if shouldSync { scheduleSynchronization() }
        } catch {
            storageError = "Не удалось сохранить задачи: \(error.localizedDescription)"
        }
    }

    private func normalized(_ task: DayTask, touch: Bool) -> DayTask {
        var result = task
        result.title = String(
            task.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(DayTask.maximumTitleLength)
        )
        if touch { result.modifiedAt = Date() }
        return result
    }

    private func replaceWithTombstones(where predicate: (DayTask) -> Bool) {
        let now = Date()
        for index in tasks.indices where predicate(tasks[index]) {
            tasks[index].isDeleted = true
            tasks[index].startedAt = nil
            tasks[index].modifiedAt = now
        }
    }

    private func scheduleSynchronization() {
        guard syncService != nil else { return }
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.synchronizeNow()
        }
    }

    private func reconcileConcurrentStarts(in values: inout [DayTask]) -> Bool {
        let activeIndices = values.indices.filter {
            values[$0].isDeleted != true
                && !values[$0].isCompleted
                && values[$0].startedAt != nil
        }
        guard activeIndices.count > 1,
              let winner = activeIndices.max(by: {
                  (values[$0].modifiedAt ?? .distantPast) < (values[$1].modifiedAt ?? .distantPast)
              }) else { return false }
        let now = Date()
        for index in activeIndices where index != winner {
            values[index].startedAt = nil
            values[index].isAutoStartSuppressed = true
            values[index].modifiedAt = now
        }
        return true
    }

    private func createSecureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
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
        guard !didCreateSessionBackup,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let backupsDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try createSecureDirectory(at: backupsDirectory)
        let backupURL = backupsDirectory.appendingPathComponent("tasks-\(Self.backupTimestamp()).json")
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        didCreateSessionBackup = true
    }

    @discardableResult
    private func preserveCurrentFile(prefix: String) -> String? {
        do {
            let backupsDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
            try createSecureDirectory(at: backupsDirectory)
            let backupURL = backupsDirectory.appendingPathComponent("\(prefix)-\(Self.backupTimestamp()).json")
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            didCreateSessionBackup = true
            return "Исходный файл сохранён: \(backupURL.path)"
        } catch {
            return "Не удалось создать резервную копию: \(error.localizedDescription)"
        }
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private func makeSeries(from task: DayTask, weekdays: Set<Int>, seriesID: UUID = UUID()) -> [DayTask] {
        let duration = task.end.timeIntervalSince(task.start)
        let todayHorizon = calendar.date(byAdding: .day, value: 365, to: Date()) ?? Date()
        let taskHorizon = calendar.date(byAdding: .day, value: 365, to: task.start) ?? task.start
        let horizon = max(todayHorizon, taskHorizon)
        var result: [DayTask] = []
        var start = task.start
        var first = true

        while start <= horizon {
            if weekdays.contains(calendar.component(.weekday, from: start)) {
                result.append(DayTask(
                    id: first ? task.id : UUID(),
                    title: task.title,
                    start: start,
                    end: start.addingTimeInterval(duration),
                    color: task.color,
                    seriesID: seriesID,
                    repeatWeekdays: weekdays.sorted(),
                    isFlexible: task.isFlexible,
                    estimatedDuration: task.estimatedDuration
                ))
                first = false
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { break }
            start = next
        }
        return result
    }

    private func extendRepeatingSeriesIfNeeded() -> Bool {
        let seriesIDs = Set(tasks.filter { $0.isDeleted != true }.compactMap(\.seriesID))
        let horizon = calendar.date(byAdding: .day, value: 365, to: Date()) ?? Date()
        var changed = false

        for seriesID in seriesIDs {
            let occurrences = tasks.filter { $0.seriesID == seriesID && $0.isDeleted != true }
            guard let latest = occurrences.max(by: { $0.start < $1.start }), latest.start < horizon else { continue }
            let duration = latest.end.timeIntervalSince(latest.start)
            let weekdays = Set(latest.repeatWeekdays ?? Array(1...7))
            var start = calendar.date(byAdding: .day, value: 1, to: latest.start) ?? horizon
            while start <= horizon {
                if weekdays.contains(calendar.component(.weekday, from: start)) {
                    tasks.append(DayTask(
                        title: latest.title,
                        start: start,
                        end: start.addingTimeInterval(duration),
                        color: latest.color,
                        seriesID: seriesID,
                        repeatWeekdays: weekdays.sorted(),
                        isFlexible: latest.isFlexible,
                        estimatedDuration: latest.estimatedDuration
                    ))
                    changed = true
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { break }
                start = next
            }
        }
        return changed
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
        case .fileTooLarge(let bytes):
            return "Файл слишком большой (\(bytes) байт)"
        case .tooManyTasks(let count):
            return "Слишком много задач (\(count))"
        }
    }
}
