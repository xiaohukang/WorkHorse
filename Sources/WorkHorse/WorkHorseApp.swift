import AppKit
import Combine
import CoreGraphics
import SwiftUI
import UserNotifications

@main
enum WorkHorseMain {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = WorkHorseStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var tickTimer: Timer?
    private var cancellable: AnyCancellable?

    private var taskPromptWindow: NSWindow?
    private var focusReminderWindow: NSWindow?
    private var offworkReminderWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var reportWindow: NSWindow?

    private var nextStartPromptAt: Date = .distantPast
    private var nextFocusReminderAt: Date?
    private var nextOffworkReminderAt: Date?
    private var lastRenderedStatus: WorkHorseStatus?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningAsAppBundle {
            configureNotifications()
        }
        configureStatusItem()
        configurePopover()
        configureTimers()
        configureStoreObservation()
        resetReminderSchedules()

        if !store.settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.showSettingsWindow(isOnboarding: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            configurePopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func configureNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "牛马时光 WorkHorse"
        updateStatusItem(force: true)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView(
                store: store,
                actions: WorkHorseActions(
                    showSettings: { [weak self] in self?.showSettingsWindow(isOnboarding: false) },
                    showTaskPrompt: { [weak self] in self?.showTaskPrompt(mode: .start) },
                    completeTask: { [weak self] in self?.completeTaskFromMenu() },
                    showReport: { [weak self] in self?.showReportWindow() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        )
    }

    private func configureTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    private func configureStoreObservation() {
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem(force: true)
            }
        }
    }

    private func tick() {
        store.tick()
        updateStatusItem()
        guard store.settings.hasCompletedOnboarding else { return }

        if store.currentTask == nil {
            maybeShowStartPrompt()
        } else {
            maybeShowFocusReminder()
        }

        maybeShowOffworkReminder()
    }

    private func updateStatusItem(force: Bool = false) {
        let status = store.status
        guard force || status != lastRenderedStatus else { return }
        lastRenderedStatus = status

        let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: "牛马时光")
        image?.isTemplate = true
        statusItem?.button?.image = image

