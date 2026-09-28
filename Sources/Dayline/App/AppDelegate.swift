import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let uiState = PopoverUIState()
    private let popover = NSPopover()
    private let notificationPopover = NSPopover()
    private var statusItem: NSStatusItem?
    private var eventTimer: Timer?
    private var taskObserver: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var notifiedTaskStarts: [UUID: Date] = [:]
    private var isClosingPopovers = false
    private var notificationSound: NSSound?
    private var systemObservers: [NSObjectProtocol] = []
    private var warmupTimer: Timer?
    private var lastBreakAt = Date()
    private var warmupSnoozedUntil: Date?
    private var screenLockedAt: Date?
    /// Что сейчас показано в окне уведомления.
    private var shownNotification: ShownNotification?
    /// Задача, уведомление о начале которой отложено, пока в окне открыт редактор.
    private var pendingTaskNotificationID: UUID?
    private var pendingNotificationTimer: Timer?

    private enum ShownNotification {
        case task
        case warmup
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPreferencesIfNeeded()
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = DaylineStatusIcon.make(isActive: false, at: Date())
            button.imagePosition = .imageOnly
            button.toolTip = AppBrand.fullName
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 520, height: 580)
        popover.contentViewController = NSHostingController(
            rootView: DaylineView().environmentObject(store).environmentObject(uiState)
        )
        // Уведомления не закрываются кликом мимо — только кнопками. Иначе их легко пропустить:
        // человек работает, кликает в своё окно, и уведомление исчезает, не успев попасться на глаза.
        notificationPopover.behavior = .applicationDefined
        statusItem = item
        refreshStatusIcon()

        taskObserver = store.$revision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshStatusIcon()
                    self?.scheduleNextEvent()
                }
            }

        checkTaskNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive), name: NSApplication.didResignActiveNotification,
            object: nil
        )
        // Смена дня, перевод системных часов и смена часового пояса: таймер стоит
        // на конкретное время, поэтому после таких событий его нужно пересчитать.
        // Эти уведомления могут приходить не на главном потоке — принимаем их на .main.
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.systemTimeDidChange()
                }
            }
            systemObservers.append(token)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(checkTaskNotifications), name: NSWorkspace.didWakeNotification,
            object: nil
        )
        setUpWarmupReminders()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            let clickLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard self?.statusItemFrame.contains(clickLocation) != true else { return }
                self?.closeVisiblePopovers()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        closeNotification()
        if popover.isShown {
            if !mainPopoverHasSheet || uiState.showingSettings { closeVisiblePopovers() }
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func checkTaskNotifications() {
        let now = Date()
        store.completeExpiredTasks(at: now)
        store.startCurrentScheduledTask(at: now)
        refreshStatusIcon()
        defer { scheduleNextEvent() }
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "taskNotifications") as? Bool ?? true
        guard enabled else { return }

        let dayTasks = store.tasksForDay(now)
        let tasks = dayTasks.filter { !$0.isCompleted && $0.isFlexible != true }
        let starting = tasks.first { task in
            // Обычно уведомляем в первую минуту задачи. Отложенное (пока был открыт редактор)
            // показываем позже — но только пока задача ещё идёт.
            let isOnTime = now.timeIntervalSince(task.start) < 60
            let isPending = task.id == pendingTaskNotificationID && now < task.end
            return notifiedTaskStarts[task.id] != task.start
                && task.start <= now
                && (isOnTime || isPending)
                && task.startedAt.map { $0 >= task.start } == true
        }

        guard let task = starting else {
            pendingTaskNotificationID = nil
            return
        }
        // Открыт редактор задачи или настройки: не закрываем их (там может быть несохранённый ввод),
        // а откладываем уведомление и проверяем снова через 30 секунд.
        if mainPopoverHasSheet {
            pendingTaskNotificationID = task.id
            pendingNotificationTimer?.invalidate()
            pendingNotificationTimer = Timer.scheduledTimer(
                timeInterval: 30,
                target: self,
                selector: #selector(checkTaskNotifications),
                userInfo: nil,
                repeats: false
            )
            return
        }
        pendingTaskNotificationID = nil
        pendingNotificationTimer?.invalidate()
        pendingNotificationTimer = nil
        // Если висит старое уведомление о задаче, новое его заменит.
        let previousTask = dayTasks
            .filter { $0.id != task.id && $0.isCompleted && $0.end <= task.start }
            .max { $0.end < $1.end }
        notifiedTaskStarts[task.id] = task.start
        showTaskNotification(task, previousTask: previousTask)
    }

    private func systemTimeDidChange() {
        NSTimeZone.resetSystemTimeZone()
        checkTaskNotifications()
    }

    private func scheduleNextEvent() {
        eventTimer?.invalidate()
        eventTimer = nil
        guard let date = store.nextScheduledEvent(after: Date()) else { return }

        let timer = Timer(
            fireAt: date.addingTimeInterval(0.05),
            interval: 0,
            target: self,
            selector: #selector(checkTaskNotifications),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        eventTimer = timer
    }

    private func migrateLegacyPreferencesIfNeeded() {
        let migrationKey = "didMigratePreferencesFromComDaylineApp"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey),
              let legacy = defaults.persistentDomain(forName: "com.dayline.app") else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        let keys = [
            "appLanguage", "timelineStartHour", "timelineEndHour", "taskNotifications",
            NotificationSoundPreferences.enabledKey,
            NotificationSoundPreferences.bookmarkKey,
            NotificationSoundPreferences.nameKey
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            defaults.set(legacy[key], forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
    }

    @objc private func applicationDidResignActive() {
        closeVisiblePopovers()
    }

    private func closeVisiblePopovers() {
        guard !isClosingPopovers else { return }
        isClosingPopovers = true
        if popover.isShown && uiState.showingSettings {
            // Настройки применяются сразу, терять нечего: закрываем лист и само окно.
            // Окно закрываем чуть позже — пока лист висит, NSPopover закрываться отказывается.
            uiState.showingSettings = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.popover.isShown, !self.mainPopoverHasSheet else { return }
                self.popover.performClose(nil)
            }
        } else if popover.isShown && !mainPopoverHasSheet {
            // Редактор задачи оставляем открытым, чтобы не потерять несохранённый ввод.
            popover.performClose(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isClosingPopovers = false
        }
    }

    /// Закрыть уведомление. Если это было «размяться» и его закрыли не кнопкой
    /// (например, открыли главное окно или его заменило уведомление о задаче) — напомним позже.
    private func closeNotification() {
        if shownNotification == .warmup, warmupSnoozedUntil == nil || warmupSnoozedUntil! < Date() {
            warmupSnoozedUntil = Date().addingTimeInterval(TimeInterval(WarmupReminderPlan.snoozeMinutes * 60))
            scheduleWarmupReminder()
        }
        shownNotification = nil
        if notificationPopover.isShown { notificationPopover.performClose(nil) }
    }

    /// По умолчанию окно живёт на том рабочем столе, где появилось: переключились на другой
    /// стол — уведомления не видно. Разрешаем ему быть на всех столах и поверх полноэкранных приложений.
    private func showNotificationOnAllSpaces() {
        guard let window = notificationPopover.contentViewController?.view.window else { return }
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
    }

    private var mainPopoverHasSheet: Bool {
        guard let window = popover.contentViewController?.view.window else { return false }
        return window.attachedSheet != nil || !window.sheets.isEmpty
    }

    private var statusItemFrame: NSRect {
        guard let button = statusItem?.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func refreshStatusIcon() {
        let now = Date()
        let active = store.tasksForDay(now).contains {
            !$0.isCompleted
                && $0.startedAt != nil
                && now < $0.end
        }
        statusItem?.button?.image = DaylineStatusIcon.make(isActive: active, at: now)
    }

    // MARK: - Напоминание размяться

    private func setUpWarmupReminders() {
        // Настройки меняются в окне настроек — пересчитываем таймер.
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWarmupReminder() }
        })
        // Сон Mac — это перерыв.
        systemObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerBreak() }
        })
        // Экран был заблокирован достаточно долго — тоже перерыв.
        let distributed = DistributedNotificationCenter.default()
        systemObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLockedAt = Date() }
        })
        systemObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let lockedAt = self.screenLockedAt,
                   Date().timeIntervalSince(lockedAt) >= WarmupReminderPlan.awayThreshold {
                    self.registerBreak()
                }
                self.screenLockedAt = nil
            }
        })
        scheduleWarmupReminder()
    }

    private func registerBreak(at date: Date = Date()) {
        lastBreakAt = date
        warmupSnoozedUntil = nil
        scheduleWarmupReminder()
    }

    private func scheduleWarmupReminder() {
        warmupTimer?.invalidate()
        warmupTimer = nil
        guard WarmupReminderPlan.isEnabled else { return }
        let date = WarmupReminderPlan.nextReminder(
            lastBreakAt: lastBreakAt,
            snoozedUntil: warmupSnoozedUntil,
            intervalMinutes: WarmupReminderPlan.intervalMinutes
        )
        let timer = Timer(
            fireAt: max(date, Date().addingTimeInterval(1)),
            interval: 0,
            target: self,
            selector: #selector(warmupTimerFired),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        warmupTimer = timer
    }

    @objc private func warmupTimerFired() {
        let now = Date()
        guard WarmupReminderPlan.isEnabled else { return }

        // Мышь и клавиатура давно не трогались — человек и так отошёл.
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= WarmupReminderPlan.awayThreshold {
            registerBreak(at: now)
            return
        }
        // Идёт завтрак/обед/ужин — перерыв уже есть, отсчёт начнётся после него.
        if let meal = store.tasksForDay(now).first(where: {
            $0.kind != nil && !$0.isCompleted && $0.start <= now && now < $0.end
        }) {
            registerBreak(at: meal.end)
            return
        }
        // Сейчас открыто другое окно — попробуем через минуту.
        guard let button = statusItem?.button, !notificationPopover.isShown, !mainPopoverHasSheet else {
            warmupSnoozedUntil = now.addingTimeInterval(60)
            scheduleWarmupReminder()
            return
        }
        showWarmupReminder(from: button, now: now)
    }

    private func showWarmupReminder(from button: NSStatusBarButton, now: Date) {
        if popover.isShown { popover.performClose(nil) }

        let soundEnabled = UserDefaults.standard.object(forKey: NotificationSoundPreferences.enabledKey) as? Bool ?? true
        if soundEnabled {
            notificationSound?.stop()
            notificationSound = NotificationSoundPreferences.makeSound()
            notificationSound?.play()
        }

        let rawLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.russian.rawValue
        let language = AppLanguage(rawValue: rawLanguage) ?? .russian
        let snooze = TimeInterval(WarmupReminderPlan.snoozeMinutes * 60)
        let view = WarmupReminderView(
            language: language,
            minutes: max(1, Int(now.timeIntervalSince(lastBreakAt) / 60)),
            onDone: { [weak self] in
                self?.registerBreak()
                self?.closeNotification()
            },
            onSnooze: { [weak self] in
                guard let self else { return }
                self.warmupSnoozedUntil = Date().addingTimeInterval(snooze)
                self.scheduleWarmupReminder()
                self.closeNotification()
            }
        )
        notificationPopover.contentSize = NSSize(width: 340, height: 132)
        notificationPopover.contentViewController = FirstClickHostingController(rootView: view)
        // Без activate: уведомление появляется, но не отбирает фокус у приложения, в котором вы работаете.
        notificationPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        showNotificationOnAllSpaces()
        shownNotification = .warmup
        // Висит, пока не нажмут кнопку, — повторный таймер не нужен.
        warmupTimer?.invalidate()
        warmupTimer = nil
    }

    private func showTaskNotification(_ task: DayTask, previousTask: DayTask?) {
        guard let button = statusItem?.button, !mainPopoverHasSheet else { return }
        if popover.isShown { popover.performClose(nil) }
        // Если висело «размяться» — заменяем его (начало задачи важнее), а размяться напомним позже.
        if shownNotification == .warmup { closeNotification() }

        let soundEnabled = UserDefaults.standard.object(forKey: NotificationSoundPreferences.enabledKey) as? Bool ?? true
        if soundEnabled {
            notificationSound?.stop()
            notificationSound = NotificationSoundPreferences.makeSound()
            notificationSound?.play()
        }

        let rawLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.russian.rawValue
        let language = AppLanguage(rawValue: rawLanguage) ?? .russian
        let view = TaskNotificationView(
            task: task,
            previousTask: previousTask,
            language: language,
            onPostpone: { [weak self] minutes in
                self?.store.postpone(task, by: minutes)
                self?.closeNotification()
            },
            onStart: { [weak self] in
                self?.store.toggleStart(task)
                self?.refreshStatusIcon()
                self?.closeNotification()
            },
            onComplete: { [weak self] in
                self?.store.complete(task)
                self?.refreshStatusIcon()
                self?.closeNotification()
            },
            onDismiss: { [weak self] in
                self?.closeNotification()
            }
        )
        notificationPopover.contentSize = NSSize(width: 380, height: previousTask == nil ? 142 : 166)
        notificationPopover.contentViewController = FirstClickHostingController(rootView: view)
        // Без activate: уведомление не отбирает фокус у приложения, в котором вы работаете.
        notificationPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        showNotificationOnAllSpaces()
        shownNotification = .task
    }
}

