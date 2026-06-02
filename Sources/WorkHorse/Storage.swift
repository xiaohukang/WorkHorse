import Foundation

final class JSONStorage {
    private let baseURL: URL
    private let settingsURL: URL
    private let tasksDirectoryURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        baseURL = (applicationSupport ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("WorkHorse", isDirectory: true)
        settingsURL = baseURL.appendingPathComponent("settings.json")
        tasksDirectoryURL = baseURL.appendingPathComponent("tasks", isDirectory: true)

        try? FileManager.default.createDirectory(at: tasksDirectoryURL, withIntermediateDirectories: true)
    }

    func loadSettings() -> WorkSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(WorkSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func saveSettings(_ settings: WorkSettings) {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    func loadDailyLog(for dateKey: String) -> DailyLog {
        let url = dailyLogURL(for: dateKey)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let log = try? decoder.decode(DailyLog.self, from: data) else {
            return .empty(for: dateKey)
        }
        return log
    }

    func saveDailyLog(_ log: DailyLog) {
        try? FileManager.default.createDirectory(at: tasksDirectoryURL, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(log) else { return }
        try? data.write(to: dailyLogURL(for: log.date), options: .atomic)
    }

    func dailyLogURL(for dateKey: String) -> URL {
        tasksDirectoryURL.appendingPathComponent("\(dateKey).json")
    }
}
