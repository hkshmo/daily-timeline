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
}
