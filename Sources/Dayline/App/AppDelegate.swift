import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore(syncService: CloudKitTaskSyncService())
    private let popover = NSPopover()
    private let notificationPopover = NSPopover()
    private var statusItem: NSStatusItem?
    private var notificationTimer: Timer?
    private var taskObserver: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var notifiedTaskStarts: [UUID: Date] = [:]
    private var isClosingPopovers = false
    private var lastCloudRefresh = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = DaylineStatusIcon.make(isActive: false, at: Date())
            button.imagePosition = .imageOnly
            button.toolTip = "Dayline"
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 520, height: 580)
        popover.contentViewController = NSHostingController(
            rootView: DaylineView().environmentObject(store)
        )
        notificationPopover.behavior = .transient
        statusItem = item
        refreshStatusIcon()
        Task { await store.synchronizeNow() }

        taskObserver = store.$tasks
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshStatusIcon()
                }
            }

        notificationTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(checkTaskNotifications),
            userInfo: nil,
            repeats: true
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
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
        notificationPopover.performClose(nil)
        if popover.isShown {
            if !mainPopoverHasSheet { closeVisiblePopovers() }
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func checkTaskNotifications() {
        let now = Date()
        if now.timeIntervalSince(lastCloudRefresh) >= 30 {
            lastCloudRefresh = now
            Task { await store.synchronizeNow() }
        }
        store.completeExpiredTasks(at: now)
        store.startCurrentScheduledTask(at: now)
        refreshStatusIcon()
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "taskNotifications") as? Bool ?? true
        guard enabled, !notificationPopover.isShown, !mainPopoverHasSheet else { return }

        let dayTasks = store.tasksForDay(now)
        let tasks = dayTasks.filter { !$0.isCompleted && $0.isFlexible != true }
        let starting = tasks.first { task in
            notifiedTaskStarts[task.id] != task.start
                && task.start <= now
                && now.timeIntervalSince(task.start) < 60
                && task.startedAt.map { $0 >= task.start } == true
        }

        guard let task = starting else { return }
        let previousTask = dayTasks
            .filter { $0.id != task.id && $0.isCompleted && $0.end <= task.start }
            .max { $0.end < $1.end }
        notifiedTaskStarts[task.id] = task.start
        showTaskNotification(task, previousTask: previousTask)
    }

    @objc private func applicationDidResignActive() {
        closeVisiblePopovers()
    }

    private func closeVisiblePopovers() {
        guard !isClosingPopovers else { return }
        isClosingPopovers = true
        if popover.isShown && !mainPopoverHasSheet {
            popover.performClose(nil)
        }
        if notificationPopover.isShown {
            notificationPopover.performClose(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isClosingPopovers = false
        }
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

    private func showTaskNotification(_ task: DayTask, previousTask: DayTask?) {
        guard let button = statusItem?.button, !mainPopoverHasSheet else { return }
        if popover.isShown { popover.performClose(nil) }

        let rawLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.russian.rawValue
        let language = AppLanguage(rawValue: rawLanguage) ?? .russian
        let view = TaskNotificationView(
            task: task,
            previousTask: previousTask,
            language: language,
            onPostpone: { [weak self] minutes in
                self?.store.postpone(task, by: minutes)
                self?.notificationPopover.performClose(nil)
            },
            onStart: { [weak self] in
                self?.store.toggleStart(task)
                self?.refreshStatusIcon()
                self?.notificationPopover.performClose(nil)
            },
            onComplete: { [weak self] in
                self?.store.complete(task)
                self?.refreshStatusIcon()
                self?.notificationPopover.performClose(nil)
            },
            onDismiss: { [weak self] in
                self?.notificationPopover.performClose(nil)
            }
        )
        notificationPopover.contentSize = NSSize(width: 380, height: previousTask == nil ? 142 : 166)
        notificationPopover.contentViewController = NSHostingController(rootView: view)
        NSApplication.shared.activate(ignoringOtherApps: true)
        notificationPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                }
                .buttonStyle(IconBlockButtonStyle())
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(task.start.formatted(.dateTime.hour().minute().locale(language.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                Button(action: onStart) {
                    Label(
                        task.startedAt == nil ? l10n.startTask : l10n.undoStart,
                        systemImage: task.startedAt == nil ? "play.fill" : "arrow.uturn.backward"
                    )
                }
                .buttonStyle(.borderedProminent)
                Button("+5") { onPostpone(5) }
                Button("+10") { onPostpone(10) }
                Spacer()
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
        image.accessibilityDescription = "Dayline"
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
        image.accessibilityDescription = "Dayline"
        return image
    }
}
