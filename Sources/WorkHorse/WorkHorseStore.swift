import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

final class WorkHorseStore: ObservableObject {
    /// 同一时间可追踪的最大任务数（包含运行中、暂停中、未结束的）。
    static let maxTrackedTasks: Int = 10

    @Published private(set) var settings: WorkSettings
    @Published private(set) var today: DailyLog
    @Published var toast: String?

    private let storage: JSONStorage
    private var currentDateKey: String
    private(set) var now: Date = Date()

    init(storage: JSONStorage = JSONStorage()) {
        self.storage = storage
        settings = storage.loadSettings()
        currentDateKey = WorkHorseFormatters.dateKey()
        today = storage.loadDailyLog(for: currentDateKey)
    }

    /// 当前正在计时的任务（同一时间最多一个）。
    var currentTask: WorkTask? {
        today.tasks.first { $0.status == .running }
    }

    /// 未结束的任务（运行中 + 暂停中），按创建时间倒序展示。
    var activeTasks: [WorkTask] {
        today.tasks
            .filter { !$0.status.isFinished }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 当日已结束的任务，按开始时间倒序。
    var finishedTasks: [WorkTask] {
        today.tasks
            .filter { $0.status.isFinished }
            .sorted { $0.startTime > $1.startTime }
    }

    /// 是否还能再新增任务（未达上限；下班后也允许继续记录新任务）。
    var canStartNewTask: Bool {
        activeTasks.count < Self.maxTrackedTasks
    }

    var isClockedOutToday: Bool {
        today.clockOutTime != nil
    }

    var status: WorkHorseStatus {
        if currentTask != nil { return .running }
        if isClockedOutToday { return .clockedOut }
        return .idle
    }

    var todayTotalSeconds: Int {
        totalSeconds(at: Date())
    }

    var reportTasks: [WorkTask] {
        reportTasks(at: Date())
    }

    func tick() {
        let currentDate = Date()
        now = currentDate
        rotateDayIfNeeded(at: currentDate)
    }

    func saveSettings(_ nextSettings: WorkSettings) {
        settings = nextSettings
        storage.saveSettings(nextSettings)
        updateLaunchAtLogin(nextSettings.enableLaunchAtLogin)
    }

    func completeOnboarding(with nextSettings: WorkSettings) {
        var configured = nextSettings
        configured.hasCompletedOnboarding = true
        saveSettings(configured)
    }

    /// 新建任务；如果当前有正在运行的任务，则自动暂停它，新任务从现在开始计时。
    @discardableResult
    func startTask(title rawTitle: String) -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        guard canStartNewTask else {
            showToast("最多同时追踪 \(Self.maxTrackedTasks) 个任务")
            return false
        }

        rotateDayIfNeeded(at: Date())
        let startDate = Date()

        if today.clockInTime == nil {
            today.clockInTime = startDate
        }

        // 同一时间只能有一个任务处于 running，新任务开始时把旧任务暂停。
        if let runningIndex = today.tasks.firstIndex(where: { $0.status == .running }) {
            pauseTaskInternal(at: runningIndex, at: startDate)
        }

        let task = WorkTask(
            title: title,
            date: currentDateKey,
            startTime: startDate,
            createdAt: startDate,
            updatedAt: startDate
        )
        today.tasks.append(task)
        persistToday()
        return true
    }

    /// 显式把任务切换为运行中（同一时间仅一个会成功）。
    @discardableResult
    func resumeTask(id: String) -> Bool {
        guard let index = today.tasks.firstIndex(where: { $0.id == id }) else { return false }
        guard !today.tasks[index].status.isFinished else { return false }

        let now = Date()
        rotateDayIfNeeded(at: now)

        // 暂停当前正在运行的，让目标任务启动。
        if let runningIndex = today.tasks.firstIndex(where: { $0.status == .running }), runningIndex != index {
            pauseTaskInternal(at: runningIndex, at: now)
        }

        var task = today.tasks[index]
        // 同一任务恢复无需处理 accumulatedSeconds；跨日时累计重新开始。
        if task.date != currentDateKey {
            task.date = currentDateKey
            task.accumulatedSeconds = 0
            task.overtimeSeconds = 0
            task.startTime = now
        }
        task.status = .running
        task.startTime = now
        task.updatedAt = now
        today.tasks[index] = task
        persistToday()
        return true
    }

