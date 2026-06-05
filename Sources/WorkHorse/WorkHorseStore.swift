import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

final class WorkHorseStore: ObservableObject {
    /// 同一时间可追踪的最大任务数（包含运行中、暂停中、未结束的）。
    static let maxTrackedTasks: Int = 10
    /// 每日累计工作达到 10 小时后点亮「超级牛马认证」徽章。
    static let superWorkhorseBadgeThresholdSeconds: Int = 10 * 60 * 60

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

    /// 是否正处于休息中。休息中时主动任务会被暂停，状态栏会显示一个 ⏸ + 倒计时提示。
    var isResting: Bool {
        today.restSegments.contains { $0.endTime == nil }
    }

    /// 当前正在进行的休息段（最多一个）。存在多条未结束的记录时只返回最早创建的那条。
    var currentRestSegment: RestSegment? {
        today.restSegments.first { $0.endTime == nil }
    }

    /// 当日已结束 + 正在进行的休息总时长（秒）。
    var totalRestSeconds: Int {
        totalRestSeconds(at: Date())
    }

    func totalRestSeconds(at referenceDate: Date) -> Int {
        today.restSegments.reduce(0) { partial, segment in
            partial + segment.actualDurationSeconds(at: referenceDate)
        }
    }

    /// 当日已结束的休息段，按开始时间倒序。仅供报告使用。
    var finishedRestSegments: [RestSegment] {
        today.restSegments
            .filter { $0.endTime != nil }
            .sorted { $0.startTime > $1.startTime }
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

    var reportTaskSummaries: [TaskTimeSummary] {
        reportTaskSummaries(at: Date())
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

        rotateDayIfNeeded(at: Date())
        let startDate = Date()

        if today.clockInTime == nil {
            today.clockInTime = startDate
        }

        let normalizedTitle = normalizedTaskTitle(title)

        // 用户在休息中选择"开始新任务"：立刻结束当前休息段，
        // 这样新任务从 startDate 这一刻起开始计时，不会被错误的算成"休息中也在工作"。
        // 不自动恢复之前被暂停的任务 —— 用户既然选择了"开始新任务"，就以新任务为准。
        if isResting {
            endCurrentRestIfNeeded(at: startDate, resumeLatestPaused: false)
        }

        let matchingActiveIndices = today.tasks.indices.filter {
            !today.tasks[$0].status.isFinished && normalizedTaskTitle(today.tasks[$0].title) == normalizedTitle
        }
        let existingIndex = matchingActiveIndices.first(where: { today.tasks[$0].status == .running })
            ?? matchingActiveIndices.max { today.tasks[$0].updatedAt < today.tasks[$1].updatedAt }

        if let existingIndex {
            if let runningIndex = today.tasks.firstIndex(where: { $0.status == .running }),
               runningIndex != existingIndex {
                pauseTaskInternal(at: runningIndex, at: startDate)
            }

            var task = today.tasks[existingIndex]
            if task.status != .running {
                task.status = .running
                task.startTime = startDate
            }
            task.updatedAt = startDate
            today.tasks[existingIndex] = task
            persistToday()
            return true
        }

        guard canStartNewTask else {
            showToast("最多同时追踪 \(Self.maxTrackedTasks) 个任务")
            return false
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

        // 休息中选择继续某个任务时，先把当前休息段收尾，避免"恢复任务"的瞬间
        // 还残留一个未结束的休息段。
        // 这次调用 resumeTask 自己会负责把目标 task 切到 running，不需要再让
        // endCurrentRestIfNeeded 自动恢复其他任务，否则会同时启动两个任务。
        if isResting {
            endCurrentRestIfNeeded(at: now, resumeLatestPaused: false)
        }

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
        endCurrentRestIfNeeded(at: Date())
        today.clockOutTime = Date()
        persistToday()
    }

    // MARK: - 休息管理

    /// 用户主动进入休息状态。
    ///
    /// - Parameter minutes: 期望休息的分钟数，由调用方负责做范围校验（2~20）。
    /// - Returns: 新创建的休息段；调用方需要根据此对象去更新下次提醒时间、显示倒计时等。
    @discardableResult
    func startRest(minutes: Int) -> RestSegment? {
        guard !isResting else { return nil }
        guard minutes > 0 else { return nil }

        let now = Date()
        rotateDayIfNeeded(at: now)

        // 进入休息时，若当前有正在运行的任务，先把任务暂停，休息结束后再恢复。
        pauseRunningTask()

        let segment = RestSegment(
            startTime: now,
            plannedDurationSeconds: minutes * 60
        )
        today.restSegments.append(segment)
        persistToday()
        return segment
    }

    /// 把当前休息段标记为结束（在休息时间用完 / 用户手动恢复时调用）。
    ///
    /// - Parameters:
    ///   - referenceDate: 休息结束时间。
    ///   - resumeLatestPaused: 是否自动恢复最近一次暂停的任务。
    ///     - 休息倒计时结束 / 用户点"结束休息"时传 `true`，符合"放空完继续干活"的预期；
    ///     - 用户在休息中选择"开始新任务"时传 `false`，因为新任务才是用户真正想做的。
    /// - Returns: 被恢复的任务（若有）。
    @discardableResult
    func endCurrentRestIfNeeded(at referenceDate: Date, resumeLatestPaused: Bool = true) -> WorkTask? {
        guard let segment = currentRestSegment else { return nil }

        if let index = today.restSegments.firstIndex(where: { $0.id == segment.id }) {
            var settled = today.restSegments[index]
            settled.endTime = referenceDate
            today.restSegments[index] = settled
            persistToday()
        }

        guard resumeLatestPaused else { return nil }

        // 找到最靠近当前时刻的、状态为 paused 的任务，让它继续计时。
        // 没有任何暂停中任务时（例如用户在无任务状态下休息），就直接结束，不创建新任务。
        let paused = today.tasks
            .filter { $0.status == .paused }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let resumeTarget = paused.first else { return nil }
        _ = resumeTask(id: resumeTarget.id)
        return currentTask
    }

    func duration(for task: WorkTask) -> Int {
        duration(for: task, at: Date())
    }

    func duration(for task: WorkTask, at referenceDate: Date) -> Int {
        resolvedDuration(for: task, at: referenceDate, countsLiveSegment: task.date == currentDateKey)
    }

    private func resolvedDuration(for task: WorkTask, at referenceDate: Date, countsLiveSegment: Bool) -> Int {
        if countsLiveSegment, task.status == .running {
            return max(0, task.accumulatedSeconds + Int(referenceDate.timeIntervalSince(task.startTime)))
        }
        return max(0, task.durationSeconds)
    }

    /// 任务已计入的加班时长（秒）。进行中时包含已结束段 + 当前正在进行的加班段。
    func overtimeSeconds(for task: WorkTask) -> Int {
        overtimeSeconds(for: task, at: Date())
    }

    func overtimeSeconds(for task: WorkTask, at referenceDate: Date) -> Int {
        resolvedOvertimeSeconds(for: task, at: referenceDate, countsLiveSegment: task.date == currentDateKey)
    }

    private func resolvedOvertimeSeconds(for task: WorkTask, at referenceDate: Date, countsLiveSegment: Bool) -> Int {
        let settled = max(0, task.overtimeSeconds)
        if countsLiveSegment, task.status == .running {
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

    func hasEarnedSuperWorkhorseBadge(at referenceDate: Date) -> Bool {
        totalSeconds(at: referenceDate) >= Self.superWorkhorseBadgeThresholdSeconds
    }

    func remainingSecondsForSuperWorkhorseBadge(at referenceDate: Date) -> Int {
        max(0, Self.superWorkhorseBadgeThresholdSeconds - totalSeconds(at: referenceDate))
    }

    func reportTasks(at referenceDate: Date) -> [WorkTask] {
        today.tasks.filter { duration(for: $0, at: referenceDate) > 0 }
    }

    func reportTaskSummaries(at referenceDate: Date) -> [TaskTimeSummary] {
        taskSummaries(in: today, at: referenceDate)
    }

    func historyRecords(at referenceDate: Date = Date()) -> [DailyWorkSummary] {
        var logsByDate: [String: DailyLog] = [:]
        for log in storage.loadAllDailyLogs() {
            logsByDate[log.date] = log
        }
        logsByDate[currentDateKey] = today

        return logsByDate.values
            .map { dailySummary(for: $0, at: referenceDate) }
            .filter { summary in
                summary.totalSeconds > 0
                    || summary.restSeconds > 0
                    || summary.clockInTime != nil
                    || summary.clockOutTime != nil
            }
            .sorted { $0.date > $1.date }
    }

    func dailySummary(for log: DailyLog, at referenceDate: Date) -> DailyWorkSummary {
        let summaries = taskSummaries(in: log, at: referenceDate)
        return DailyWorkSummary(
            date: log.date,
            clockInTime: log.clockInTime,
            clockOutTime: log.clockOutTime,
            taskSummaries: summaries,
            totalSeconds: summaries.reduce(0) { $0 + $1.durationSeconds },
            overtimeSeconds: summaries.reduce(0) { $0 + $1.overtimeSeconds },
            restSeconds: totalRestSeconds(in: log, at: referenceDate)
        )
    }

    func taskSummaries(in log: DailyLog, at referenceDate: Date) -> [TaskTimeSummary] {
        let countsLiveSegment = log.date == currentDateKey
        var summaries: [String: TaskTimeSummary] = [:]
        var orderedKeys: [String] = []

        for task in log.tasks {
            let durationSeconds = resolvedDuration(
                for: task,
                at: referenceDate,
                countsLiveSegment: countsLiveSegment
            )
            guard durationSeconds > 0 || !task.status.isFinished else { continue }

            let key = normalizedTaskTitle(task.title)
            let overtimeSeconds = resolvedOvertimeSeconds(
                for: task,
                at: referenceDate,
                countsLiveSegment: countsLiveSegment
            )

            if summaries[key] == nil {
                orderedKeys.append(key)
                summaries[key] = TaskTimeSummary(
                    id: key,
                    title: task.title,
                    firstStartTime: task.createdAt,
                    lastEndTime: task.status.isFinished ? task.endTime : nil,
                    durationSeconds: durationSeconds,
                    overtimeSeconds: overtimeSeconds,
                    taskCount: 1,
                    hasRunningTask: task.status == .running,
                    hasPausedTask: task.status == .paused,
                    latestStatus: task.status,
                    latestUpdatedAt: task.updatedAt
                )
                continue
            }

            var summary = summaries[key]!
            summary.firstStartTime = min(summary.firstStartTime, task.createdAt)
            if task.status.isFinished, let endTime = task.endTime {
                if let existingEndTime = summary.lastEndTime {
                    summary.lastEndTime = max(existingEndTime, endTime)
                } else {
                    summary.lastEndTime = endTime
                }
            }
            summary.durationSeconds += durationSeconds
            summary.overtimeSeconds += overtimeSeconds
            summary.taskCount += 1
            summary.hasRunningTask = summary.hasRunningTask || task.status == .running
            summary.hasPausedTask = summary.hasPausedTask || task.status == .paused
            if task.updatedAt >= summary.latestUpdatedAt {
                summary.latestStatus = task.status
                summary.latestUpdatedAt = task.updatedAt
            }
            summaries[key] = summary
        }

        return orderedKeys.compactMap { summaries[$0] }
    }

    private func totalRestSeconds(in log: DailyLog, at referenceDate: Date) -> Int {
        let countsLiveSegment = log.date == currentDateKey
        return log.restSegments.reduce(0) { partial, segment in
            if segment.endTime == nil, !countsLiveSegment {
                return partial
            }
            return partial + segment.actualDurationSeconds(at: referenceDate)
        }
    }

    func reportMarkdown() -> String {
        let referenceDate = Date()
        let tasks = reportTaskSummaries(at: referenceDate)
        let date = WorkHorseFormatters.displayDate.string(from: referenceDate)
        let rows = tasks.map { task in
            let total = WorkHorseFormatters.durationString(seconds: task.durationSeconds)
            let overtime = WorkHorseFormatters.durationString(seconds: task.overtimeSeconds)
            let count = task.taskCount > 1 ? "\(task.taskCount)次" : "1次"
            return "| \(task.title) | \(total) | \(overtime) | \(count) |"
        }.joined(separator: "\n")

        let restSeconds = totalRestSeconds(at: referenceDate)
        let restSummary = restSeconds > 0
            ? "- 休息时长：\(WorkHorseFormatters.durationString(seconds: restSeconds))"
            : ""
        let badgeSummary = hasEarnedSuperWorkhorseBadge(at: referenceDate)
            ? "已获得"
            : "未获得（还差 \(WorkHorseFormatters.durationString(seconds: remainingSecondsForSuperWorkhorseBadge(at: referenceDate)))）"

        return """
        # 今日工作报告

        日期：\(date)

        ## 总览

        - 总工作时长：\(WorkHorseFormatters.durationString(seconds: totalSeconds(at: referenceDate)))
        - 加班时长：\(WorkHorseFormatters.durationString(seconds: totalOvertimeSeconds(at: referenceDate)))
        - 任务数量：\(tasks.count)个
        - 超级牛马认证：\(badgeSummary)
        \(restSummary)

        ## 任务明细

        | 任务 | 时长 | 加班 | 记录 |
        |---|---:|---:|---:|
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
        var lines = ["任务,开始时间,结束时间,时长,加班,状态,记录数"]
        for task in reportTaskSummaries(at: referenceDate) {
            let line = [
                WorkHorseFormatters.csvEscape(task.title),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.clockTime(task.firstStartTime)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.clockTime(task.lastEndTime)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: task.durationSeconds)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: task.overtimeSeconds)),
                WorkHorseFormatters.csvEscape(task.statusDisplayName),
                WorkHorseFormatters.csvEscape("\(task.taskCount)")
            ].joined(separator: ",")
            lines.append(line)
        }
        let restSeconds = totalRestSeconds(at: referenceDate)
        if restSeconds > 0 {
            lines.append([
                WorkHorseFormatters.csvEscape("休息"),
                WorkHorseFormatters.csvEscape(""),
                WorkHorseFormatters.csvEscape(""),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: restSeconds)),
                WorkHorseFormatters.csvEscape(""),
                WorkHorseFormatters.csvEscape("休息"),
                WorkHorseFormatters.csvEscape("")
            ].joined(separator: ","))
        }
        lines.append([
            WorkHorseFormatters.csvEscape("超级牛马认证"),
            WorkHorseFormatters.csvEscape(""),
            WorkHorseFormatters.csvEscape(""),
            WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: totalSeconds(at: referenceDate))),
            WorkHorseFormatters.csvEscape(""),
            WorkHorseFormatters.csvEscape(hasEarnedSuperWorkhorseBadge(at: referenceDate) ? "已获得" : "未获得"),
            WorkHorseFormatters.csvEscape("")
        ].joined(separator: ","))
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
        // 跨天时把仍在进行的休息段标记为结束，避免状态泄露到下一天。
        if let restIndex = today.restSegments.firstIndex(where: { $0.endTime == nil }) {
            var settled = today.restSegments[restIndex]
            settled.endTime = referenceDate
            today.restSegments[restIndex] = settled
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

    private func normalizedTaskTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
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
