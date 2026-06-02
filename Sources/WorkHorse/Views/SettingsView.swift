import SwiftUI

struct SettingsView: View {
    private let initialSettings: WorkSettings
    let isOnboarding: Bool
    let onSave: (WorkSettings) -> Void
    let onCancel: () -> Void

    @State private var selectedDays: Set<Int>
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var enableFocusReminder: Bool
    @State private var focusReminderInterval: Double
    @State private var enableOffworkReminder: Bool
    @State private var offworkReminderInterval: Double
    @State private var enableLaunchAtLogin: Bool

    init(
        settings: WorkSettings,
        isOnboarding: Bool,
        onSave: @escaping (WorkSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        initialSettings = settings
        self.isOnboarding = isOnboarding
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedDays = State(initialValue: Set(settings.workDays))
        _startTime = State(initialValue: Self.date(from: settings.workStartTime))
        _endTime = State(initialValue: Self.date(from: settings.workEndTime))
        _enableFocusReminder = State(initialValue: settings.enableFocusReminder)
        _focusReminderInterval = State(initialValue: Double(settings.focusReminderInterval))
        _enableOffworkReminder = State(initialValue: settings.enableOffworkReminder)
        _offworkReminderInterval = State(initialValue: Double(settings.offworkReminderInterval))
        _enableLaunchAtLogin = State(initialValue: settings.enableLaunchAtLogin)
    }

    var body: some View {
        ZStack {
            WorkHorseWindowBackground()
            VStack(alignment: .leading, spacing: 22) {
                header
                workdaySection
                workTimeSection
                reminderSection
                launchSection
                Spacer(minLength: 0)
                actions
            }
            .padding(28)
        }
        .frame(width: 560, height: 620)
        .liquidPanel()
    }

    private var header: some View {
        HStack(spacing: 14) {
            LogoMark(size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(isOnboarding ? "欢迎使用牛马时光" : "工作设置")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.whTitle)
                Text(isOnboarding ? "先设置你的工作节奏" : "调整提醒、时间和工作日")
                    .font(.system(size: 13))
                    .foregroundColor(.whMuted)
            }
            Spacer()
        }
    }

    private var workdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("工作日")
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { weekday in
                    let isSelected = selectedDays.contains(weekday.rawValue)
                    Button {
                        if isSelected {
                            selectedDays.remove(weekday.rawValue)
                        } else {
                            selectedDays.insert(weekday.rawValue)
                        }
                    } label: {
                        Text(weekday.shortName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .whBody)
                            .frame(width: 56, height: 40)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(LinearGradient(colors: [.whBlue, .whSky], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.32))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .liquidCard()
    }

    private var workTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("工作时间")
            HStack(spacing: 12) {
                DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.whMuted)

                DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .liquidCard()
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("提醒")
            ToggleRow(
                title: "专注提醒",
                subtitle: "\(Int(focusReminderInterval)) 分钟",
                isOn: $enableFocusReminder
            )
            Slider(value: $focusReminderInterval, in: 5...60, step: 5)
                .tint(.whBlue)
                .disabled(!enableFocusReminder)
                .opacity(enableFocusReminder ? 1 : 0.4)

            ToggleRow(
                title: "下班提醒",
                subtitle: "\(Int(offworkReminderInterval)) 分钟后重复",
                isOn: $enableOffworkReminder
            )
            Slider(value: $offworkReminderInterval, in: 5...60, step: 5)
                .tint(.whBlue)
                .disabled(!enableOffworkReminder)
                .opacity(enableOffworkReminder ? 1 : 0.4)
        }
        .padding(16)
        .liquidCard()
    }

    private var launchSection: some View {
        ToggleRow(title: "开机启动", subtitle: "登录 macOS 后自动运行", isOn: $enableLaunchAtLogin)
            .padding(16)
            .liquidCard()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if !isOnboarding {
                Button("取消", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button(isOnboarding ? "开始使用" : "保存设置") {
                onSave(makeSettings())
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.whTitle)
    }

    private func makeSettings() -> WorkSettings {
        var settings = initialSettings
        settings.workDays = selectedDays.isEmpty ? WorkSettings.default.workDays : selectedDays.sorted()
        settings.workStartTime = WorkHorseFormatters.time.string(from: startTime)
        settings.workEndTime = WorkHorseFormatters.time.string(from: endTime)
        settings.enableFocusReminder = enableFocusReminder
        settings.focusReminderInterval = Int(focusReminderInterval)
        settings.enableOffworkReminder = enableOffworkReminder
        settings.offworkReminderInterval = Int(offworkReminderInterval)
        settings.enableLaunchAtLogin = enableLaunchAtLogin
        return settings
    }

    private static func date(from timeString: String) -> Date {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts.first ?? 9
        components.minute = parts.dropFirst().first ?? 0
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.whTitle)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.whMuted)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
