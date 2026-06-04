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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let store = WorkHorseStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var tickTimer: Timer?
    private var cancellable: AnyCancellable?
    private var popoverLocalEventMonitor: Any?
    private var popoverGlobalEventMonitor: Any?

    private var taskPromptWindow: NSWindow?
    private var offworkReminderWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var reportWindow: NSWindow?
    private var toastWindow: NSWindow?
    private var toastDismissWorkItem: DispatchWorkItem?
    private let focusReminderPopover = NSPopover()
    private var focusReminderDismissWorkItem: DispatchWorkItem?

    private var nextStartPromptAt: Date = .distantPast
    private var nextFocusReminderAt: Date?
    private var nextOffworkReminderAt: Date?
    private var lastRenderedStatus: WorkHorseStatus?
    private var lastRenderedStatusBarTitle: String?
    private let startPromptPostponeInterval: TimeInterval = 10 * 60
    private let menuPopoverWidth: CGFloat = 340
    private let statusBarFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private let statusBarIconLength: CGFloat = 18
    private let statusBarHorizontalPadding: CGFloat = 12

    private lazy var statusBarIcon: NSImage = {
        if let url = statusBarIconURL(),
           let image = NSImage(contentsOf: url) {
            return makeStatusBarTemplateImage(from: image)
        }

        let fallback = NSImage(systemSymbolName: "clock", accessibilityDescription: "牛马时光") ?? NSImage()
        fallback.size = NSSize(width: 18, height: 18)
        fallback.isTemplate = true
        return fallback
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        if isRunningAsAppBundle {
            configureNotifications()
        }
        configureStatusItem()
        configurePopover()
        configureTimers()
        configureStoreObservation()
        resetReminderSchedules()
        postponeStartPrompt()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.showSettingsWindow(isOnboarding: false, promptsForTaskOnDismiss: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        stopPopoverOutsideClickMonitoring()
        focusReminderDismissWorkItem?.cancel()
        focusReminderPopover.performClose(nil)
        toastDismissWorkItem?.cancel()
        toastWindow?.close()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            configurePopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startPopoverOutsideClickMonitoring()
        }
    }

    private func configureNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "牛马时光 WorkHorse"
        item.button?.image = statusBarIcon
        item.button?.imagePosition = .imageLeft
        item.button?.imageHugsTitle = true
        item.button?.alignment = .center
        updateStatusItem(force: true)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true

        let rootView = MenuPanelView(
            store: store,
            actions: WorkHorseActions(
                showSettings: { [weak self] in self?.showSettingsWindow(isOnboarding: false) },
                showTaskPrompt: { [weak self] in self?.showTaskPrompt(mode: .start) },
                completeTask: { [weak self] in self?.completeTaskFromMenu() },
                showReport: { [weak self] in self?.showReportWindow() },
                quit: { NSApp.terminate(nil) },
                resumeTask: { [weak self] id in self?.handleResumeTask(id: id) },
                pauseCurrentTask: { [weak self] in self?.handlePauseCurrentTask() },
                completeTaskByID: { [weak self] id in self?.handleCompleteTaskByID(id: id) }
            ),
            onContentHeightChange: { [weak self] height in
                self?.updateMenuPopoverHeight(height)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let fittingHeight = ceil(hostingController.view.fittingSize.height)
        let contentSize = NSSize(width: menuPopoverWidth, height: fittingHeight > 0 ? fittingHeight : 1)
        popover.contentSize = contentSize
        hostingController.preferredContentSize = contentSize
        popover.contentViewController = hostingController
    }

    private func updateMenuPopoverHeight(_ height: CGFloat) {
        let nextHeight = ceil(height)
        guard nextHeight > 0,
              abs(popover.contentSize.height - nextHeight) > 0.5 else {
            return
        }

        let nextSize = NSSize(width: menuPopoverWidth, height: nextHeight)
        popover.contentSize = nextSize
        popover.contentViewController?.preferredContentSize = nextSize
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "牛马时光")
        appMenu.addItem(
            withTitle: "退出牛马时光",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = makeEditMenu()
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(responderMenuItem(title: "撤销", action: "undo:", keyEquivalent: "z"))

        let redoItem = responderMenuItem(title: "重做", action: "redo:", keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)

        menu.addItem(.separator())
        menu.addItem(responderMenuItem(title: "剪切", action: "cut:", keyEquivalent: "x"))
        menu.addItem(responderMenuItem(title: "复制", action: "copy:", keyEquivalent: "c"))
        menu.addItem(responderMenuItem(title: "粘贴", action: "paste:", keyEquivalent: "v"))
        menu.addItem(responderMenuItem(title: "全选", action: "selectAll:", keyEquivalent: "a"))

        menu.addItem(.separator())
        let emojiItem = NSMenuItem(
            title: "表情与符号",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " "
        )
        emojiItem.target = NSApp
        emojiItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(emojiItem)

        return menu
    }

    private func responderMenuItem(title: String, action: String, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: keyEquivalent)
        item.target = nil
        return item
    }

    private func closePopover() {
        guard popover.isShown else {
            stopPopoverOutsideClickMonitoring()
            return
        }

        popover.performClose(nil)
        stopPopoverOutsideClickMonitoring()
    }

    private func startPopoverOutsideClickMonitoring() {
        stopPopoverOutsideClickMonitoring()

        let mouseDownEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        popoverLocalEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
            return event
        }
        popoverGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
        }
    }

    private func stopPopoverOutsideClickMonitoring() {
        if let popoverLocalEventMonitor {
            NSEvent.removeMonitor(popoverLocalEventMonitor)
            self.popoverLocalEventMonitor = nil
        }
        if let popoverGlobalEventMonitor {
            NSEvent.removeMonitor(popoverGlobalEventMonitor)
            self.popoverGlobalEventMonitor = nil
        }
    }

    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        let screenPoint = screenPoint(for: event)
        if Thread.isMainThread {
            closePopoverIfClickIsOutside(at: screenPoint)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.closePopoverIfClickIsOutside(at: screenPoint)
            }
        }
    }

    private func closePopoverIfClickIsOutside(at screenPoint: NSPoint) {
        guard popover.isShown else {
            stopPopoverOutsideClickMonitoring()
            return
        }

        guard !isPointInsidePopover(screenPoint),
              !isPointInsideStatusButton(screenPoint) else {
            return
        }

        closePopover()
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    private func isPointInsidePopover(_ point: NSPoint) -> Bool {
        guard let window = popover.contentViewController?.view.window else { return false }
        return window.frame.contains(point)
    }

    private func isPointInsideStatusButton(_ point: NSPoint) -> Bool {
        guard let button = statusItem?.button,
              let window = button.window else {
            return false
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        return buttonFrameOnScreen.insetBy(dx: -2, dy: -2).contains(point)
    }

    func popoverDidClose(_ notification: Notification) {
        if let closedPopover = notification.object as? NSPopover,
           closedPopover === focusReminderPopover,
           focusReminderDismissWorkItem != nil {
            focusReminderDismissWorkItem?.cancel()
            focusReminderDismissWorkItem = nil
            postponeFocusReminder()
        }

        stopPopoverOutsideClickMonitoring()
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

    private func handleResumeTask(id: String) {
        guard store.resumeTask(id: id) else { return }
        if let task = store.currentTask {
            showToast("「\(task.title)」正在计时")
        }
        nextFocusReminderAt = Date().addingTimeInterval(TimeInterval(max(1, store.settings.focusReminderInterval) * 60))
    }

    private func handlePauseCurrentTask() {
        guard store.pauseRunningTask() else { return }
        showToast("当前任务已暂停")
        nextFocusReminderAt = nil
    }

    private func handleCompleteTaskByID(id: String) {
        guard let task = store.completeTask(id: id) else { return }
        showToast("「\(task.title)」已完成")
        nextFocusReminderAt = nil
    }

    private func updateStatusItem(force: Bool = false) {
        let status = store.status
        let title = statusBarTitle(for: status)
        guard force || status != lastRenderedStatus || title != lastRenderedStatusBarTitle else { return }

        lastRenderedStatus = status
        lastRenderedStatusBarTitle = title

        if let button = statusItem?.button {
            statusItem?.length = statusBarItemLength(for: title)
            button.image = statusBarIcon
            button.imagePosition = .imageLeft
            button.imageHugsTitle = true
            button.alignment = .center
            button.contentTintColor = nil
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: statusBarFont,
                    .foregroundColor: NSColor.labelColor
                ]
            )
        }
    }

    private func statusBarTitle(for status: WorkHorseStatus) -> String {
        guard status == .running, let task = store.currentTask else { return "" }
        return " \(statusBarTimerString(seconds: store.duration(for: task, at: Date())))"
    }

    private func statusBarTimerString(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let seconds = safeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func statusBarItemLength(for title: String) -> CGFloat {
        guard !title.isEmpty else { return NSStatusItem.squareLength }

        let stableTitle = titleWidth(" 00:00:00")
        let currentTitle = titleWidth(title)
        let titleLength = max(stableTitle, currentTitle)
        return ceil(statusBarIconLength + titleLength + statusBarHorizontalPadding * 2)
    }

    private func titleWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: statusBarFont]).width
    }

    private func makeStatusBarTemplateImage(from source: NSImage) -> NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = true
        image.cacheMode = .never
        image.setName(NSImage.Name("statusbar-iconTemplate"))
        return image
    }

    private func maybeShowStartPrompt() {
        guard store.today.clockOutTime == nil,
              taskPromptWindow == nil,
              settingsWindow == nil,
              Date() >= nextStartPromptAt,
              store.canStartNewTask,
              store.settings.isWithinWorkWindow(Date()),
              latestInputIdleSeconds() < 3 else {
            return
        }

        postponeStartPrompt()
        showTaskPrompt(mode: .start)
    }

    private func maybeShowFocusReminder() {
        guard store.settings.enableFocusReminder,
              !focusReminderPopover.isShown,
              let task = store.currentTask else {
            return
        }

        if nextFocusReminderAt == nil {
            nextFocusReminderAt = nextFocusDate(for: task)
        }

        guard let nextFocusReminderAt, Date() >= nextFocusReminderAt else { return }
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

    private func resetReminderSchedules(afterSettingsChange: Bool = false) {
        let now = Date()
        if let task = store.currentTask {
            if afterSettingsChange {
                nextFocusReminderAt = nextReminderDate(from: now, intervalMinutes: store.settings.focusReminderInterval)
            } else {
                nextFocusReminderAt = nextFocusDate(for: task)
            }
        } else {
            nextFocusReminderAt = nil
        }

        if store.settings.enableOffworkReminder {
            let offworkDate = store.settings.date(on: now, from: store.settings.workEndTime)
            if afterSettingsChange, now >= offworkDate {
                nextOffworkReminderAt = nextReminderDate(from: now, intervalMinutes: store.settings.offworkReminderInterval)
            } else {
                nextOffworkReminderAt = offworkDate
            }
        } else {
            nextOffworkReminderAt = nil
        }
    }

    private func nextReminderDate(from referenceDate: Date, intervalMinutes: Int) -> Date {
        referenceDate.addingTimeInterval(TimeInterval(max(1, intervalMinutes) * 60))
    }

    private func postponeStartPrompt() {
        nextStartPromptAt = Date().addingTimeInterval(startPromptPostponeInterval)
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

    private func statusBarIconURL() -> URL? {
        [
            Bundle.main.url(forResource: "statusbar-icon", withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("statusbar-icon.png"),
            Bundle.module.url(forResource: "statusbar-icon", withExtension: "png"),
            URL(fileURLWithPath: "/Users/hukang/Documents/Work Horse/Sources/WorkHorse/Resources/statusbar-icon.png")
        ]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func showTaskPrompt(mode: TaskPromptMode) {
        closePopover()
        closeWindow(key: "taskPrompt")
        let window = makeWindow(
            key: "taskPrompt",
            title: mode.title,
            size: NSSize(width: 460, height: 280),
            level: .floating,
            rootView: TaskPromptView(
                mode: mode,
                onStart: { [weak self] title in
                    guard let self else { return }
                    let started = self.store.startTask(title: title)
                    if started {
                        self.nextFocusReminderAt = Date().addingTimeInterval(TimeInterval(max(1, self.store.settings.focusReminderInterval) * 60))
                        self.closeWindow(key: "taskPrompt")
                        self.showToast("开始计时，可在状态栏查看时长")
                    }
                    // 启动失败时（如已达 10 个任务上限）保持弹窗打开，
                    // Store 已通过 toast 给出原因。
                },
                onPostpone: { [weak self] in
                    self?.postponeStartPrompt()
                    self?.closeWindow(key: "taskPrompt")
                }
            )
        )
        taskPromptWindow = window
    }

    private func showFocusReminder() {
        closePopover()
        closeFocusReminderPopover()
        guard let task = store.currentTask else { return }
        guard let button = statusItem?.button else {
            postponeFocusReminder()
            return
        }

        let size = NSSize(width: 340, height: 280)
        focusReminderPopover.behavior = .transient
        focusReminderPopover.delegate = self
        focusReminderPopover.animates = true
        focusReminderPopover.contentSize = size
        focusReminderPopover.contentViewController = NSHostingController(
            rootView: FocusReminderBubbleView(
                store: store,
                task: task,
                onComplete: { [weak self] in
                    self?.closeFocusReminderPopover()
                    self?.store.completeCurrentTask(status: .completed)
                    self?.nextFocusReminderAt = nil
                    self?.showTaskPrompt(mode: .next)
                },
                onContinue: { [weak self] in
                    self?.postponeFocusReminder()
                    self?.closeFocusReminderPopover()
                }
            )
        )
        focusReminderPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        ReminderSoundPlayer.shared.play()
        scheduleFocusReminderAutoDismiss()
    }

    private func scheduleFocusReminderAutoDismiss() {
        focusReminderDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.focusReminderPopover.isShown else {
                return
            }
            self.postponeFocusReminder()
            self.closeFocusReminderPopover()
        }
        focusReminderDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    private func closeFocusReminderPopover() {
        focusReminderDismissWorkItem?.cancel()
        focusReminderDismissWorkItem = nil
        if focusReminderPopover.isShown {
            focusReminderPopover.performClose(nil)
        }
    }

    private func postponeFocusReminder() {
        nextFocusReminderAt = nextReminderDate(from: Date(), intervalMinutes: store.settings.focusReminderInterval)
    }

    private func showOffworkReminder() {
        closePopover()
        closeWindow(key: "offworkReminder")
        let window = makeWindow(
            key: "offworkReminder",
            title: "到点下班啦",
            size: NSSize(width: 440, height: 300),
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

    private func showSettingsWindow(isOnboarding: Bool, promptsForTaskOnDismiss: Bool = false) {
        closePopover()
        if let settingsWindow {
            presentWindow(settingsWindow)
            return
        }

        let window = makeWindow(
            key: "settings",
            title: "牛马时光设置",
            size: NSSize(width: 600, height: 800),
            level: .floating,
            rootView: SettingsView(
                settings: store.settings,
                isOnboarding: isOnboarding,
                onSave: { [weak self] settings in
                    guard let self else { return }
                    if isOnboarding || !self.store.settings.hasCompletedOnboarding {
                        self.store.completeOnboarding(with: settings)
                    } else {
                        self.store.saveSettings(settings)
                    }
                    self.resetReminderSchedules(afterSettingsChange: true)
                    self.finishSettingsFlow(promptsForTask: promptsForTaskOnDismiss)
                },
                onCancel: { [weak self] in
                    guard let self else { return }
                    if promptsForTaskOnDismiss, !self.store.settings.hasCompletedOnboarding {
                        self.store.completeOnboarding(with: self.store.settings)
                    }
                    self.finishSettingsFlow(promptsForTask: promptsForTaskOnDismiss)
                }
            )
        )
        settingsWindow = window
    }

    private func finishSettingsFlow(promptsForTask: Bool) {
        postponeStartPrompt()
        closeWindow(key: "settings")

        guard promptsForTask,
              store.currentTask == nil,
              store.canStartNewTask,
              store.today.clockOutTime == nil else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self,
                  self.settingsWindow == nil,
                  self.taskPromptWindow == nil,
                  self.store.currentTask == nil,
                  self.store.canStartNewTask,
                  self.store.today.clockOutTime == nil else {
                return
            }
            self.showTaskPrompt(mode: .start)
        }
    }

    private func showReportWindow() {
        closePopover()
        if let reportWindow {
            presentWindow(reportWindow)
            return
        }

        let window = makeWindow(
            key: "report",
            title: "今日工作报告",
            size: NSSize(width: 720, height: 660),
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
        closeFocusReminderPopover()
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
            // 不使用 .nonactivatingPanel：之前它导致面板永远成不了 keyWindow，
            // 进而 NSApp.keyWindow?.miniaturize / zoom / performClose 全部失效。
            // 当前设置下 makeKey() 能把面板置为 keyWindow，配合 WindowControlButton
            // 内部的 selector fallback 即可让三个自定义红绿灯按钮正常工作。
            styleMask: [.closable, .resizable, .miniaturizable, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(key)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // 点中面板上的空白（非交互控件）区域时，可以直接拖动窗口
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = level
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.isReleasedWhenClosed = false
        // 背景与圆角由 SwiftUI 的 .liquidPanel() 渲染；不要给 contentView 套自定义 layer，
        // 否则会多出一层背景并遮挡 SwiftUI 的阴影。
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setContentSize(size)
        NSApp.activate(ignoringOtherApps: true)
        centerWindow(window)
        window.makeKeyAndOrderFront(nil)
        // 显式 makeKey()：避免 accessory app 中面板不会自动成为 keyWindow。
        window.makeKey()
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else { return }
            self?.centerWindow(window)
        }
        return window
    }

    private func presentWindow(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        centerWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else { return }
            self?.centerWindow(window)
        }
    }

    private func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        toastWindow?.close()

        let size = NSSize(width: 500, height: 132)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("toast")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentViewController = NSHostingController(
            rootView: LargeToastView(message: message)
                .frame(width: size.width, height: size.height)
        )

        positionToastWindow(window)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }

        toastWindow = window
        let dismissWorkItem = DispatchWorkItem { [weak self, weak window] in
            guard let self,
                  let window,
                  self.toastWindow === window else {
                return
            }
            self.hideToast()
        }
        toastDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: dismissWorkItem)
    }

    private func hideToast() {
        toastDismissWorkItem?.cancel()
        toastDismissWorkItem = nil

        guard let window = toastWindow else { return }
        toastWindow = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            window.close()
        }
    }

    private func positionToastWindow(_ window: NSWindow) {
        guard let screen = screenContainingMouse()
            ?? statusItem?.button?.window?.screen
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
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

    private func centerWindow(_ window: NSWindow) {
        guard let screen = screenContainingMouse()
            ?? NSApp.keyWindow?.screen
            ?? statusItem?.button?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
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

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }
    }

    private func closeWindow(key: String) {
        switch key {
        case "taskPrompt":
            taskPromptWindow?.close()
            taskPromptWindow = nil
        case "focusReminder":
            closeFocusReminderPopover()
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
        case "taskPrompt":
            taskPromptWindow = nil
            // 防止用户手动关闭后，下一 tick 因 taskPromptWindow == nil 立即重弹
            postponeStartPrompt()
        case "focusReminder":
            // 手动关闭后，将下次提醒推迟一个间隔，避免立即重弹
            postponeFocusReminder()
        case "offworkReminder":
            offworkReminderWindow = nil
            // 手动关闭后，将下次提醒推迟一个间隔，避免立即重弹
            let interval = TimeInterval(max(1, store.settings.offworkReminderInterval) * 60)
            nextOffworkReminderAt = Date().addingTimeInterval(interval)
        case "settings":
            settingsWindow = nil
        case "report":
            reportWindow = nil
        default:
            break
        }
    }
}

private struct LargeToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.whBlue.opacity(0.16))
                Image(systemName: "timer.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.whBlue)
            }
            .frame(width: 56, height: 56)

            Text(message)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.whTitle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.whCardStroke, lineWidth: 1)
        )
        .shadow(color: .whToastShadow, radius: 28, x: 0, y: 16)
    }
}
