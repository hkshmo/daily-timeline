import Foundation

struct DayTask: Identifiable, Codable, Equatable, Sendable {
    static let maximumTitleLength = 200

    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var color: TaskColor
    var isCompleted: Bool
    var startedAt: Date?
    var isAutoStartSuppressed: Bool?
    var seriesID: UUID?
    var repeatWeekdays: [Int]?
    var isFlexible: Bool?
    var estimatedDuration: TimeInterval?
    var modifiedAt: Date?
    var isDeleted: Bool?

    init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date,
        color: TaskColor = .blue,
        isCompleted: Bool = false,
        startedAt: Date? = nil,
        isAutoStartSuppressed: Bool? = nil,
        seriesID: UUID? = nil,
        repeatWeekdays: [Int]? = nil,
        isFlexible: Bool? = nil,
        estimatedDuration: TimeInterval? = nil,
        modifiedAt: Date? = Date(),
        isDeleted: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.color = color
        self.isCompleted = isCompleted
        self.startedAt = startedAt
        self.isAutoStartSuppressed = isAutoStartSuppressed
        self.seriesID = seriesID
        self.repeatWeekdays = repeatWeekdays
        self.isFlexible = isFlexible
        self.estimatedDuration = estimatedDuration
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
    }
}

enum TaskColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue, violet, orange, green, pink, red
    case cyan, teal, yellow, indigo, mint, brown

    var id: String { rawValue }
}
