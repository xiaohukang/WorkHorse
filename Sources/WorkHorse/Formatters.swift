import Foundation

enum WorkHorseFormatters {
    static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let displayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func dateKey(for date: Date = Date()) -> String {
        dayKey.string(from: date)
    }

    static func displayDayAndWeekday(for date: Date = Date()) -> String {
        let weekdayIndex = Calendar.current.workHorseWeekdayIndex(from: date)
        let weekday = Weekday(rawValue: weekdayIndex)?.shortName ?? ""
        return "\(displayDate.string(from: date)) \(weekday)"
    }

    static func timerString(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let seconds = safeSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func durationString(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        if safeSeconds < 60 {
            return safeSeconds == 0 ? "0分钟" : "1分钟"
        }

        let totalMinutes = Int((Double(safeSeconds) / 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        if hours > 0 {
            return "\(hours)小时"
        }
        return "\(minutes)分钟"
    }

    static func clockTime(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        return time.string(from: date)
    }

    static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension Calendar {
    func workHorseWeekdayIndex(from date: Date) -> Int {
        let systemWeekday = component(.weekday, from: date)
        return systemWeekday == 1 ? 7 : systemWeekday - 1
    }
}

extension WorkSettings {
    func minutes(from timeString: String) -> Int {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return max(0, min(23, parts[0])) * 60 + max(0, min(59, parts[1]))
    }

    func date(on day: Date, from timeString: String) -> Date {
        let minutes = minutes(from: timeString)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return Calendar.current.date(from: components) ?? day
    }

    func isWorkday(_ date: Date = Date()) -> Bool {
        workDays.contains(Calendar.current.workHorseWeekdayIndex(from: date))
    }

    func isWithinWorkWindow(_ date: Date = Date()) -> Bool {
        guard isWorkday(date) else { return false }

        let start = minutes(from: workStartTime)
        let end = minutes(from: workEndTime)
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if start <= end {
            return current >= start && current <= end
        }

        return current >= start || current <= end
    }
}