        switch status {
        case .idle:
            statusItem?.button?.contentTintColor = .secondaryLabelColor
        case .running:
            statusItem?.button?.contentTintColor = .systemBlue
        case .waiting:
            statusItem?.button?.contentTintColor = .systemOrange
        case .clockedOut:
            statusItem?.button?.contentTintColor = .systemGreen
        }
    }

    private func maybeShowStartPrompt() {
        guard store.today.clockOutTime == nil,
              taskPromptWindow == nil,
              Date() >= nextStartPromptAt,
              store.settings.isWithinWorkWindow(Date()),
              latestInputIdleSeconds() < 3 else {
            return
        }

        nextStartPromptAt = Date().addingTimeInterval(10 * 60)
        showTaskPrompt(mode: .start)
    }

    private func maybeShowFocusReminder() {
        guard store.settings.enableFocusReminder,
              focusReminderWindow == nil,
              let task = store.currentTask else {
            return
        }

        if nextFocusReminderAt == nil {
            nextFocusReminderAt = nextFocusDate(for: task)
        }

        guard let nextFocusReminderAt, Date() >= nextFocusReminderAt else { return }
        sendNotification(title: "专注 25 分钟提醒", body: "当前任务：\(task.title)")
        showFocusReminder()
    }

    private func maybeShowOffworkReminder() {
        let settings = store.settings
        guard settings.enableOffworkReminder,
              offworkReminderWindow == nil,
              store.today.clockOutTime == nil,
              settings.isWorkday(Date()) else {
            return
        }

        let offworkDate = settings.date(on: Date(), from: settings.workEndTime)
        if nextOffworkReminderAt == nil {
            nextOffworkReminderAt = offworkDate
        }

        guard let nextOffworkReminderAt, Date() >= nextOffworkReminderAt else { return }
        sendNotification(title: "到点下班啦", body: "记得打卡。")
        showOffworkReminder()
    }

    private func latestInputIdleSeconds() -> TimeInterval {
        let eventTypes: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
    }

    private func resetReminderSchedules() {
        if let task = store.currentTask {
            nextFocusReminderAt = nextFocusDate(for: task)
        }

        if store.settings.enableOffworkReminder {
            nextOffworkReminderAt = store.settings.date(on: Date(), from: store.settings.workEndTime)
        }
    }

    private func nextFocusDate(for task: WorkTask) -> Date {
        let interval = TimeInterval(max(1, store.settings.focusReminderInterval) * 60)
        let elapsed = Date().timeIntervalSince(task.startTime)
        if elapsed >= interval {
            return Date().addingTimeInterval(2)
        }
        return task.startTime.addingTimeInterval(interval)
    }

    private func sendNotification(title: String, body: String) {
        guard isRunningAsAppBundle else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private var isRunningAsAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func showTaskPrompt(mode: TaskPromptMode) {
        popover.performClose(nil)
        let window = makeWindow(
            key: "taskPrompt",
            title: mode.title,
            size: NSSize(width: 460, height: 250),
            level: .floating,
            rootView: TaskPromptView(
                mode: mode,
                onStart: { [weak self] title in
                    self?.store.startTask(title: title)
                    self?.nextFocusReminderAt = Date().addingTimeInterval(TimeInterval(max(1, self?.store.settings.focusReminderInterval ?? 25) * 60))
                    self?.closeWindow(key: "taskPrompt")
                },
                onPostpone: { [weak self] in
                    self?.nextStartPromptAt = Date().addingTimeInterval(10 * 60)
                    self?.closeWindow(key: "taskPrompt")
                }
            )
        )
        taskPromptWindow = window
    }

    private func showFocusReminder() {
        popover.performClose(nil)
        guard let task = store.currentTask else { return }
        let window = makeWindow(
            key: "focusReminder",
            title: "专注 25 分钟提醒",
            size: NSSize(width: 470, height: 330),
            level: .floating,
            rootView: FocusReminderView(
                store: store,
                task: task,
                onComplete: { [weak self] in
                    self?.store.completeCurrentTask(status: .completed)
                    self?.nextFocusReminderAt = nil
                    self?.closeWindow(key: "focusReminder")
                    self?.showTaskPrompt(mode: .next)
                },
                onContinue: { [weak self] in
                    let interval = TimeInterval(max(1, self?.store.settings.focusReminderInterval ?? 25) * 60)
                    self?.nextFocusReminderAt = Date().addingTimeInterval(interval)
                    self?.closeWindow(key: "focusReminder")
                }
            )
        )
        focusReminderWindow = window
    }

    private func showOffworkReminder() {
        popover.performClose(nil)
        let window = makeWindow(
            key: "offworkReminder",
            title: "到点下班啦",
            size: NSSize(width: 440, height: 280),
            level: .floating,
            rootView: OffworkReminderView(
                onClockOut: { [weak self] in
                    self?.store.clockOutToday()
                    self?.nextFocusReminderAt = nil
                    self?.nextOffworkReminderAt = nil
                    self?.closeWindow(key: "offworkReminder")
                    self?.showReportWindow()
                },
                onContinue: { [weak self] in
                    let interval = TimeInterval(max(1, self?.store.settings.offworkReminderInterval ?? 15) * 60)
                    self?.nextOffworkReminderAt = Date().addingTimeInterval(interval)
                    self?.closeWindow(key: "offworkReminder")
                }
            )
        )
        offworkReminderWindow = window
    }

    private func showSettingsWindow(isOnboarding: Bool) {
        popover.performClose(nil)
        if let settingsWindow {
            presentWindow(settingsWindow)
            return
        }

        let window = makeWindow(
            key: "settings",
            title: "牛马时光设置",
            size: NSSize(width: 600, height: 740),
            level: .floating,
            rootView: SettingsView(
                settings: store.settings,
                isOnboarding: isOnboarding,
                onSave: { [weak self] settings in
                    if isOnboarding {
                        self?.store.completeOnboarding(with: settings)
                    } else {
                        self?.store.saveSettings(settings)
                    }
                    self?.resetReminderSchedules()
                    self?.closeWindow(key: "settings")
                },
                onCancel: { [weak self] in
                    self?.closeWindow(key: "settings")
                }
            )
        )
        settingsWindow = window
    }

    private func showReportWindow() {
        popover.performClose(nil)
        if let reportWindow {
            presentWindow(reportWindow)
            return
        }

        let window = makeWindow(
            key: "report",
            title: "今日工作报告",
            size: NSSize(width: 720, height: 600),
            level: .floating,
            rootView: ReportView(
                store: store,
                onClose: { [weak self] in
                    self?.closeWindow(key: "report")
                }
            )
        )
        reportWindow = window
    }

    private func completeTaskFromMenu() {
        guard store.currentTask != nil else { return }
        store.completeCurrentTask(status: .completed)
        nextFocusReminderAt = nil
        showTaskPrompt(mode: .next)
    }

    private func makeWindow<Content: View>(
        key: String,
        title: String,
        size: NSSize,
        level: NSWindow.Level,
        rootView: Content
    ) -> NSWindow {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(key)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = level
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
        NSApp.activate(ignoringOtherApps: true)
        centerWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return window
    }

    private func presentWindow(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        centerWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func centerWindow(_ window: NSWindow) {
        guard let screen = statusItem?.button?.window?.screen ?? NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - windowFrame.width / 2,
            y: visibleFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(NSPoint(x: floor(origin.x), y: floor(origin.y)))
    }

    private func closeWindow(key: String) {
        switch key {
        case "taskPrompt":
            taskPromptWindow?.close()
            taskPromptWindow = nil
        case "focusReminder":
            focusReminderWindow?.close()
            focusReminderWindow = nil
        case "offworkReminder":
            offworkReminderWindow?.close()
            offworkReminderWindow = nil
        case "settings":
            settingsWindow?.close()
            settingsWindow = nil
        case "report":
            reportWindow?.close()
            reportWindow = nil
        default:
            break
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = window.identifier?.rawValue else {
            return
        }

        switch key {
        case "taskPrompt": taskPromptWindow = nil
        case "focusReminder": focusReminderWindow = nil
        case "offworkReminder": offworkReminderWindow = nil
        case "settings": settingsWindow = nil
        case "report": reportWindow = nil
        default: break
        }
    }
}
