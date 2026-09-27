import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [DayTask] = []
    @Published var selectedDate = Date()

    private let calendar: Calendar
    private let fileURL: URL

    init(calendar: Calendar = .current, fileURL: URL? = nil) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func menuBarTitle(at now: Date) -> String {
        let active = tasksForDay(now).first { $0.start <= now && now < $0.end && !$0.isCompleted }
        return active.map { "\($0.title) · \(Self.timeFormatter.string(from: $0.end))" } ?? Self.timeFormatter.string(from: now)
    }

    func tasksForDay(_ date: Date) -> [DayTask] {
        tasks
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .sorted { $0.start < $1.start }
    }

    func add(_ task: DayTask, repeatWeekdays: Set<Int>? = nil) {
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
        guard let oldTask = tasks.first(where: { $0.id == task.id }) else { return }

        if let repeatWeekdays {
            let seriesID = oldTask.seriesID ?? UUID()
            if let oldSeriesID = oldTask.seriesID {
                tasks.removeAll { $0.seriesID == oldSeriesID && $0.start >= oldTask.start }
            } else {
                tasks.removeAll { $0.id == oldTask.id }
            }
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
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func toggle(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()
        persist()
    }

    func toggleStart(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = tasks
        if updated[index].startedAt == nil {
            for otherIndex in updated.indices where otherIndex != index && updated[otherIndex].startedAt != nil {
                updated[otherIndex].startedAt = nil
            }
            let now = Date()
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
        tasks = updated
        persist()
    }

    @discardableResult
    func startCurrentScheduledTask(at date: Date) -> DayTask? {
        guard let index = tasks.indices
            .filter({
                !tasks[$0].isCompleted
                    && tasks[$0].isFlexible != true
                    && tasks[$0].isAutoStartSuppressed != true
                    && tasks[$0].start <= date
                    && date < tasks[$0].end
            })
            .max(by: { tasks[$0].start < tasks[$1].start }),
              tasks[index].startedAt == nil else { return nil }

        var updated = tasks
        for otherIndex in updated.indices where otherIndex != index && updated[otherIndex].startedAt != nil {
            updated[otherIndex].startedAt = nil
        }
        updated[index].startedAt = date
        updated[index].isCompleted = false
        updated[index].isAutoStartSuppressed = false
        tasks = updated
        persist()
        return updated[index]
    }

    func complete(_ task: DayTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted = true
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
        persist()
    }

    func completeExpiredTasks(at date: Date) {
        var updated = tasks
        var changed = false
        for index in updated.indices where
            !updated[index].isCompleted
            && updated[index].end <= date
            && (updated[index].isFlexible != true || updated[index].startedAt != nil) {
            updated[index].isCompleted = true
            changed = true
        }
        if changed {
            tasks = updated
            persist()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DayTask].self, from: data) else { return }
        tasks = decoded
        var changed = false
        for index in tasks.indices where tasks[index].seriesID != nil && tasks[index].repeatWeekdays == nil {
            tasks[index].repeatWeekdays = Array(1...7)
            changed = true
        }
        if extendRepeatingSeriesIfNeeded() { changed = true }
        if changed { persist() }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save tasks: \(error)")
        }
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
        let seriesIDs = Set(tasks.compactMap(\.seriesID))
        let horizon = calendar.date(byAdding: .day, value: 365, to: Date()) ?? Date()
        var changed = false

        for seriesID in seriesIDs {
            let occurrences = tasks.filter { $0.seriesID == seriesID }
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
