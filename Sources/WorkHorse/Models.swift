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
    case completed
    case interrupted
    case endedByOffwork = "ended_by_offwork"

    var displayName: String {
        switch self {
        case .running: return "进行中"
        case .completed: return "已完成"
        case .interrupted: return "被打断"
        case .endedByOffwork: return "下班结束"
        }
    }
}

struct WorkTask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var date: String
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Int
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
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DailyLog: Codable, Equatable {
    var date: String
    var clockInTime: Date?
    var clockOutTime: Date?
    var tasks: [WorkTask]

    static func empty(for date: String) -> DailyLog {
        DailyLog(date: date, clockInTime: nil, clockOutTime: nil, tasks: [])
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
