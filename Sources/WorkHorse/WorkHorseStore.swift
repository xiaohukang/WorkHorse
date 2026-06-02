import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

final class WorkHorseStore: ObservableObject {
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

    var currentTask: WorkTask? {
        today.tasks.first { $0.status == .running }
    }

    var isClockedOutToday: Bool {
        today.clockOutTime != nil
    }

    var status: WorkHorseStatus {
        if isClockedOutToday { return .clockedOut }
        if currentTask != nil { return .running }
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

    func startTask(title rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        rotateDayIfNeeded(at: Date())
        let startDate = Date()

        if today.clockInTime == nil {
            today.clockInTime = startDate
        }

        if let runningIndex = today.tasks.firstIndex(where: { $0.status == .running }) {
            finishTask(at: runningIndex, status: .interrupted, endDate: startDate)
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
    }

    @discardableResult
    func completeCurrentTask(status: TaskStatus = .completed) -> WorkTask? {
        guard let index = today.tasks.firstIndex(where: { $0.status == .running }) else { return nil }
        let endDate = Date()
        finishTask(at: index, status: status, endDate: endDate)
        persistToday()
        return today.tasks[index]
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
            return max(0, Int(referenceDate.timeIntervalSince(task.startTime)))
        }
        return max(0, task.durationSeconds)
    }

    func totalSeconds(at referenceDate: Date) -> Int {
        today.tasks.reduce(0) { partial, task in
            partial + duration(for: task, at: referenceDate)
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
            "| \(task.title) | \(WorkHorseFormatters.durationString(seconds: duration(for: task, at: referenceDate))) |"
        }.joined(separator: "\n")

        return """
        # 今日工作报告

        日期：\(date)

        ## 总览

        - 总工作时长：\(WorkHorseFormatters.durationString(seconds: totalSeconds(at: referenceDate)))
        - 任务数量：\(tasks.count)个

        ## 任务明细

        | 任务 | 时长 |
        |---|---:|
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
        var lines = ["任务,开始时间,结束时间,时长,状态"]
        for task in reportTasks(at: referenceDate) {
            let line = [
                WorkHorseFormatters.csvEscape(task.title),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.clockTime(task.startTime)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.clockTime(task.endTime)),
                WorkHorseFormatters.csvEscape(WorkHorseFormatters.durationString(seconds: duration(for: task, at: referenceDate))),
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
            finishTask(at: runningIndex, status: .interrupted, endDate: referenceDate)
            persistToday()
        }

        currentDateKey = dateKey
        today = storage.loadDailyLog(for: dateKey)
    }

    private func finishTask(at index: Int, status: TaskStatus, endDate: Date) {
        var task = today.tasks[index]
        task.endTime = endDate
        task.durationSeconds = max(0, Int(endDate.timeIntervalSince(task.startTime)))
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
