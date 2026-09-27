import SwiftUI

struct DaylineMobileView: View {
    @EnvironmentObject private var store: TaskStore
    @AppStorage("appLanguage") private var language: AppLanguage = .russian
    @AppStorage("timelineStartHour") private var timelineStartHour = 0
    @AppStorage("timelineEndHour") private var timelineEndHour = 24
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorContext: MobileEditorContext?
    @State private var showingCalendar = false
    @State private var showingSettings = false

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayPicker
                if let error = store.syncError {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                        Text(error).lineLimit(2)
                        Spacer()
                        Button { store.clearSyncError() } label: { Image(systemName: "xmark") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                Divider()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView {
                        VStack(spacing: 16) {
                            MobileTimeline(
                                date: store.selectedDate,
                                now: context.date,
                                tasks: store.tasksForDay(store.selectedDate),
                                startHour: timelineStartHour,
                                endHour: timelineEndHour
                            )
                            taskList
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dayline")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await store.synchronizeNow() } } label: {
                        if store.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: store.syncError == nil ? "icloud" : "icloud.slash")
                        }
                    }
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    Button { editorContext = MobileEditorContext(task: nil) } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .environment(\.locale, language.locale)
        .task {
            while !Task.isCancelled {
                await store.synchronizeNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let now = Date()
            store.completeExpiredTasks(at: now)
            store.startCurrentScheduledTask(at: now)
            Task { await store.synchronizeNow() }
        }
        .sheet(item: $editorContext) { context in
            MobileTaskEditor(
                task: context.task,
                date: store.selectedDate,
                language: language,
                suggestedStart: context.task == nil ? suggestedStart : nil
            ) { task, weekdays in
                if context.task == nil {
                    store.add(task, repeatWeekdays: weekdays)
                } else {
                    store.update(task, repeatWeekdays: weekdays)
                }
            }
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                DatePicker("", selection: $store.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle(l10n.today)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(l10n.done) { showingCalendar = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSettings) {
            MobileSettingsView(
                language: $language,
                timelineStartHour: $timelineStartHour,
                timelineEndHour: $timelineEndHour
            )
        }
        .alert(l10n.storageErrorTitle, isPresented: storageErrorPresented) {
            Button(l10n.done) { store.clearStorageError() }
        } message: {
            Text(store.storageError ?? "")
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 4) {
            ForEach(dayDates, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: store.selectedDate)
                Button { store.selectedDate = date } label: {
                    VStack(spacing: 4) {
                        Text(shortWeekday(date))
                            .font(.caption2.weight(.semibold))
                        Text(date, format: .dateTime.day())
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(selected ? .white : .primary)
                    .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { showingCalendar = true } label: {
                Image(systemName: "calendar")
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var taskList: some View {
        let tasks = store.tasksForDay(store.selectedDate)
        if tasks.isEmpty {
            ContentUnavailableView(
                l10n.emptyTitle,
                systemImage: "sun.max",
                description: Text(l10n.emptyDescription)
            )
            .padding(.top, 70)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(tasks) { task in
                    MobileTaskRow(
                        task: task,
                        language: language,
                        onStart: { store.toggleStart(task) },
                        onComplete: { store.toggle(task) },
                        onEdit: { editorContext = MobileEditorContext(task: task) },
                        onDelete: { store.delete(task) }
                    )
                }
            }
        }
    }

    private var suggestedStart: Date? {
        store.tasksForDay(store.selectedDate)
            .filter { $0.isFlexible != true || $0.startedAt != nil }
            .map(\.end)
            .max()
    }

    private var dayDates: [Date] {
        let calendar = Calendar.current
        let selected = calendar.startOfDay(for: store.selectedDate)
        return (-2...2).compactMap { calendar.date(byAdding: .day, value: $0, to: selected) }
    }

    private func shortWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "EE"
        return String(formatter.string(from: date).prefix(2)).capitalized(with: language.locale)
    }

    private var storageErrorPresented: Binding<Bool> {
        Binding(get: { store.storageError != nil }, set: { if !$0 { store.clearStorageError() } })
    }

}

private struct MobileTimeline: View {
    let date: Date
    let now: Date
    let tasks: [DayTask]
    let startHour: Int
    let endHour: Int

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    ForEach(tasks.filter(isVisible)) { task in
                        Capsule()
                            .fill(task.color.swiftUIColor.opacity(task.isCompleted ? 0.35 : 0.9))
                            .frame(width: max(5, proxy.size.width * (fraction(task.end) - fraction(task.start))))
                            .offset(x: proxy.size.width * fraction(task.start))
                    }
                    if Calendar.current.isDateInToday(date) {
                        Rectangle()
                            .fill(.primary)
                            .frame(width: 2, height: 30)
                            .offset(x: min(proxy.size.width - 2, proxy.size.width * fraction(now)))
                    }
                }
            }
            .frame(height: 22)
            HStack {
                Text(hour(startHour))
                Spacer()
                Text(hour((startHour + endHour) / 2))
                Spacer()
                Text(hour(endHour))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func isVisible(_ task: DayTask) -> Bool {
        task.isFlexible != true && seconds(task.end) > startHour * 3600 && seconds(task.start) < endHour * 3600
    }

    private func fraction(_ date: Date) -> CGFloat {
        let duration = max(1, (endHour - startHour) * 3600)
        return min(1, max(0, CGFloat(seconds(date) - startHour * 3600) / CGFloat(duration)))
    }

    private func seconds(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    private func hour(_ value: Int) -> String { String(format: "%02d", value) }
}

private struct MobileTaskRow: View {
    let task: DayTask
    let language: AppLanguage
    let onStart: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(task.color.swiftUIColor)
                    .frame(width: 4, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.isCompleted)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button(action: onStart) {
                    Label(task.startedAt == nil ? l10n.startTask : l10n.undoStart,
                          systemImage: task.startedAt == nil ? "play.fill" : "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.isCompleted)
                Button(action: onComplete) {
                    Image(systemName: task.isCompleted ? "arrow.uturn.backward.circle" : "stop.circle")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.bordered)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.bordered)
            }
            .labelStyle(.iconOnly)
        }
        .padding(14)
        .background(
            task.startedAt != nil && !task.isCompleted
                ? task.color.swiftUIColor.opacity(0.1)
                : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var timeText: String {
        if task.isFlexible == true && task.startedAt == nil {
            return "\(l10n.anytime) · \(l10n.minutes(Int((task.estimatedDuration ?? 3600) / 60)))"
        }
        return "\(task.start.formatted(.dateTime.hour().minute().locale(language.locale))) – \(task.end.formatted(.dateTime.hour().minute().locale(language.locale)))"
    }
}

private struct MobileEditorContext: Identifiable {
    let id = UUID()
    let task: DayTask?
}

private struct MobileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var language: AppLanguage
    @Binding var timelineStartHour: Int
    @Binding var timelineEndHour: Int

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        NavigationStack {
            Form {
                Picker(l10n.languageLabel, selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Section(l10n.timelineRange) {
                    Picker(l10n.from, selection: $timelineStartHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Picker(l10n.to, selection: $timelineEndHour) {
                        ForEach(1...24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Button(l10n.fullDay) { timelineStartHour = 0; timelineEndHour = 24 }
                    Button(l10n.workDay) { timelineStartHour = 9; timelineEndHour = 18 }
                }
                Section {
                    LabeledContent(l10n.developer, value: "hkshmo")
                }
            }
            .navigationTitle(l10n.settings)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.done) { dismiss() }
                }
            }
        }
        .onChange(of: timelineStartHour) { _, value in
            if value >= timelineEndHour { timelineEndHour = min(24, value + 1) }
        }
        .onChange(of: timelineEndHour) { _, value in
            if value <= timelineStartHour { timelineStartHour = max(0, value - 1) }
        }
    }
}
