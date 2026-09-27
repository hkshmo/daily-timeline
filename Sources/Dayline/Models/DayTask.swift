import Foundation

struct DayTask: Identifiable, Codable, Equatable {
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
        estimatedDuration: TimeInterval? = nil
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
    }
}

enum TaskColor: String, CaseIterable, Codable, Identifiable {
    case blue, violet, orange, green, pink, red
    case cyan, teal, yellow, indigo, mint, brown

    var id: String { rawValue }
}
