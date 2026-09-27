import SwiftUI

struct MobileTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var color: TaskColor
    @State private var repeatOption: RepeatOption
    @State private var selectedWeekdays: Set<Int>
    @State private var isFlexible: Bool
    @State private var durationMinutes: Int

    private let task: DayTask?
    private let language: AppLanguage
    private let onSave: (DayTask, Set<Int>?) -> Void

    init(
        task: DayTask?,
        date: Date,
        language: AppLanguage,
        suggestedStart: Date?,
        onSave: @escaping (DayTask, Set<Int>?) -> Void
    ) {
        self.task = task
        self.language = language
        self.onSave = onSave
        let calendar = Calendar.current
        let now = Date()
        let currentStart = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: calendar.component(.minute, from: now),
            second: 0,
            of: date
        ) ?? date
        let initialStart = task?.start ?? suggestedStart ?? currentStart
        _title = State(initialValue: task?.title ?? "")
        _start = State(initialValue: initialStart)
        _end = State(initialValue: task?.end ?? initialStart.addingTimeInterval(3600))
        _color = State(initialValue: task?.color ?? TaskColor.allCases.randomElement() ?? .blue)
        let weekdays = Set(task?.repeatWeekdays ?? [])
        _repeatOption = State(initialValue: task == nil ? .daily : task?.seriesID == nil ? .once : weekdays == Set(1...7) ? .daily : .weekdays)
        _selectedWeekdays = State(initialValue: weekdays.isEmpty ? Set([2, 3, 4, 5, 6]) : weekdays)
        _isFlexible = State(initialValue: task?.isFlexible == true)
        _durationMinutes = State(initialValue: max(15, Int((task?.estimatedDuration ?? 3600) / 60)))
    }

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        NavigationStack {
            Form {
                TextField(l10n.title, text: $title)
                    .onChange(of: title) { _, value in
                        if value.count > DayTask.maximumTitleLength {
                            title = String(value.prefix(DayTask.maximumTitleLength))
                        }
                    }
                Picker(l10n.repeatMode, selection: $repeatOption) {
                    Text(l10n.todayOnly).tag(RepeatOption.once)
                    Text(l10n.everyDay).tag(RepeatOption.daily)
                    Text(l10n.selectedDays).tag(RepeatOption.weekdays)
                }
                if repeatOption == .weekdays {
                    weekdaySelector
                }
                Toggle(l10n.anytime, isOn: $isFlexible)
                if isFlexible {
                    Picker(l10n.duration, selection: $durationMinutes) {
                        ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) {
                            Text(l10n.minutes($0)).tag($0)
                        }
                    }
                } else {
                    DatePicker(l10n.start, selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(l10n.end, selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                }
                Section(l10n.color) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(TaskColor.allCases) { option in
                            Button { color = option } label: {
                                Circle()
                                    .fill(option.swiftUIColor)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if color == option {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? l10n.newBlock : l10n.editBlock)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.save, action: save)
                        .disabled(!canSave)
                }
            }
        }
        .environment(\.locale, language.locale)
    }

    private var weekdaySelector: some View {
        HStack {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                let selected = selectedWeekdays.contains(weekday)
                Button(shortWeekday(weekday)) {
                    if selected { selectedWeekdays.remove(weekday) }
                    else { selectedWeekdays.insert(weekday) }
                }
                .buttonStyle(.bordered)
                .tint(selected ? color.swiftUIColor : .secondary)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isFlexible || end > start)
            && (repeatOption != .weekdays || !selectedWeekdays.isEmpty)
    }

    private func save() {
        let resultStart: Date = if isFlexible && task?.startedAt != nil {
            task?.start ?? start
        } else if isFlexible {
            Calendar.current.startOfDay(for: start)
        } else {
            start
        }
        let resultEnd = isFlexible ? resultStart.addingTimeInterval(TimeInterval(durationMinutes * 60)) : end
        let result = DayTask(
            id: task?.id ?? UUID(),
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(DayTask.maximumTitleLength)),
            start: resultStart,
            end: resultEnd,
            color: color,
            isCompleted: task?.isCompleted ?? false,
            startedAt: task?.startedAt,
            isAutoStartSuppressed: task?.isAutoStartSuppressed,
            seriesID: task?.seriesID,
            repeatWeekdays: task?.repeatWeekdays,
            isFlexible: isFlexible,
            estimatedDuration: isFlexible ? TimeInterval(durationMinutes * 60) : nil,
            modifiedAt: task?.modifiedAt
        )
        let weekdays: Set<Int>? = switch repeatOption {
        case .once: nil
        case .daily: Set(1...7)
        case .weekdays: selectedWeekdays
        }
        onSave(result, weekdays)
        dismiss()
    }

    private func shortWeekday(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard symbols.indices.contains(weekday - 1) else { return "?" }
        return String(symbols[weekday - 1].prefix(2)).uppercased()
    }
}

private enum RepeatOption: String {
    case daily
    case once
    case weekdays
}