/// Уведомления показываются без активации приложения, а в неактивном окне macOS
/// по умолчанию «съедает» первый клик. Эта обёртка принимает клик сразу,
/// чтобы «Понятно» срабатывало с первого нажатия.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstClickHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FirstClickHostingView(rootView: rootView)
    }
}

/// Состояние окна, которое нужно знать AppDelegate: например, открыты ли настройки.
@MainActor
final class PopoverUIState: ObservableObject {
    @Published var showingSettings = false
}

/// Настройки и расчёт напоминаний размяться.
@MainActor
enum WarmupReminderPlan {
    static let enabledKey = "warmupReminders"
    static let intervalKey = "warmupIntervalMinutes"
    static let defaultIntervalMinutes = 60
    static let intervalOptions = [30, 45, 60, 90, 120]
    static let snoozeMinutes = 10
    /// Сколько секунд без мыши и клавиатуры (или с заблокированным экраном) считается перерывом.
    static let awayThreshold: TimeInterval = 5 * 60

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var intervalMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: intervalKey)
        return intervalOptions.contains(value) ? value : defaultIntervalMinutes
    }

    /// Когда напомнить: через интервал после последнего перерыва, но не раньше, чем кончится «отложить».
    static func nextReminder(lastBreakAt: Date, snoozedUntil: Date?, intervalMinutes: Int) -> Date {
        let due = lastBreakAt.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        guard let snoozedUntil else { return due }
        return max(due, snoozedUntil)
    }
}

