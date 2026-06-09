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
        // 走 .regular 而非 .accessory：让 WorkHorse 出现在 ⌘Tab 任务切换器中，
        // 避免窗口被其他 App 遮挡后"找不到界面"。状态栏图标在 .regular 下仍正常工作。
        app.setActivationPolicy(.regular)
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
    private var historyWindow: NSWindow?
    private var restPickerWindow: NSWindow?
    private var superBadgeWindow: NSWindow?
    private var toastWindow: NSWindow?
    private var toastDismissWorkItem: DispatchWorkItem?
    private let focusReminderPopover = NSPopover()
    private var focusReminderDismissWorkItem: DispatchWorkItem?
    private var runningTaskActivity: NSObjectProtocol?
    private var superBadgeTriggerWorkItem: DispatchWorkItem?
    private var superBadgePresentationConfirmationWorkItem: DispatchWorkItem?
    private var superBadgeCelebrationDateKey: String?
    private var isScreenAwake = true
    private var isUserSessionActive = true

    private var nextStartPromptAt: Date = .distantPast
    private var nextFocusReminderAt: Date?
    private var nextOffworkReminderAt: Date?
    /// 最近一次被 `showXxxWindow` 打开过的窗口 key（settings/report/taskPrompt/offworkReminder/restPicker），
    /// 用于 ⌘Tab 切回 WorkHorse 时按"上次打开过哪个窗口就恢复哪个"恢复界面。
    private var lastOpenedWindowKey: String?
    /// 启动后首次 activation 不算"用户从 ⌘Tab 切回来"，避免与 0.35s 后的 onboarding 弹窗重复打开。
    private var hasHandledFirstActivation = false
    private var lastRenderedStatus: WorkHorseStatus?
    private var lastRenderedStatusBarTitle: String?
    private var lastRenderedIsResting: Bool = false
    private let startPromptPostponeInterval: TimeInterval = 10 * 60
    private let menuPopoverWidth: CGFloat = 340
    /// 弹窗高度的兜底值。默认 0 表示不强制撑高，让弹窗完全跟随内部 SwiftUI
    /// 内容自适应；外部需要时仍然可以通过 `MenuPanelView.minContentHeight`
    /// 显式传入一个最小高度。
    private let menuPopoverMinHeight: CGFloat = 0
    /// 当前弹窗的 contentSize 高度缓存，用于在 SwiftUI 反复上报同一高度时
    /// 跳过无意义的 `popover.contentSize` 写入。每次关闭弹窗后重置。
    private var menuPopoverCurrentHeight: CGFloat = 0
    private let statusBarFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private let statusBarIconLength: CGFloat = 18
    private let statusBarHorizontalPadding: CGFloat = 12
    private let superBadgeCelebrationDefaultsKey = "superWorkhorseBadgeCelebratedDate"

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

    /// 状态栏在休息中显示的图标：与"牛马需要休息"按钮的 `cup.and.saucer.fill` 保持一致。
    /// 渲染成 18×18 的 template image，遵循 macOS 状态栏的暗色自适应规则。
    private lazy var statusBarRestIcon: NSImage = {
        let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "休息中") ?? NSImage()
        let target = NSImage(size: NSSize(width: 18, height: 18))
        target.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: NSSize(width: 18, height: 18)),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        target.unlockFocus()
        target.isTemplate = true
        target.cacheMode = .never
        target.setName(NSImage.Name("statusbar-rest-iconTemplate"))
        return target
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
        configureWorkspaceObservation()
        resetReminderSchedules()
        syncRunningTaskRuntimeState(rescheduleBadge: true)
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
        superBadgeWindow?.close()
        superBadgeTriggerWorkItem?.cancel()
        superBadgePresentationConfirmationWorkItem?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let runningTaskActivity {
            ProcessInfo.processInfo.endActivity(runningTaskActivity)
            self.runningTaskActivity = nil
        }
    }

    /// ⌘Tab 切到 WorkHorse 时按"上次打开过哪个窗口就恢复哪个"恢复界面；
    /// 若从未打开过窗口，则兜底弹主菜单弹窗（和点状态栏图标一样），保证"找得到界面"。
    /// 启动后第一次 activation 不触发，避免与 applicationDidFinishLaunching 中
    /// 0.35s 后的 onboarding 设置弹窗重复打开。
    func applicationDidBecomeActive(_ notification: Notification) {
        guard hasHandledFirstActivation else {
            hasHandledFirstActivation = true
            return
        }
        store.tick()
        discardStaleSuperBadgeCelebrationIfNeeded()
        maybeShowSuperWorkhorseBadgeCelebration()
        guard superBadgeWindow == nil else { return }
        restoreLastOpenedWindowOrShowMenu()
    }

    /// 用户点 Dock 图标（或者在 App 列表里再次点击 App）时，也走"恢复最近窗口"逻辑。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreLastOpenedWindowOrShowMenu()
        return true
    }

    /// 关掉所有窗口后不要退出：用户可能只是临时关掉弹窗，工作仍然在状态栏常驻；
    /// 这样也避免在 ⌘Tab 切换过程中出现"窗口被全关 → App 退出 → 切不到"的尴尬。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func restoreLastOpenedWindowOrShowMenu() {
        NSApp.activate(ignoringOtherApps: true)
        // 1) 有未关闭的窗口：直接置前。
        if let key = lastOpenedWindowKey,
           let window = windowForKey(key),
           window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // 2) 有过窗口但被关掉了：重新打开。
        if let key = lastOpenedWindowKey {
            openWindow(forKey: key)
            return
        }
        // 3) 从没主动开过窗口：兜底弹主菜单弹窗。
        togglePopover()
    }

    private func windowForKey(_ key: String) -> NSWindow? {
        switch key {
        case "taskPrompt": return taskPromptWindow
        case "offworkReminder": return offworkReminderWindow
        case "settings": return settingsWindow
        case "report": return reportWindow
        case "history": return historyWindow
        case "restPicker": return restPickerWindow
        default: return nil
        }
    }

    private func openWindow(forKey key: String) {
        switch key {
        case "taskPrompt": showTaskPrompt(mode: .start)
        case "offworkReminder": showOffworkReminder()
        case "settings": showSettingsWindow(isOnboarding: false)
        case "report": showReportWindow()
        case "history": showHistoryWindow()
        case "restPicker": showRestPickerWindow()
        default: togglePopover()
        }
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
        // 主菜单内容会随任务增减实时变高/变矮；关闭 popover 自带的尺寸动画，
        // 避免缩高时 AppKit 保留旧 view 偏移，导致顶部内容被裁切。
        popover.animates = false

        menuPopoverCurrentHeight = 0

        let rootView = MenuPanelView(
            store: store,
            actions: WorkHorseActions(
                showSettings: { [weak self] in self?.showSettingsWindow(isOnboarding: false) },
                showTaskPrompt: { [weak self] in self?.showTaskPrompt(mode: .start) },
                completeTask: { [weak self] in self?.completeTaskFromMenu() },
                showReport: { [weak self] in self?.showReportWindow() },
                showHistory: { [weak self] in self?.showHistoryWindow() },
                quit: { NSApp.terminate(nil) },
                resumeTask: { [weak self] id in self?.handleResumeTask(id: id) },
                pauseCurrentTask: { [weak self] in self?.handlePauseCurrentTask() },
                completeTaskByID: { [weak self] id in self?.handleCompleteTaskByID(id: id) },
                requestRest: { [weak self] in self?.showRestPickerWindow() },
                startRest: { [weak self] minutes in self?.handleStartRest(minutes: minutes) },
                endRest: { [weak self] in self?.handleEndRest() }
            ),
            minContentHeight: menuPopoverMinHeight,
            onContentHeightChange: { [weak self] height in
                self?.updateMenuPopoverHeight(height)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let fittingHeight = ceil(hostingController.view.fittingSize.height)
        let initialHeight = max(menuPopoverMinHeight, fittingHeight > 0 ? fittingHeight : 1)
        menuPopoverCurrentHeight = initialHeight
        let contentSize = NSSize(width: menuPopoverWidth, height: initialHeight)
        popover.contentViewController = hostingController
        applyMenuPopoverSize(contentSize)
    }

    private func updateMenuPopoverHeight(_ height: CGFloat) {
        let nextHeight = ceil(height)
        guard nextHeight > 0 else { return }

        // 弹窗高度完全跟随 SwiftUI 内容自适应：
        // 内容变长就变长，内容变短就同步缩回，不会留下多余的空白。
        let displayHeight = max(menuPopoverMinHeight, nextHeight)
        guard abs(menuPopoverCurrentHeight - displayHeight) > 0.5 else { return }

        menuPopoverCurrentHeight = displayHeight
        let nextSize = NSSize(width: menuPopoverWidth, height: displayHeight)
        applyMenuPopoverSize(nextSize)
    }

    private func applyMenuPopoverSize(_ size: NSSize) {
        popover.contentViewController?.preferredContentSize = size

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            popover.contentSize = size
        }
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

        if let closedPopover = notification.object as? NSPopover, closedPopover === popover {
            // 主菜单弹窗关闭后重置当前高度缓存，下次打开从内容 fit 重新计算，
            // 避免上一次会话的高度被带到下一次。
            menuPopoverCurrentHeight = 0
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

    private func configureWorkspaceObservation() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleScreenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleScreenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleScreenDidSleep(_ notification: Notification) {
        isScreenAwake = false
        suspendSuperBadgeCelebrationPresentation()
    }

    @objc private func handleScreenDidWake(_ notification: Notification) {
        isScreenAwake = true
        resumeSuperBadgeCelebrationPresentationIfPossible()
    }

    @objc private func handleSessionDidResignActive(_ notification: Notification) {
        isUserSessionActive = false
        suspendSuperBadgeCelebrationPresentation()
    }

    @objc private func handleSessionDidBecomeActive(_ notification: Notification) {
        isUserSessionActive = true
        resumeSuperBadgeCelebrationPresentationIfPossible()
    }

    private func tick() {
        store.tick()
        discardStaleSuperBadgeCelebrationIfNeeded()
        syncRunningTaskRuntimeState()
        updateStatusItem()
        guard store.settings.hasCompletedOnboarding else { return }

        if store.currentTask == nil {
            maybeShowStartPrompt()
        } else {
            maybeShowFocusReminder()
        }

        maybeShowOffworkReminder()
        maybeShowSuperWorkhorseBadgeCelebration()
    }

    private func handleResumeTask(id: String) {
        guard store.resumeTask(id: id) else { return }
        syncRunningTaskRuntimeState(rescheduleBadge: true)
        ReminderSoundPlayer.shared.playTaskStarted()
        if let task = store.currentTask {
            showToast("「\(task.title)」正在计时")
        }
        nextFocusReminderAt = Date().addingTimeInterval(TimeInterval(max(1, store.settings.focusReminderInterval) * 60))
    }

    private func handlePauseCurrentTask() {
        guard store.pauseRunningTask() else { return }
        syncRunningTaskRuntimeState(rescheduleBadge: true)
        ReminderSoundPlayer.shared.playTaskPaused()
        showToast("当前任务已暂停")
        nextFocusReminderAt = nil
    }

    private func handleCompleteTaskByID(id: String) {
        guard let task = store.completeTask(id: id) else { return }
        syncRunningTaskRuntimeState(rescheduleBadge: true)
        ReminderSoundPlayer.shared.playTaskCompleted()
        showToast("「\(task.title)」已完成")
        nextFocusReminderAt = nil
    }

    private func updateStatusItem(force: Bool = false) {
        let status = store.status
        let title = statusBarTitle(for: status)
        let isResting = store.isResting
        guard force || status != lastRenderedStatus
                || title != lastRenderedStatusBarTitle
                || isResting != lastRenderedIsResting else {
            return
        }

        lastRenderedStatus = status
        lastRenderedStatusBarTitle = title
        lastRenderedIsResting = isResting

        if let button = statusItem?.button {
            statusItem?.length = statusBarItemLength(for: title)
            // 休息中切换为咖啡杯图标，与"牛马需要休息"按钮的视觉保持一致。
            button.image = isResting ? statusBarRestIcon : statusBarIcon
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
        if let segment = store.currentRestSegment {
            let remaining = segment.plannedDurationSeconds - segment.actualDurationSeconds(at: Date())
            return " \(statusBarTimerString(seconds: remaining))"
        }
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

    private func syncRunningTaskRuntimeState(rescheduleBadge: Bool = false) {
        if store.currentTask != nil {
            if runningTaskActivity == nil {
                runningTaskActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                    reason: "WorkHorse is tracking an active task"
                )
            }
            if rescheduleBadge {
                scheduleSuperBadgeTriggerIfNeeded()
            }
        } else {
            if let runningTaskActivity {
                ProcessInfo.processInfo.endActivity(runningTaskActivity)
                self.runningTaskActivity = nil
            }
            cancelScheduledSuperBadgeTrigger()
        }
    }

    private func scheduleSuperBadgeTriggerIfNeeded() {
        cancelScheduledSuperBadgeTrigger()

        guard store.settings.hasCompletedOnboarding,
              store.currentTask != nil else {
            return
        }

        let referenceDate = Date()
        let dateKey = WorkHorseFormatters.dateKey(for: referenceDate)
        guard UserDefaults.standard.string(forKey: superBadgeCelebrationDefaultsKey) != dateKey else {
            return
        }

        let remaining = store.remainingSecondsForSuperWorkhorseBadge(at: referenceDate)
        guard remaining > 0 else {
            maybeShowSuperWorkhorseBadgeCelebration()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.tick()
            self.updateStatusItem(force: true)
            self.maybeShowSuperWorkhorseBadgeCelebration()
        }
        superBadgeTriggerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(remaining), execute: workItem)
    }

    private func cancelScheduledSuperBadgeTrigger() {
        superBadgeTriggerWorkItem?.cancel()
        superBadgeTriggerWorkItem = nil
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
        lastOpenedWindowKey = "taskPrompt"
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
                        self.syncRunningTaskRuntimeState(rescheduleBadge: true)
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

        let size = NSSize(width: 340, height: 320)
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
                    self?.syncRunningTaskRuntimeState(rescheduleBadge: true)
                    self?.nextFocusReminderAt = nil
                    self?.showTaskPrompt(mode: .next)
                },
                onContinue: { [weak self] in
                    // 用户选择"继续"：先把弹窗关掉、把下次提醒时间推后，让视觉反馈立刻生效；
                    // 哀嚎音效放在最后且是 fire-and-forget，即便加载/播放失败也不影响主流程。
                    self?.postponeFocusReminder()
                    self?.closeFocusReminderPopover()
                    ReminderSoundPlayer.shared.playMoan()
                },
                onRest: { [weak self] in
                    // 休息 5 分钟：复用 Store 的休息流程，休息结束会自动恢复任务。
                    self?.closeFocusReminderPopover()
                    self?.handleStartRest(minutes: 5)
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
        lastOpenedWindowKey = "offworkReminder"
        let window = makeWindow(
            key: "offworkReminder",
            title: "到点下班啦",
            size: NSSize(width: 440, height: 300),
            level: .floating,
            rootView: OffworkReminderView(
                onClockOut: { [weak self] in
                    self?.store.clockOutToday()
                    self?.syncRunningTaskRuntimeState(rescheduleBadge: true)
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
        lastOpenedWindowKey = "settings"

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
                    self.syncRunningTaskRuntimeState(rescheduleBadge: true)
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

    // MARK: - 休息流程

    /// 弹出"牛马需要休息"选择窗口；用户选择具体分钟数（2~20）后开始休息。
    private func showRestPickerWindow() {
        closePopover()
        closeWindow(key: "restPicker")
        if store.isResting {
            showToast("已经在休息中")
            return
        }
        lastOpenedWindowKey = "restPicker"

        let window = makeWindow(
            key: "restPicker",
            title: "牛马需要休息",
            size: NSSize(width: 420, height: 420),
            level: .floating,
            rootView: RestPickerView(
                onPick: { [weak self] minutes in
                    self?.handleStartRest(minutes: minutes)
                },
                onCancel: { [weak self] in
                    self?.closeWindow(key: "restPicker")
                }
            ),
            preferredHeight: 420
        )
        restPickerWindow = window
    }

    private func handleStartRest(minutes: Int) {
        let bounded = max(2, min(20, minutes))
        guard let segment = store.startRest(minutes: bounded) else {
            closeWindow(key: "restPicker")
            return
        }
        closeWindow(key: "restPicker")
        // 休息中不要再触发专注提醒，否则会反复打扰正在放空的牛马。
        syncRunningTaskRuntimeState(rescheduleBadge: true)
        nextFocusReminderAt = nil
        showToast("开始休息 \(bounded) 分钟")
        scheduleRestAutoResume(for: segment, fallbackMinutes: bounded)
    }

    /// 休息时长到达后自动结束休息并恢复任务；
    /// 与 OffworkReminder 类似的 fire-and-forget 计时器，不需要暴露给外部。
    private var restAutoResumeWorkItem: DispatchWorkItem?
    private var restAutoResumeTargetID: String?

    private func scheduleRestAutoResume(for segment: RestSegment, fallbackMinutes: Int) {
        restAutoResumeWorkItem?.cancel()
        let target = segment.id
        restAutoResumeTargetID = target

        let seconds = max(1, segment.plannedDurationSeconds)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.restAutoResumeTargetID == target,
                  let current = self.store.currentRestSegment,
                  current.id == target else {
                return
            }
            self.handleEndRest()
        }
        restAutoResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TimeInterval(seconds),
            execute: workItem
        )
        _ = fallbackMinutes
    }

    private func handleEndRest() {
        restAutoResumeWorkItem?.cancel()
        restAutoResumeWorkItem = nil
        restAutoResumeTargetID = nil
        guard store.isResting else { return }

        let resumed = store.endCurrentRestIfNeeded(at: Date())
        if resumed != nil {
            syncRunningTaskRuntimeState(rescheduleBadge: true)
            showToast("休息结束，继续干活")
            // 任务恢复后，按用户配置的专注提醒间隔再推迟一次提醒。
            nextFocusReminderAt = Date().addingTimeInterval(TimeInterval(max(1, store.settings.focusReminderInterval) * 60))
        } else {
            syncRunningTaskRuntimeState(rescheduleBadge: true)
            showToast("休息结束")
        }
    }

    private func showReportWindow() {
        closePopover()
        if let reportWindow {
            presentWindow(reportWindow)
            return
        }
        lastOpenedWindowKey = "report"

        let window = makeWindow(
            key: "report",
            title: "今日工作报告",
            size: NSSize(width: 720, height: 760),
            level: .floating,
            rootView: ReportView(
                store: store,
                onClose: { [weak self] in
                    self?.closeWindow(key: "report")
                }
            ),
            // preferredHeight > 0 触发 makeWindow 内的"按 SwiftUI 内容自适应窗口高度"逻辑，
            // 这样今日任务少时窗口不会留一大块空白，任务多时也不会写死 760 溢出。
            preferredHeight: 1
        )
        reportWindow = window
    }

    private func showHistoryWindow() {
        closePopover()
        if let historyWindow {
            presentWindow(historyWindow)
            return
        }
        lastOpenedWindowKey = "history"

        let window = makeWindow(
            key: "history",
            title: "历史工作记录",
            size: NSSize(width: 760, height: 760),
            level: .floating,
            rootView: HistoryView(
                store: store,
                onClose: { [weak self] in
                    self?.closeWindow(key: "history")
                }
            ),
            preferredHeight: 1
        )
        historyWindow = window
    }

    private func maybeShowSuperWorkhorseBadgeCelebration() {
        let referenceDate = Date()
        let dateKey = WorkHorseFormatters.dateKey(for: referenceDate)
        let shouldPresent = SuperBadgeCelebrationPolicy.shouldPresent(
            hasCompletedOnboarding: store.settings.hasCompletedOnboarding,
            hasEarnedBadge: store.hasEarnedSuperWorkhorseBadge(at: referenceDate),
            hasOpenWindow: superBadgeWindow != nil,
            isPresentationAvailable: canPresentSuperBadgeCelebration,
            celebratedDateKey: UserDefaults.standard.string(forKey: superBadgeCelebrationDefaultsKey),
            currentDateKey: dateKey
        )
        guard shouldPresent else {
            return
        }

        showSuperWorkhorseBadgeWindow(
            totalSeconds: store.totalSeconds(at: referenceDate),
            dateKey: dateKey
        )
    }

    private var canPresentSuperBadgeCelebration: Bool {
        isScreenAwake && isUserSessionActive
    }

    private func showSuperWorkhorseBadgeWindow(totalSeconds: Int, dateKey: String) {
        guard canPresentSuperBadgeCelebration else { return }

        closePopover()
        superBadgeWindow?.close()

        guard let screen = screenContainingMouse()
            ?? NSApp.keyWindow?.screen
            ?? statusItem?.button?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return
        }

        let window = WorkHorseOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("superBadge")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SuperWorkhorseBadgeCelebrationView(
                totalSeconds: totalSeconds,
                onDismiss: { [weak self] in
                    self?.closeSuperWorkhorseBadgeWindow()
                }
            )
            .frame(width: screen.frame.width, height: screen.frame.height)
        )
        window.setFrame(screen.frame, display: true)
        superBadgeWindow = window
        superBadgeCelebrationDateKey = dateKey

        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        superBadgePresentationConfirmationWorkItem?.cancel()
        let confirmation = DispatchWorkItem { [weak self, weak window] in
            guard let self,
                  let window,
                  self.superBadgeWindow === window,
                  self.superBadgeCelebrationDateKey == dateKey else {
                return
            }
            self.superBadgePresentationConfirmationWorkItem = nil

            guard self.canPresentSuperBadgeCelebration,
                  window.isVisible,
                  window.occlusionState.contains(.visible) else {
                self.closeSuperWorkhorseBadgeWindow()
                return
            }

            UserDefaults.standard.set(dateKey, forKey: self.superBadgeCelebrationDefaultsKey)
            ReminderSoundPlayer.shared.playBadgeEarned()
        }
        superBadgePresentationConfirmationWorkItem = confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: confirmation)
    }

    private func suspendSuperBadgeCelebrationPresentation() {
        superBadgePresentationConfirmationWorkItem?.cancel()
        superBadgePresentationConfirmationWorkItem = nil
        closeSuperWorkhorseBadgeWindow(animated: false)
    }

    private func resumeSuperBadgeCelebrationPresentationIfPossible() {
        guard canPresentSuperBadgeCelebration else { return }
        store.tick()
        discardStaleSuperBadgeCelebrationIfNeeded()
        syncRunningTaskRuntimeState(rescheduleBadge: true)
        maybeShowSuperWorkhorseBadgeCelebration()
    }

    private func discardStaleSuperBadgeCelebrationIfNeeded() {
        let currentDateKey = WorkHorseFormatters.dateKey()
        guard SuperBadgeCelebrationPolicy.shouldCloseOpenCelebration(
            celebrationDateKey: superBadgeCelebrationDateKey,
            currentDateKey: currentDateKey
        ) else {
            return
        }
        closeSuperWorkhorseBadgeWindow(animated: false)
    }

    private func closeSuperWorkhorseBadgeWindow(animated: Bool = true) {
        superBadgePresentationConfirmationWorkItem?.cancel()
        superBadgePresentationConfirmationWorkItem = nil
        superBadgeCelebrationDateKey = nil
        guard let window = superBadgeWindow else { return }
        superBadgeWindow = nil
        guard animated else {
            window.close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            window.animator().alphaValue = 0
        } completionHandler: {
            window.close()
        }
    }

    private func completeTaskFromMenu() {
        guard store.currentTask != nil else { return }
        closeFocusReminderPopover()
        store.completeCurrentTask(status: .completed)
        syncRunningTaskRuntimeState(rescheduleBadge: true)
        nextFocusReminderAt = nil
        showTaskPrompt(mode: .next)
    }

    private func makeWindow<Content: View>(
        key: String,
        title: String,
        size: NSSize,
        level: NSWindow.Level,
        rootView: Content,
        preferredHeight: CGFloat? = nil
    ) -> NSWindow {
        // 如果调用方传了 preferredHeight（比如想要"高度自适应"的弹窗），
        // 用 NSHostingController 测出 SwiftUI 内容的 fittingSize，再把窗口尺寸校正到该高度；
        // 这样内容自然撑开多少，窗口就多高，不会出现截图中"高度写死但内容溢出/留白"的问题。
        let resolvedSize: NSSize = {
            guard let preferredHeight, preferredHeight > 0 else { return size }
            return NSSize(width: size.width, height: preferredHeight)
        }()

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: resolvedSize),
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
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        window.setContentSize(resolvedSize)
        NSApp.activate(ignoringOtherApps: true)
        centerWindow(window)
        window.makeKeyAndOrderFront(nil)
        // 显式 makeKey()：避免 accessory app 中面板不会自动成为 keyWindow。
        window.makeKey()
        window.orderFrontRegardless()

        // 自适应高度：layoutIfNeeded 后 SwiftUI 会按内容算出真实高度，
        // 此时再把窗口 contentSize 调整一次，确保不同文案长度下都不会溢出/留白。
        if preferredHeight != nil {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                hostingController.view.layoutSubtreeIfNeeded()
                let fittingHeight = ceil(hostingController.view.fittingSize.height)
                guard fittingHeight > 0 else {
                    self?.centerWindow(window)
                    return
                }
                // 防止内容特别多时把窗口撑出屏幕：以窗口所在屏幕可见高度的 90% 为上限。
                let maxAllowedHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
                let clampedHeight = min(fittingHeight, maxAllowedHeight * 0.9)
                if abs(window.contentRect(forFrameRect: window.frame).height - clampedHeight) > 0.5 {
                    window.setContentSize(NSSize(width: resolvedSize.width, height: clampedHeight))
                }
                self?.centerWindow(window)
            }
        } else {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.centerWindow(window)
            }
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
        case "history":
            historyWindow?.close()
            historyWindow = nil
        case "restPicker":
            restPickerWindow?.close()
            restPickerWindow = nil
        case "superBadge":
            closeSuperWorkhorseBadgeWindow()
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
        case "history":
            historyWindow = nil
        case "restPicker":
            // 用户关闭选择器时不取消已经启动的休息；只清空窗口引用。
            restPickerWindow = nil
        case "superBadge":
            superBadgeWindow = nil
        default:
            break
        }
    }
}

private final class WorkHorseOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