    /// 把运行中的任务手动暂停（仅对当前任务有效）。
    @discardableResult
    func pauseRunningTask() -> Bool {
        guard let index = today.tasks.firstIndex(where: { $0.status == .running }) else { return false }
        pauseTaskInternal(at: index, at: Date())
        persistToday()
        return true
    }

    /// 完成指定任务（无论运行中或暂停中）。
    @discardableResult
    func completeTask(id: String, status: TaskStatus = .completed) -> WorkTask? {
        guard let index = today.tasks.firstIndex(where: { $0.id == id }) else { return nil }
        guard !today.tasks[index].status.isFinished else { return nil }
        finishTask(at: index, status: status, endDate: Date())
        persistToday()
        return today.tasks[index]
    }

    /// 完成当前正在运行的任务（兼容旧 API，供菜单/快捷键使用）。
    @discardableResult
    func completeCurrentTask(status: TaskStatus = .completed) -> WorkTask? {
        guard let id = currentTask?.id else { return nil }
        return completeTask(id: id, status: status)
    }

    func clockOutToday() {
        _ = completeCurrentTask(status: .endedByOffwork)
        today.clockOutTime = Date()
        persistToday()
    }

    func duration(for task: WorkTask) -> Int {
        duration(for: task, at: Date())
    }

    func duration(for task: WorkTask, at referenceDate: Date) -> Int {
        if task.status == .running {
            return max(0, task.accumulatedSeconds + Int(referenceDate.timeIntervalSince(task.startTime)))
        }
        return max(0, task.durationSeconds)
    }

    /// 任务已计入的加班时长（秒）。进行中时包含已结束段 + 当前正在进行的加班段。
    func overtimeSeconds(for task: WorkTask) -> Int {
        overtimeSeconds(for: task, at: Date())
    }

    func overtimeSeconds(for task: WorkTask, at referenceDate: Date) -> Int {
        let settled = max(0, task.overtimeSeconds)
        if task.status == .running {
            // 当前进行中的时段,如果跨越了下班时间,只把下班后那部分计入加班。
            let segment = max(0, Int(referenceDate.timeIntervalSince(task.startTime)))
            return settled + overtimeSlice(ofSegment: segment, from: task.startTime, to: referenceDate)
        }
        return settled
    }

    /// 一段 `[from, to]` 时间内,落在「下班时间(workEndTime)之后」的部分（秒）。
    /// 用于把运行中任务的当前时段拆成"工作时间"和"加班时间"两段。
    private func overtimeSlice(ofSegment segment: Int, from segmentStart: Date, to segmentEnd: Date) -> Int {
        guard segment > 0 else { return 0 }
        // 仅当今天是工作日时才计入加班；休息日不设"下班"概念,
        // 避免用户周末随手记一段却被识别成加班。
        guard settings.isWorkday(segmentStart) else { return 0 }
        let offworkDate = settings.date(on: segmentStart, from: settings.workEndTime)
        guard segmentEnd > offworkDate else { return 0 }
        let overtimeStart = max(segmentStart, offworkDate)
        return max(0, Int(segmentEnd.timeIntervalSince(overtimeStart)))
    }

    func totalSeconds(at referenceDate: Date) -> Int {
        today.tasks.reduce(0) { partial, task in
            partial + duration(for: task, at: referenceDate)
        }
    }

    func totalOvertimeSeconds(at referenceDate: Date) -> Int {
        today.tasks.reduce(0) { partial, task in
            partial + overtimeSeconds(for: task, at: referenceDate)
        }
    }

    func reportTasks(at referenceDate: Date) -> [WorkTask] {
        today.tasks.filter { duration(for: $0, at: referenceDate) > 0 }
    }

