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
                        Rectangle()
                            .fill(.primary)
                            .frame(width: 2, height: trackHeight + 8)
                            .offset(x: min(width - 2, width * fraction(for: now)), y: -4)
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

    private func fraction(for date: Date) -> CGFloat {
        let value = seconds(for: date)
        let start = startHour * 3600
        let duration = max(1, (endHour - startHour) * 3600)
        return min(1, max(0, CGFloat(value - start) / CGFloat(duration)))
    }

    private var visibleTasks: [DayTask] {
        tasks.filter {
            ($0.isFlexible != true || $0.startedAt != nil)
                && seconds(for: $0.end) > startHour * 3600
                && seconds(for: $0.start) < endHour * 3600
        }
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
        let value = seconds(for: date)
        return value >= startHour * 3600 && value <= endHour * 3600
    }

    private func seconds(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }

    private func opacity(for task: DayTask, highlighted: Bool) -> Double {
        if highlighted { return 1 }
        if highlightedTaskID != nil { return 0.28 }
        return task.isCompleted ? 0.35 : 0.85
    }
}

private struct TaskPlacement: Identifiable {
    let task: DayTask
    let lane: Int
    var id: UUID { task.id }
}
