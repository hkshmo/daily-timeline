import SwiftUI

struct DaylineView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var language: AppLanguage = .russian
    @AppStorage("timelineStartHour") private var timelineStartHour = 0
    @AppStorage("timelineEndHour") private var timelineEndHour = 24
    @State private var editorContext: EditorContext?
    @State private var showingCalendar = false
    @State private var showingSettings = false
    @State private var hoveredTaskID: UUID?
    @State private var hoveredDay: Date?
    @State private var dayStripStart = Calendar.current.startOfDay(for: Date())

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TimelineView(.periodic(from: .now, by: 30)) { context in
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
                suggestedStart: context.task == nil ? nextStart : nil
            ) { task, repeatWeekdays in
                context.task == nil
                    ? store.add(task, repeatWeekdays: repeatWeekdays)
                    : store.update(task, repeatWeekdays: repeatWeekdays)
            }
        }
        .sheet(isPresented: $showingSettings) {
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
                Text("Dayline")
                    .font(.title2.bold())
                Spacer()
                Button { Task { await store.synchronizeNow() } } label: {
                    if store.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: store.syncError == nil ? "icloud" : "icloud.slash")
                    }
                }
                .buttonStyle(IconBlockButtonStyle())
                .help(store.syncError ?? "iCloud")
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(IconBlockButtonStyle())
                .help(l10n.settings)
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
                .help(store.selectedDate.formatted(.dateTime.day().month(.wide).year()))
                .popover(isPresented: $showingCalendar, arrowEdge: .top) {
                    DatePicker("", selection: $store.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }
                Spacer()
            }
        }
        .padding(18)
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
                                store.delete(task)
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

private struct EditorContext: Identifiable {
    let id = UUID()
    let task: DayTask?
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
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .fontWeight(.medium)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
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
            .help(task.startedAt == nil ? L10n(language: language).startTask : L10n(language: language).undoStart)
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "stop.circle.fill" : "stop.circle")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle(tint: task.isCompleted ? .red : .primary))
            .foregroundStyle(task.isCompleted ? Color.red : Color.secondary)
            .help(task.isCompleted ? L10n(language: language).undoCompletion : L10n(language: language).completeTask)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle())
            .help(L10n(language: language).edit)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(IconBlockButtonStyle(tint: .red))
            .foregroundStyle(.red)
            .help(L10n(language: language).delete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
