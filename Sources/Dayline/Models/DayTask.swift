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
    var occurrenceDate: Date?
    /// Тип блока. nil — обычная задача (так хранятся все задачи, созданные до появления типов).
    var kind: TaskKind?

    var isLunch: Bool { kind == .lunch }

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
        occurrenceDate: Date? = nil,
        kind: TaskKind? = nil
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
        self.occurrenceDate = occurrenceDate
        self.kind = kind
    }
}

/// Приёмы пищи. Обычная задача — kind == nil.
enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    /// SF Symbol для отображения на шкале и в списке.
    var systemImage: String {
        switch self {
        case .breakfast: "cup.and.saucer.fill"
        case .lunch: "fork.knife"
        case .dinner: "wineglass.fill"
        }
    }

    /// Время по умолчанию при быстром добавлении.
    var defaultStartHour: Int {
        switch self {
        case .breakfast: 8
        case .lunch: 13
        case .dinner: 19
        }
    }

    var defaultDurationMinutes: Int {
        switch self {
        case .breakfast: 30
        case .lunch, .dinner: 60
        }
    }

    var defaultColor: TaskColor {
        switch self {
        case .breakfast: .yellow
        case .lunch: .orange
        case .dinner: .indigo
        }
    }
}

enum TaskColor: String, CaseIterable, Codable, Identifiable {
    case blue, violet, orange, green, pink, red
    case cyan, teal, yellow, indigo, mint, brown

    var id: String { rawValue }
}
