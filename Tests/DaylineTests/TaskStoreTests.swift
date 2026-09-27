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

    func testDeletedTaskBecomesTombstoneAndStaysHidden() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        let task = DayTask(title: "Delete", start: Date(), end: Date().addingTimeInterval(3600))

        store.add(task)
        store.delete(task)

        XCTAssertTrue(store.tasksForDay(task.start).isEmpty)
        XCTAssertEqual(store.tasks.first?.isDeleted, true)
        XCTAssertTrue(TaskStore(fileURL: url).tasksForDay(task.start).isEmpty)
    }

    func testSynchronizationImportsRemoteTasks() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
        let remote = DayTask(title: "From iPhone", start: Date(), end: Date().addingTimeInterval(3600))
        let store = TaskStore(fileURL: url, syncService: StubSyncService(tasks: [remote]))

        await store.synchronizeNow()

        XCTAssertEqual(store.tasksForDay(remote.start).map(\.id), [remote.id])
        XCTAssertNil(store.syncError)
        XCTAssertNotNil(store.lastSyncedAt)
    }
}

private struct StubSyncService: TaskSyncing {
    let tasks: [DayTask]

    func merge(localTasks _: [DayTask]) async throws -> [DayTask] {
        tasks
    }
}