private struct WarmupReminderView: View {
    let language: AppLanguage
    let minutes: Int
    let onDone: () -> Void
    let onSnooze: () -> Void

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.green)
                Text(l10n.warmupTitle)
                    .font(.headline)
            }
            Text(l10n.warmupMessage(minutes: minutes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(action: onDone) {
                    Label(l10n.warmupDone, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                Button(l10n.warmupSnooze(WarmupReminderPlan.snoozeMinutes), action: onSnooze)
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340, height: 132, alignment: .topLeading)
        .environment(\.locale, language.locale)
    }
}

private struct TaskNotificationView: View {
    let task: DayTask
    let previousTask: DayTask?
    let language: AppLanguage
    let onPostpone: (Int) -> Void
    let onStart: () -> Void
    let onComplete: () -> Void
    let onDismiss: () -> Void

    /// Подсказка к кнопкам «+5» / «+10»: показывается строкой над кнопками, ничего не перекрывая.
    @State private var postponeHint: String?

    private var l10n: L10n { L10n(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let previousTask {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(l10n.previousTask): \(previousTask.title)")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(task.color.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(l10n.taskStarted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let kind = task.kind {
                        Image(systemName: kind.systemImage)
                            .foregroundStyle(task.color.swiftUIColor)
                    }
                    Text(task.title)
                        .lineLimit(1)
                }
                .font(.headline)
                HStack {
                    Text("\(time(task.start)) – \(time(task.end))")
                    Spacer()
                    if let postponeHint {
                        Text(postponeHint)
                            .transition(.opacity)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeOut(duration: 0.12), value: postponeHint)
            }

            HStack(spacing: 7) {
                // Главное действие — просто закрыть: задача уже началась сама. Enter тоже закрывает.
                Button(l10n.gotIt, action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("+5") { onPostpone(5) }
                    .onHover { postponeHint = $0 ? l10n.postponeBy(5) : nil }
                Button("+10") { onPostpone(10) }
                    .onHover { postponeHint = $0 ? l10n.postponeBy(10) : nil }
                Spacer()
                // Редкое действие — компактной иконкой с подсказкой.
                Button(action: onStart) {
                    Image(systemName: task.startedAt == nil ? "play.fill" : "arrow.uturn.backward")
                }
                Button(action: onComplete) {
                    Label(l10n.completeTask, systemImage: "checkmark")
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 380, height: previousTask == nil ? 142 : 166)
        .environment(\.locale, language.locale)
    }

    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(language.locale))
    }
}

private enum DaylineStatusIcon {
    static func make(isActive: Bool, at _: Date) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            let frame = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 15, height: 14), xRadius: 4.5, yRadius: 4.5)
            frame.lineWidth = 1.5
            frame.stroke()

            let line = NSBezierPath()
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 4.5, y: 9))
            line.line(to: NSPoint(x: 14.5, y: 9))
            line.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 7.5, width: 3, height: 3)).fill()

            if isActive {
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: 11.5, y: -0.5, width: 9, height: 9)).fill()

                NSColor.white.setFill()
                let letter = NSBezierPath()
                letter.move(to: NSPoint(x: 14.2, y: 1.4))
                letter.line(to: NSPoint(x: 14.2, y: 6.6))
                letter.line(to: NSPoint(x: 15.7, y: 6.6))
                letter.curve(
                    to: NSPoint(x: 15.7, y: 1.4),
                    controlPoint1: NSPoint(x: 19, y: 6.6),
                    controlPoint2: NSPoint(x: 19, y: 1.4)
                )
                letter.close()
                letter.fill()
            }
            return true
        }
        image.isTemplate = !isActive
        image.accessibilityDescription = AppBrand.fullName
        return image
    }

    // Первый вариант сохранён: линия с вертикальным маркером.
    static func classicMarker() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineWidth = 1.8
            path.move(to: NSPoint(x: 2, y: 9))
            path.line(to: NSPoint(x: 18, y: 9))
            path.stroke()

            path.removeAllPoints()
            path.lineWidth = 2.4
            path.move(to: NSPoint(x: 12.5, y: 4))
            path.line(to: NSPoint(x: 12.5, y: 14))
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppBrand.fullName
        return image
    }
}
