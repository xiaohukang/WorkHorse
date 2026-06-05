import Foundation

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        case .sunday: return "周日"
        }
    }

    var fullName: String {
        switch self {
        case .monday: return "星期一"
        case .tuesday: return "星期二"
        case .wednesday: return "星期三"
        case .thursday: return "星期四"
        case .friday: return "星期五"
        case .saturday: return "星期六"
        case .sunday: return "星期日"
        }
    }
}

struct WorkSettings: Codable, Equatable {
    var workDays: [Int]
    var workStartTime: String
    var workEndTime: String
    var enableFocusReminder: Bool
    var focusReminderInterval: Int
    var enableOffworkReminder: Bool
    var offworkReminderInterval: Int
    var enableLaunchAtLogin: Bool
    var hasCompletedOnboarding: Bool

    static let `default` = WorkSettings(
        workDays: [1, 2, 3, 4, 5],
        workStartTime: "09:00",
        workEndTime: "18:00",
        enableFocusReminder: true,
        focusReminderInterval: 25,
        enableOffworkReminder: true,
        offworkReminderInterval: 15,
        enableLaunchAtLogin: false,
        hasCompletedOnboarding: false
    )
}

enum TaskStatus: String, Codable, CaseIterable {
    case running
    case paused
    case completed
    case interrupted
    case endedByOffwork = "ended_by_offwork"

    var displayName: String {
        switch self {
        case .running: return "进行中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .interrupted: return "被打断"
        case .endedByOffwork: return "下班结束"
        }
    }

    /// 任务已结束（不会再继续计时）。
    var isFinished: Bool {
        switch self {
        case .running, .paused: return false
        case .completed, .interrupted, .endedByOffwork: return true
        }
    }
}

struct WorkTask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var date: String
    /// 当前正在计时段的开始时间；任务处于 `.paused` / 已结束时此字段不再代表实际开始。
    var startTime: Date
    var endTime: Date?
    /// 任务结束后保存的最终时长；进行中/暂停时与 `accumulatedSeconds` 一致。
    var durationSeconds: Int
    /// 暂停前已累计的时长（秒）。任务处于 `.running` 时：
    /// `totalDuration = accumulatedSeconds + (now - startTime)`。
    var accumulatedSeconds: Int
    /// 已累计的下班后加班时长（秒）。和 `accumulatedSeconds` 同样分段结算：
    /// 任务处于 `.running` 时 `overtimeSeconds` 包含已结束段 + 当前正在进行的加班段。
    var overtimeSeconds: Int
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        date: String,
        startTime: Date,
        endTime: Date? = nil,
        durationSeconds: Int = 0,
        accumulatedSeconds: Int = 0,
        overtimeSeconds: Int = 0,
        status: TaskStatus = .running,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.accumulatedSeconds = accumulatedSeconds
        self.overtimeSeconds = overtimeSeconds
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // 兼容历史 JSON：旧文件没有 `accumulatedSeconds` / `overtimeSeconds` 字段时取默认值。
    private enum CodingKeys: String, CodingKey {
        case id, title, date, startTime, endTime, durationSeconds, accumulatedSeconds, overtimeSeconds, status, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(String.self, forKey: .date)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        accumulatedSeconds = try container.decodeIfPresent(Int.self, forKey: .accumulatedSeconds) ?? durationSeconds
        overtimeSeconds = try container.decodeIfPresent(Int.self, forKey: .overtimeSeconds) ?? 0
        status = try container.decode(TaskStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(accumulatedSeconds, forKey: .accumulatedSeconds)
        try container.encode(overtimeSeconds, forKey: .overtimeSeconds)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct TaskTimeSummary: Identifiable, Equatable {
    var id: String
    var title: String
    var firstStartTime: Date
    var lastEndTime: Date?
    var durationSeconds: Int
    var overtimeSeconds: Int
    var taskCount: Int
    var hasRunningTask: Bool
    var hasPausedTask: Bool
    var latestStatus: TaskStatus
    var latestUpdatedAt: Date

    var isOngoing: Bool {
        hasRunningTask || hasPausedTask
    }

    var statusDisplayName: String {
        if hasRunningTask { return TaskStatus.running.displayName }
        if hasPausedTask { return TaskStatus.paused.displayName }
        return latestStatus.displayName
    }
}

/// 一次休息记录：用户主动进入休息状态时由 Store 记录。
/// 进入休息时若当前有运行中的任务，会先暂停任务；休息结束（达到预计结束时间或用户主动恢复）后，
/// 任务的累计时长不会把休息段算进去。
struct RestSegment: Identifiable, Codable, Equatable {
    var id: String
    var startTime: Date
    var plannedDurationSeconds: Int
    var endTime: Date?

    init(
        id: String = UUID().uuidString,
        startTime: Date,
        plannedDurationSeconds: Int,
        endTime: Date? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.plannedDurationSeconds = max(0, plannedDurationSeconds)
        self.endTime = endTime
    }

    /// 实际休息秒数。仍在进行中时按"现在 - 开始时间"计算。
    func actualDurationSeconds(at referenceDate: Date) -> Int {
        let end = endTime ?? referenceDate
        return max(0, Int(end.timeIntervalSince(startTime)))
    }
}

struct DailyLog: Codable, Equatable {
    var date: String
    var clockInTime: Date?
    var clockOutTime: Date?
    var tasks: [WorkTask]
    var restSegments: [RestSegment]

    static func empty(for date: String) -> DailyLog {
        DailyLog(date: date, clockInTime: nil, clockOutTime: nil, tasks: [], restSegments: [])
    }

    private enum CodingKeys: String, CodingKey {
        case date, clockInTime, clockOutTime, tasks, restSegments
    }

    init(date: String, clockInTime: Date?, clockOutTime: Date?, tasks: [WorkTask], restSegments: [RestSegment] = []) {
        self.date = date
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.tasks = tasks
        self.restSegments = restSegments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        clockInTime = try container.decodeIfPresent(Date.self, forKey: .clockInTime)
        clockOutTime = try container.decodeIfPresent(Date.self, forKey: .clockOutTime)
        tasks = try container.decodeIfPresent([WorkTask].self, forKey: .tasks) ?? []
        restSegments = try container.decodeIfPresent([RestSegment].self, forKey: .restSegments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(clockInTime, forKey: .clockInTime)
        try container.encodeIfPresent(clockOutTime, forKey: .clockOutTime)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(restSegments, forKey: .restSegments)
    }
}

struct DailyWorkSummary: Identifiable, Equatable {
    var id: String { date }

    var date: String
    var clockInTime: Date?
    var clockOutTime: Date?
    var taskSummaries: [TaskTimeSummary]
    var totalSeconds: Int
    var overtimeSeconds: Int
    var restSeconds: Int

    var taskCount: Int {
        taskSummaries.count
    }
}

enum WorkHorseStatus: Equatable {
    case idle
    case running
    case waiting
    case clockedOut

    var symbolName: String {
        switch self {
        case .idle: return "clock"
        case .running: return "timer.circle.fill"
        case .waiting: return "bell.badge.fill"
        case .clockedOut: return "checkmark.circle.fill"
        }
    }
}