    func reportMarkdown() -> String {
        let referenceDate = Date()
        let tasks = reportTasks(at: referenceDate)
        let date = WorkHorseFormatters.displayDate.string(from: referenceDate)
        let rows = tasks.map { task in
            let total = WorkHorseFormatters.durationString(seconds: duration(for: task, at: referenceDate))
            let overtime = WorkHorseFormatters.durationString(seconds: overtimeSeconds(for: task, at: referenceDate))
            return "| \(task.title) | \(total) | \(overtime) |"
        }.joined(separator: "\n")

        return """
        # 今日工作报告

        日期：\(date)

        ## 总览

        - 总工作时长：\(WorkHorseFormatters.durationString(seconds: totalSeconds(at: referenceDate)))
        - 加班时长：\(WorkHorseFormatters.durationString(seconds: totalOvertimeSeconds(at: referenceDate)))
        - 任务数量：\(tasks.count)个

        ## 任务明细

        | 任务 | 时长 | 加班 |
        |---|---:|---:|
        \(rows)
        """
    }

    func copyReportMarkdown() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(reportMarkdown(), forType: .string)
        showToast("日报已复制")
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "导出今日工作报告"
        panel.nameFieldStringValue = "WorkHorse-\(currentDateKey).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csvString().write(to: url, atomically: true, encoding: .utf8)
            showToast("CSV 已导出")
        } catch {
            showToast("CSV 导出失败")
        }
    }

    func csvString() -> String {
        let referenceDate = Date()
        var lines = ["任务,开始时间,结束时间,时长,加班,状态"]
        for task in reportTasks(at: referenceDate) {
            let line = [
                WorkHorseFormatters.csvEscape(task.title),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.clockTime(task.startTime)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.clockTime(task.endTime)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: duration(for: task, at: referenceDate))),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: overtimeSeconds(for: task, at: referenceDate))),
                WorkHorseFormatters.csvEscape(task.status.displayName)
            ].joined(separator: ",")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    func storageDescription() -> String {
        NSHomeDirectory() + "/Library/Application Support/WorkHorse"
    }

    private func rotateDayIfNeeded(at referenceDate: Date) {
        let dateKey = WorkHorseFormatters.dateKey(for: referenceDate)
        guard dateKey != currentDateKey else { return }

        if let runningIndex = today.tasks.firstIndex(where: { $0.status == .running }) {
            pauseTaskInternal(at: runningIndex, at: referenceDate)
            persistToday()
        }

        currentDateKey = dateKey
        today = storage.loadDailyLog(for: dateKey)
    }

    /// 把任务从 running 切到 paused，结算并保存当前时段的累计时长。
    private func pauseTaskInternal(at index: Int, at endDate: Date) {
        guard today.tasks[index].status == .running else { return }
        var task = today.tasks[index]
        let segment = max(0, Int(endDate.timeIntervalSince(task.startTime)))
        task.accumulatedSeconds += segment
        task.overtimeSeconds += overtimeSlice(ofSegment: segment, from: task.startTime, to: endDate)
        task.durationSeconds = task.accumulatedSeconds
        task.startTime = endDate
        task.status = .paused
        task.updatedAt = endDate
        today.tasks[index] = task
    }

    private func finishTask(at index: Int, status: TaskStatus, endDate: Date) {
        var task = today.tasks[index]
        if task.status == .running {
            let segment = max(0, Int(endDate.timeIntervalSince(task.startTime)))
            task.accumulatedSeconds += segment
            task.overtimeSeconds += overtimeSlice(ofSegment: segment, from: task.startTime, to: endDate)
        }
        task.endTime = endDate
        task.durationSeconds = max(0, task.accumulatedSeconds)
        task.status = status
        task.updatedAt = endDate
        today.tasks[index] = task
    }

    private func persistToday() {
        storage.saveDailyLog(today)
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toast == message {
                self?.toast = nil
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                showToast("开机启动设置暂未生效")
            }
        }
    }
}
