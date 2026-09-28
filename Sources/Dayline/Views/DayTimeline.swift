import SwiftUI

struct DayTimeline: View {
    let date: Date
    let now: Date
    let tasks: [DayTask]
    let startHour: Int
    let endHour: Int
    @Binding var highlightedTaskID: UUID?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.quaternary)
                        .frame(height: trackHeight)

                    FreeTimeHatch(ranges: freeTimeRanges)
                        .frame(width: width, height: trackHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .allowsHitTesting(false)

                    ForEach(taskPlacements) { placement in
                        let task = placement.task
                        let start = fraction(for: task.start)
                        let end = fraction(for: task.end)
                        let highlighted = highlightedTaskID == task.id
                        RoundedRectangle(cornerRadius: 5)
                            .fill(task.color.swiftUIColor.opacity(opacity(for: task, highlighted: highlighted)))
                            .frame(width: max(5, width * (end - start)), height: blockHeight)
                            .offset(
                                x: width * start,
                                y: laneCount == 1 ? 0 : 2 + CGFloat(placement.lane) * 12
                            )
                            .scaleEffect(x: 1, y: highlighted ? 1.28 : 1)
                            .zIndex(highlighted ? 2 : 1)
                            .shadow(
                                color: highlighted ? task.color.swiftUIColor.opacity(0.65) : .clear,
                                radius: highlighted ? 4 : 0
                            )
                            .animation(.easeOut(duration: 0.12), value: highlightedTaskID)
                            .allowsHitTesting(false)
                    }

                    if calendar.isDateInToday(date), isVisible(now) {
                        let lineX = min(width - 2, width * fraction(for: now))

                        Rectangle()
                            .fill(.primary)
                            .frame(width: 2, height: trackHeight + 8)
                            .offset(x: lineX, y: -4)
                            .allowsHitTesting(false)

                        // Стрелка под линией: остриём вверх, по центру линии.
                        Triangle()
                            .fill(.primary)
                            .frame(width: 12, height: 5)
                            .offset(x: lineX - 5, y: trackHeight + 3)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: trackHeight)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        highlightedTaskID = task(at: location, width: width)?.id
                    case .ended:
                        highlightedTaskID = nil
                    }
                }
            }
            .frame(height: trackHeight)

            HStack {
                ForEach(scaleHours.indices, id: \.self) { index in
                    Text(String(format: "%02d", scaleHours[index]))
                    if index < scaleHours.count - 1 { Spacer() }
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private var scale: TimelineScale {
        TimelineScale(day: date, startHour: startHour, endHour: endHour, calendar: calendar)
    }

    private func fraction(for date: Date) -> CGFloat {
        scale.fraction(for: date)
    }

    private var visibleTasks: [DayTask] {
        tasks.filter { ($0.isFlexible != true || $0.startedAt != nil) && scale.overlaps($0) }
    }

    private var taskPlacements: [TaskPlacement] {
        var laneEnds: [Date] = []
        return visibleTasks.sorted { $0.start < $1.start }.map { task in
            let lane: Int
            if let available = laneEnds.firstIndex(where: { $0 <= task.start }) {
                lane = available
                laneEnds[available] = task.end
            } else {
                lane = laneEnds.count
                laneEnds.append(task.end)
            }
            return TaskPlacement(task: task, lane: lane)
        }
    }

    private var freeTimeRanges: [ClosedRange<CGFloat>] {
        TimelineFreeTimeCalculator.ranges(
            tasks: tasks,
            day: date,
            startHour: startHour,
            endHour: endHour,
            calendar: calendar
        )
    }

    private var laneCount: Int {
        max(1, (taskPlacements.map(\.lane).max() ?? 0) + 1)
    }

    private var blockHeight: CGFloat { laneCount == 1 ? 20 : 10 }
    private var trackHeight: CGFloat { laneCount == 1 ? 20 : CGFloat(laneCount * 12 + 2) }

    private func task(at location: CGPoint, width: CGFloat) -> DayTask? {
        let lane: Int
        if laneCount == 1 {
            lane = 0
        } else {
            guard location.y >= 2 else { return nil }
            lane = Int((location.y - 2) / 12)
        }

        return taskPlacements.reversed().first { placement in
            guard placement.lane == lane else { return false }
            let startX = width * fraction(for: placement.task.start)
            let endX = max(startX + 5, width * fraction(for: placement.task.end))
            return location.x >= startX && location.x <= endX
        }?.task
    }

    private var scaleHours: [Int] {
        let span = endHour - startHour
        return (0...4).map { index in
            index == 4 ? endHour : startHour + Int((Double(span) * Double(index) / 4).rounded())
        }
    }

    private func isVisible(_ date: Date) -> Bool {
        scale.contains(date)
    }

    private func opacity(for task: DayTask, highlighted: Bool) -> Double {
        if highlighted { return 1 }
        if highlightedTaskID != nil { return 0.28 }
        return task.isCompleted ? 0.35 : 0.85
    }
}

/// Видимый интервал шкалы: конкретные даты начала и конца для выбранного дня.
/// Считаем по реальным датам, а не по времени суток, чтобы задачи через полночь
/// (например, 23:00 → 01:00) не «переворачивались» на шкале.
struct TimelineScale {
    let start: Date
    let end: Date

    init(day: Date, startHour: Int, endHour: Int, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: day)
        func time(_ hour: Int) -> Date {
            let hour = min(max(hour, 0), 24)
            if hour == 24 {
                return calendar.date(byAdding: .day, value: 1, to: dayStart)
                    ?? dayStart.addingTimeInterval(86_400)
            }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart)
                ?? dayStart.addingTimeInterval(TimeInterval(hour * 3600))
        }
        start = time(startHour)
        end = max(time(endHour), start.addingTimeInterval(1))
    }

    func fraction(for date: Date) -> CGFloat {
        let value = date.timeIntervalSince(start) / end.timeIntervalSince(start)
        return CGFloat(min(1, max(0, value)))
    }

    func overlaps(_ task: DayTask) -> Bool {
        task.end > start && task.start < end
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

enum TimelineFreeTimeCalculator {
    static func ranges(
        tasks: [DayTask],
        day: Date,
        startHour: Int,
        endHour: Int,
        calendar: Calendar = .current
    ) -> [ClosedRange<CGFloat>] {
        let scale = TimelineScale(day: day, startHour: startHour, endHour: endHour, calendar: calendar)

        let occupied = tasks
            .filter { ($0.isFlexible != true || $0.startedAt != nil) && scale.overlaps($0) }
            .map { scale.fraction(for: $0.start)...scale.fraction(for: $0.end) }
            .filter { $0.upperBound > $0.lowerBound }
            .sorted { $0.lowerBound < $1.lowerBound }

        var merged: [ClosedRange<CGFloat>] = []
        for range in occupied {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        var free: [ClosedRange<CGFloat>] = []
        var cursor: CGFloat = 0
        for range in merged {
            if range.lowerBound > cursor { free.append(cursor...range.lowerBound) }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < 1 { free.append(cursor...1) }
        return free
    }
}

private struct FreeTimeHatch: View {
    let ranges: [ClosedRange<CGFloat>]

    var body: some View {
        Canvas { context, size in
            for range in ranges {
                let rect = CGRect(
                    x: size.width * range.lowerBound,
                    y: 0,
                    width: size.width * (range.upperBound - range.lowerBound),
                    height: size.height
                )
                guard rect.width > 0 else { continue }
                var clipped = context
                clipped.clip(to: Path(rect))
                for x in stride(from: rect.minX - size.height, through: rect.maxX, by: 8) {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: size.height))
                    line.addLine(to: CGPoint(x: x + size.height, y: 0))
                    clipped.stroke(line, with: .color(.primary.opacity(0.09)), lineWidth: 0.6)
                }
            }
        }
    }
}

private struct TaskPlacement: Identifiable {
    let task: DayTask
    let lane: Int
    var id: UUID { task.id }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))    // верхняя точка (остриё)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) // правый нижний угол
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) // левый нижний угол
        path.closeSubpath()
        return path
    }
}
