import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DaylineView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var language: AppLanguage = .russian
    @AppStorage("timelineStartHour") private var timelineStartHour = 0
    @AppStorage("timelineEndHour") private var timelineEndHour = 24
    @State private var editorContext: EditorContext?
    @State private var showingCalendar = false
    @EnvironmentObject private var uiState: PopoverUIState
    @State private var hoveredTaskID: UUID?
    @State private var hoveredDay: Date?
    @State private var repeatingTaskToDelete: DayTask?
    @State private var dayStripStart = Calendar.current.startOfDay(for: Date())

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TimelineView(.everyMinute) { context in
                VStack(spacing: 18) {
                    DayTimeline(
                        date: store.selectedDate,
                        now: context.date,
                        tasks: store.tasksForDay(store.selectedDate),
                        startHour: timelineStartHour,
                        endHour: timelineEndHour,
                        highlightedTaskID: $hoveredTaskID
                    )
                    HStack {
                        Spacer()
                        ForEach(TaskKind.allCases) { kind in
                            mealButton(kind)
                        }
                        Button {
                            editorContext = EditorContext(task: nil)
                        } label: {
                            Label(l10n.add, systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    schedule
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 580)
        .background(.regularMaterial)
        .environment(\.locale, language.locale)
        .onChange(of: store.selectedDate) { _, newDate in
            if !dayStripDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: newDate) }) {
                dayStripStart = Calendar.current.startOfDay(for: newDate)
            }
        }
        .sheet(item: $editorContext) { context in
            let nextStart = store.tasksForDay(store.selectedDate)
                .filter { $0.isFlexible != true || $0.startedAt != nil }
                .map(\.end)
                .max()
            TaskEditor(
                task: context.task,
                date: store.selectedDate,
                language: language,
                suggestedStart: context.task == nil ? nextStart : nil,
                presetKind: context.presetKind
            ) { task, repeatWeekdays in
                context.task == nil
                    ? store.add(task, repeatWeekdays: repeatWeekdays)
                    : store.update(task, repeatWeekdays: repeatWeekdays)
            }
        }
        .sheet(isPresented: $uiState.showingSettings) {
            SettingsView(
                language: $language,
                timelineStartHour: $timelineStartHour,
                timelineEndHour: $timelineEndHour
            )
        }
        .alert(l10n.storageErrorTitle, isPresented: storageErrorPresented) {
            Button(l10n.done) { store.clearStorageError() }
        } message: {
            Text("\(l10n.storageErrorMessage)\n\n\(store.storageError ?? "")")
        }
        .confirmationDialog(
            l10n.deleteRepeatingTitle,
            isPresented: repeatingDeletionPresented,
            titleVisibility: .visible,
            presenting: repeatingTaskToDelete
        ) { task in
            Button(l10n.deleteOnlyThisDay, role: .destructive) { store.delete(task, scope: .thisDay) }
            Button(l10n.deleteThisAndFollowing, role: .destructive) { store.delete(task, scope: .thisAndFollowing) }
            Button(l10n.deleteWholeSeries, role: .destructive) { store.delete(task, scope: .wholeSeries) }
            Button(l10n.cancel, role: .cancel) {}
        } message: { task in
            Text(task.title)
        }
    }

    private var repeatingDeletionPresented: Binding<Bool> {
        Binding(
            get: { repeatingTaskToDelete != nil },
            set: { if !$0 { repeatingTaskToDelete = nil } }
        )
    }

    private var storageErrorPresented: Binding<Bool> {
        Binding(
            get: { store.storageError != nil },
            set: { if !$0 { store.clearStorageError() } }
        )
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text(AppBrand.fullName)
                    .font(.title2.bold())
                Spacer()
                Button { uiState.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(IconBlockButtonStyle())
            }

            HStack(spacing: 8) {
                Button { shiftDayStrip(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconBlockButtonStyle())

                ZStack {
                    HStack(spacing: 4) {
                        ForEach(dayStripDates, id: \.self) { date in
                            let selected = Calendar.current.isDate(date, inSameDayAs: store.selectedDate)
                            Button { store.selectedDate = date } label: {
                                VStack(spacing: 2) {
                                    Text(shortWeekday(for: date))
                                        .font(.caption2.weight(.semibold))
                                    Text(date, format: .dateTime.day())
                                        .font(.body.weight(.semibold))
                                }
                                .frame(width: 34, height: 40)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .background(
                                    selected
                                        ? Color.accentColor
                                        : hoveredDay == date
                                            ? Color.primary.opacity(0.09)
                                            : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .bottom) {
                                    if Calendar.current.isDateInToday(date) && !selected {
                                        Circle().fill(Color.accentColor).frame(width: 3, height: 3).padding(.bottom, 2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    hoveredDay = date
                                } else if hoveredDay == date {
                                    hoveredDay = nil
                                }
                            }
                        }
                    }
                }
                .frame(width: 186, height: 40)
                .clipped()

                Button { shiftDayStrip(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(IconBlockButtonStyle())

                Button { showingCalendar.toggle() } label: {
                    Image(systemName: "calendar")
                }
                .buttonStyle(IconBlockButtonStyle())
                .popover(isPresented: $showingCalendar, arrowEdge: .top) {
                    DatePicker("", selection: $store.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }
                Spacer(minLength: 8)
                DayStatusView(
                    language: language,
                    isShowingToday: isShowingToday,
                    onReturnToToday: returnToToday
                )
                // Сначала место получает эта панель, а Spacer — только то, что осталось.
                // Без этого SwiftUI делит место поровну и обрезает название задачи.
                .layoutPriority(1)
            }
        }
        .padding(18)
    }

    /// Кнопка приёма пищи. Если он уже есть в этот день — показывает иконку и время
    /// и открывает его на редактирование; иначе — добавляет новый с временем по умолчанию.
    @ViewBuilder
    private func mealButton(_ kind: TaskKind) -> some View {
        if let meal = store.tasksForDay(store.selectedDate).first(where: { $0.kind == kind }) {
            let time = meal.start.formatted(.dateTime.hour().minute().locale(language.locale))
            Button {
                editorContext = EditorContext(task: meal)
            } label: {
                Label(time, systemImage: kind.systemImage)
            }
            .controlSize(.small)
            .foregroundStyle(meal.color.swiftUIColor)
        } else {
            Button {
                editorContext = EditorContext(task: nil, presetKind: kind)
            } label: {
                Label(l10n.name(of: kind), systemImage: kind.systemImage)
            }
            .controlSize(.small)
        }
    }

    /// Выбран сегодняшний день и он виден в полосе дней.
    private var isShowingToday: Bool {
        Calendar.current.isDateInToday(store.selectedDate)
            && dayStripDates.contains { Calendar.current.isDateInToday($0) }
    }

    private func returnToToday() {
        store.selectedDate = Date()
        dayStripStart = Calendar.current.startOfDay(for: Date())
    }

    private var dayStripDates: [Date] {
        (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: dayStripStart) }
    }

    private func shiftDayStrip(by days: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: dayStripStart) else { return }
        dayStripStart = date
    }

    private func shortWeekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "EE"
        return String(formatter.string(from: date).prefix(2)).capitalized(with: language.locale)
    }

    private var schedule: some View {
        let tasks = store.tasksForDay(store.selectedDate)
        let currentTaskID = tasks.first(where: { $0.startedAt != nil && !$0.isCompleted })?.id
        return Group {
            if tasks.isEmpty {
                ContentUnavailableView(l10n.emptyTitle, systemImage: "sun.max", description: Text(l10n.emptyDescription))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(tasks) { task in
                            TaskRow(
                                task: task,
                                language: language,
                                isHighlighted: hoveredTaskID == task.id,
                                isCurrent: currentTaskID == task.id
                            ) {
                                store.toggle(task)
                            } onStart: {
                                store.toggleStart(task)
                            } onEdit: {
                                editorContext = EditorContext(task: task)
                            } onDelete: {
                                if task.seriesID != nil {
                                    repeatingTaskToDelete = task
                                } else {
                                    store.delete(task)
                                }
                            }
                            .onHover { hovering in
                                if hovering {
                                    hoveredTaskID = task.id
                                } else if hoveredTaskID == task.id {
                                    hoveredTaskID = nil
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(l10n.blocks(store.tasksForDay(store.selectedDate).count))
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Button(l10n.quit) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Text("\(l10n.developer): hkshmo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .frame(height: 48)
    }
}

/// Справа от полосы дней: что идёт сейчас и что дальше, а если открыт другой день — кнопка «Сегодня».
private struct DayStatusView: View {
    @EnvironmentObject private var store: TaskStore
    let language: AppLanguage
    let isShowingToday: Bool
    let onReturnToToday: () -> Void

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        if isShowingToday {
            TimelineView(.everyMinute) { context in
                status(at: context.date)
            }
        } else {
            Button(action: onReturnToToday) {
                Label(l10n.today, systemImage: "arrow.uturn.backward")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func status(at now: Date) -> some View {
        // Только задачи с временем: «в любое время» без запуска на шкале не стоят.
        let tasks = store.tasksForDay(now).filter {
            !$0.isCompleted && ($0.isFlexible != true || $0.startedAt != nil)
        }
        let current = tasks.first { $0.startedAt != nil && $0.start <= now && now < $0.end }
            ?? tasks.last { $0.start <= now && now < $0.end }
        let next = tasks.first { $0.start > now && $0.id != current?.id }

        // Места справа от полосы дней мало (~190 pt), поэтому показываем одну задачу —
        // текущую, а если её нет, то следующую — в две короткие строки.
        // Полная информация (и «сейчас», и «далее») — во всплывающей подсказке.
        let focus = current ?? next
        VStack(alignment: .trailing, spacing: 2) {
            if let focus {
                Text(current != nil
                    ? "\(l10n.nowShort) · \(l10n.remaining(focus.end.timeIntervalSince(now)))"
                    : "\(l10n.nextShort) · \(l10n.startsIn(focus.start.timeIntervalSince(now)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(focus.color.swiftUIColor)
                        .frame(width: 7, height: 7)
                    Text(focus.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text(l10n.nothingLeftToday)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tooltip(current: DayTask?, next: DayTask?, now: Date) -> String {
        var lines: [String] = []
        if let current {
            lines.append("\(l10n.nowLabel) \(current.title) · \(l10n.remaining(current.end.timeIntervalSince(now)))")
        }
        if let next {
            let time = next.start.formatted(.dateTime.hour().minute().locale(language.locale))
            lines.append("\(l10n.nextLabel) \(next.title) · \(l10n.at(time))")
        }
        return lines.isEmpty ? l10n.nothingLeftToday : lines.joined(separator: "\n")
    }
}

private struct EditorContext: Identifiable {
    let id = UUID()
    let task: DayTask?
    var presetKind: TaskKind?
}

private struct TaskRow: View {
    let task: DayTask
    let language: AppLanguage
    let isHighlighted: Bool
    let isCurrent: Bool
    let onToggle: () -> Void
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(task.color.swiftUIColor)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let kind = task.kind {
                        Image(systemName: kind.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(task.color.swiftUIColor)
                    }
                    Text(task.title)
                        .fontWeight(.medium)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                }
                HStack(spacing: 6) {
                    if task.isFlexible == true && task.startedAt == nil {
                        Text("\(L10n(language: language).anytime) · \(L10n(language: language).minutes(Int((task.estimatedDuration ?? 3600) / 60)))")
                            .lineLimit(1)
                    } else {
                        Text("\(task.start.formatted(.dateTime.hour().minute().locale(language.locale))) – \(task.end.formatted(.dateTime.hour().minute().locale(language.locale)))")
                    }
                    Text(repeatLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer()
            Button(action: onStart) {
                Image(systemName: task.startedAt == nil ? "play.circle" : "play.circle.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle())
            .foregroundStyle(task.startedAt == nil ? Color.secondary : Color.green)
            .disabled(task.isCompleted)
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "stop.circle.fill" : "stop.circle")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle(tint: task.isCompleted ? .red : .primary))
            .foregroundStyle(task.isCompleted ? Color.red : Color.secondary)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle())
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle(tint: .red))
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            isHighlighted
                ? task.color.swiftUIColor.opacity(0.16)
                : isCurrent
                    ? task.color.swiftUIColor.opacity(0.075)
                    : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHighlighted
                        ? task.color.swiftUIColor.opacity(0.55)
                        : isCurrent
                            ? task.color.swiftUIColor.opacity(0.2)
                            : .clear,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.12), value: isHighlighted || isCurrent)
    }

    private var repeatLabel: String {
        let l10n = L10n(language: language)
        guard task.seriesID != nil else { return l10n.todayOnly }
        return Set(task.repeatWeekdays ?? Array(1...7)) == Set(1...7)
            ? l10n.everyDay
            : l10n.selectedDays
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var language: AppLanguage
    @Binding var timelineStartHour: Int
    @Binding var timelineEndHour: Int
    @AppStorage("taskNotifications") private var taskNotifications = true
    @AppStorage(NotificationSoundPreferences.enabledKey) private var soundNotifications = true
    @AppStorage(NotificationSoundPreferences.nameKey) private var customSoundName = ""
    @AppStorage(WarmupReminderPlan.enabledKey) private var warmupReminders = true
    @AppStorage(WarmupReminderPlan.intervalKey) private var warmupInterval = WarmupReminderPlan.defaultIntervalMinutes
    @State private var previewSound: NSSound?
    @State private var soundError: String?

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(l10n.settings).font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(IconBlockButtonStyle())
                    .foregroundStyle(.secondary)
            }
            Picker(l10n.languageLabel, selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Toggle(l10n.notifications, isOn: $taskNotifications)
            Toggle(l10n.soundNotifications, isOn: $soundNotifications)
                .disabled(!taskNotifications)
            if soundNotifications && taskNotifications {
                VStack(alignment: .leading, spacing: 8) {
                    Text(customSoundName.isEmpty ? l10n.systemSound : customSoundName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack {
                        Button(l10n.chooseSound) { chooseSound() }
                        Button(l10n.previewSound) { playPreview() }
                        if !customSoundName.isEmpty {
                            Button(l10n.systemSound) {
                                NotificationSoundPreferences.useSystemSound()
                                customSoundName = ""
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }

            Divider()
            Toggle(l10n.warmupReminders, isOn: $warmupReminders)
            if warmupReminders {
                Picker(l10n.warmupInterval, selection: $warmupInterval) {
                    ForEach(WarmupReminderPlan.intervalOptions, id: \.self) { minutes in
                        Text(l10n.duration(TimeInterval(minutes * 60))).tag(minutes)
                    }
                }
                Text(l10n.warmupHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Text(l10n.timelineRange)
                .font(.headline)
            HStack {
                Picker(l10n.from, selection: $timelineStartHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                Picker(l10n.to, selection: $timelineEndHour) {
                    ForEach(1...24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
            }
            HStack {
                Button(l10n.fullDay) {
                    timelineStartHour = 0
                    timelineEndHour = 24
                }
                Button(l10n.workDay) {
                    timelineStartHour = 9
                    timelineEndHour = 18
                }
            }
            .controlSize(.small)
        }
        .padding(24)
        .frame(width: 360)
        .onChange(of: timelineStartHour) { _, value in
            if value >= timelineEndHour { timelineEndHour = min(24, value + 1) }
        }
        .onChange(of: timelineEndHour) { _, value in
            if value <= timelineStartHour { timelineStartHour = max(0, value - 1) }
        }
        .alert(l10n.soundFileError, isPresented: soundErrorPresented) {
            Button(l10n.done) { soundError = nil }
        } message: {
            Text(soundError ?? "")
        }
    }

    private var soundErrorPresented: Binding<Bool> {
        Binding(get: { soundError != nil }, set: { if !$0 { soundError = nil } })
    }

    private func chooseSound() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try NotificationSoundPreferences.select(url)
                customSoundName = url.lastPathComponent
                playPreview()
            } catch {
                soundError = error.localizedDescription
            }
        }
    }

    private func playPreview() {
        previewSound?.stop()
        previewSound = NotificationSoundPreferences.makeSound()
        guard previewSound?.play() == true else {
            soundError = l10n.soundFileError
            return
        }
    }
}

struct IconBlockButtonStyle: ButtonStyle {
    let tint: Color

    init(tint: Color = .primary) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        IconBlockButtonBody(configuration: configuration, tint: tint)
    }
}

private struct IconBlockButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    @State private var hovering = false

    var body: some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(
                hovering || configuration.isPressed ? tint.opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}
