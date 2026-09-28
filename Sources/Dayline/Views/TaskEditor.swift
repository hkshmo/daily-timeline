import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var color: TaskColor
    @State private var repeatOption: TaskRepeatOption
    @State private var selectedWeekdays: Set<Int>
    @State private var timingOption: TaskTimingOption
    @State private var durationMinutes: Int

    private let task: DayTask?
    private let language: AppLanguage
    private let onSave: (DayTask, Set<Int>?) -> Void

    init(
        task: DayTask?,
        date: Date,
        language: AppLanguage,
        suggestedStart: Date? = nil,
        onSave: @escaping (DayTask, Set<Int>?) -> Void
    ) {
        self.task = task
        self.language = language
        self.onSave = onSave
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        let initialStart = task?.start ?? suggestedStart ?? currentStart
        _title = State(initialValue: task?.title ?? "")
        _start = State(initialValue: initialStart)
        _end = State(initialValue: task?.end ?? calendar.date(byAdding: .hour, value: 1, to: initialStart)!)
        _color = State(initialValue: task?.color ?? TaskColor.allCases.randomElement() ?? .blue)
        let weekdays = Set(task?.repeatWeekdays ?? (task?.seriesID == nil ? [] : Array(1...7)))
        if task == nil {
            _repeatOption = State(initialValue: .daily)
        } else if task?.seriesID == nil {
            _repeatOption = State(initialValue: .once)
        } else if weekdays == Set(1...7) {
            _repeatOption = State(initialValue: .daily)
        } else {
            _repeatOption = State(initialValue: .weekdays)
        }
        _selectedWeekdays = State(initialValue: weekdays.isEmpty ? Set([2, 3, 4, 5, 6]) : weekdays)
        _timingOption = State(initialValue: task?.isFlexible == true ? .flexible : .fixed)
        let duration = task?.estimatedDuration ?? task?.end.timeIntervalSince(task?.start ?? initialStart) ?? 3600
        _durationMinutes = State(initialValue: max(15, Int(duration / 60)))
    }

    var body: some View {
        let l10n = L10n(language: language)
        VStack(alignment: .leading, spacing: 18) {
            Text(task == nil ? l10n.newBlock : l10n.editBlock)
                .font(.title2.bold())
            TextField(l10n.title, text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, value in
                    if value.count > DayTask.maximumTitleLength {
                        title = String(value.prefix(DayTask.maximumTitleLength))
                    }
                }
            Picker(l10n.repeatMode, selection: $repeatOption) {
                Text(l10n.todayOnly).tag(TaskRepeatOption.once)
                Text(l10n.everyDay).tag(TaskRepeatOption.daily)
                Text(l10n.selectedDays).tag(TaskRepeatOption.weekdays)
            }
            .pickerStyle(.segmented)
            if repeatOption == .weekdays {
                HStack(spacing: 6) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        let selected = selectedWeekdays.contains(weekday)
                        Button(shortWeekday(weekday)) {
                            if selected { selectedWeekdays.remove(weekday) }
                            else { selectedWeekdays.insert(weekday) }
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? color.swiftUIColor : .secondary)
                        .controlSize(.small)
                    }
                }
            }
            Picker(l10n.timingMode, selection: $timingOption) {
                Text(l10n.fixedTime).tag(TaskTimingOption.fixed)
                Text(l10n.anytime).tag(TaskTimingOption.flexible)
            }
            .pickerStyle(.segmented)
            if timingOption == .fixed {
                HStack {
                    DatePicker(l10n.start, selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(l10n.end, selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                }
            } else {
                Picker(l10n.duration, selection: $durationMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                        Text(l10n.minutes(minutes)).tag(minutes)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.color).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(TaskColor.allCases) { option in
                        Button { color = option } label: {
                            Circle()
                                .fill(option.swiftUIColor)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if color == option { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                                }
                        }
                        .buttonStyle(IconBlockButtonStyle(tint: option.swiftUIColor))
                    }
                }
            }
            HStack {
                Spacer()
                Button(l10n.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l10n.save) {
                    let flexible = timingOption == .flexible
                    let flexibleStart: Date = if task?.startedAt != nil && task?.isFlexible == true {
                        task?.start ?? start
                    } else {
                        Calendar.current.startOfDay(for: start)
                    }
                    let resultStart = flexible ? flexibleStart : start
                    let resultEnd = flexible
                        ? resultStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
                        : end
                    let result = DayTask(
                        id: task?.id ?? UUID(),
                        title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(DayTask.maximumTitleLength)),
                        start: resultStart, end: resultEnd, color: color,
                        isCompleted: task?.isCompleted ?? false,
                        startedAt: task?.startedAt,
                        isAutoStartSuppressed: task?.isAutoStartSuppressed,
                        seriesID: task?.seriesID,
                        repeatWeekdays: task?.repeatWeekdays,
                        isFlexible: flexible,
                        estimatedDuration: flexible ? TimeInterval(durationMinutes * 60) : nil,
                        occurrenceDate: task?.occurrenceDate
                    )
                    let weekdays: Set<Int>? = switch repeatOption {
                    case .once: nil
                    case .daily: Set(1...7)
                    case .weekdays: selectedWeekdays
                    }
                    onSave(result, weekdays)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (timingOption == .fixed && end <= start)
                        || (repeatOption == .weekdays && selectedWeekdays.isEmpty)
                )
            }
        }
        .padding(24)
        .frame(width: 460)
        .environment(\.locale, language.locale)
    }

    private func shortWeekday(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard symbols.indices.contains(weekday - 1) else { return "?" }
        return String(symbols[weekday - 1].prefix(2)).uppercased()
    }
}

private enum TaskRepeatOption: String {
    case daily
    case once
    case weekdays
}

private enum TaskTimingOption: String {
    case fixed
    case flexible
}
