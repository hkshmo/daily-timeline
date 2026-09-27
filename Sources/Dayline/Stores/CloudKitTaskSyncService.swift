@preconcurrency import CloudKit
import Foundation

protocol TaskSyncing: Sendable {
    func merge(localTasks: [DayTask]) async throws -> [DayTask]
}

actor CloudKitTaskSyncService: TaskSyncing {
    static let containerIdentifier = "iCloud.com.hkshmo.dayline"

    private let database: CKDatabase
    private let recordType = "DaylineTask"

    init(containerIdentifier: String = CloudKitTaskSyncService.containerIdentifier) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    func merge(localTasks: [DayTask]) async throws -> [DayTask] {
        let remoteRecords = try await fetchAllRecords()
        let remoteTasks = remoteRecords.compactMap(Self.task(from:))
        let remoteRecordsByID = Dictionary(uniqueKeysWithValues: remoteRecords.compactMap { record in
            UUID(uuidString: record.recordID.recordName).map { ($0, record) }
        })

        var mergedByID: [UUID: DayTask] = [:]
        for task in remoteTasks {
            mergedByID[task.id] = task
        }

        var recordsToSave: [CKRecord] = []
        for localTask in localTasks {
            if let remoteTask = mergedByID[localTask.id],
               Self.modificationDate(for: remoteTask) > Self.modificationDate(for: localTask) {
                continue
            }
            mergedByID[localTask.id] = localTask
            let record = remoteRecordsByID[localTask.id]
                ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: localTask.id.uuidString))
            Self.apply(localTask, to: record)
            recordsToSave.append(record)
        }

        if !recordsToSave.isEmpty {
            _ = try await database.modifyRecords(
                saving: recordsToSave,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        }

        return mergedByID.values.sorted {
            if $0.start == $1.start { return $0.id.uuidString < $1.id.uuidString }
            return $0.start < $1.start
        }
    }

    private func fetchAllRecords() async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, resultsLimit: 200)
        records.append(contentsOf: try Self.successfulRecords(from: page.matchResults))

        while let cursor = page.queryCursor {
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 200)
            records.append(contentsOf: try Self.successfulRecords(from: page.matchResults))
        }
        return records
    }

    private static func successfulRecords(
        from results: [(CKRecord.ID, Result<CKRecord, any Error>)]
    ) throws -> [CKRecord] {
        try results.map { try $0.1.get() }
    }

    private static func modificationDate(for task: DayTask) -> Date {
        task.modifiedAt ?? task.start
    }

    private static func apply(_ task: DayTask, to record: CKRecord) {
        record["title"] = task.title as CKRecordValue
        record["start"] = task.start as CKRecordValue
        record["end"] = task.end as CKRecordValue
        record["color"] = task.color.rawValue as CKRecordValue
        record["isCompleted"] = NSNumber(value: task.isCompleted)
        record["startedAt"] = task.startedAt as CKRecordValue?
        record["isAutoStartSuppressed"] = task.isAutoStartSuppressed.map(NSNumber.init(value:))
        record["seriesID"] = task.seriesID?.uuidString as CKRecordValue?
        record["repeatWeekdays"] = task.repeatWeekdays?.map(NSNumber.init(value:)) as CKRecordValue?
        record["isFlexible"] = task.isFlexible.map(NSNumber.init(value:))
        record["estimatedDuration"] = task.estimatedDuration.map(NSNumber.init(value:))
        record["modifiedAt"] = modificationDate(for: task) as CKRecordValue
        record["isDeleted"] = NSNumber(value: task.isDeleted == true)
    }

    private static func task(from record: CKRecord) -> DayTask? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let title = record["title"] as? String,
              let start = record["start"] as? Date,
              let end = record["end"] as? Date,
              let colorName = record["color"] as? String,
              let color = TaskColor(rawValue: colorName) else { return nil }

        return DayTask(
            id: id,
            title: String(title.prefix(DayTask.maximumTitleLength)),
            start: start,
            end: end,
            color: color,
            isCompleted: (record["isCompleted"] as? NSNumber)?.boolValue ?? false,
            startedAt: record["startedAt"] as? Date,
            isAutoStartSuppressed: (record["isAutoStartSuppressed"] as? NSNumber)?.boolValue,
            seriesID: (record["seriesID"] as? String).flatMap(UUID.init(uuidString:)),
            repeatWeekdays: (record["repeatWeekdays"] as? [NSNumber])?.map(\.intValue),
            isFlexible: (record["isFlexible"] as? NSNumber)?.boolValue,
            estimatedDuration: (record["estimatedDuration"] as? NSNumber)?.doubleValue,
            modifiedAt: record["modifiedAt"] as? Date ?? record.modificationDate,
            isDeleted: (record["isDeleted"] as? NSNumber)?.boolValue
        )
    }
}
