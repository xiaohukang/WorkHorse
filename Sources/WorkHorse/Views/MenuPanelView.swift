import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var store: WorkHorseStore
    let actions: WorkHorseActions
    var onContentHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().opacity(0.45)
            statusBlock
            actionGrid
            footer
        }
        .padding(18)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(WorkHorseWindowBackground())
        .background(contentHeightReader)
        .onPreferenceChange(MenuPanelHeightPreferenceKey.self) { height in
            onContentHeightChange?(height)
        }
    }

    private var contentHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: MenuPanelHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AlarmHorseIcon(size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("牛马时光")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.whTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("WorkHorse")
                    .font(.system(size: 12))
                    .foregroundColor(.whMuted)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
            Button(action: actions.showSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconCircleButtonStyle())
            .help("设置")
        }
    }

    private var statusBlock: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            statusBlockContent(at: context.date)
        }
    }

    @ViewBuilder
    private func statusBlockContent(at referenceDate: Date) -> some View {
        if store.activeTasks.isEmpty {
            idleStatusContent(at: referenceDate)
        } else {
            activeTasksContent(at: referenceDate)
        }
    }

    private func activeTasksContent(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.whBlue)
                Spacer()
                Text(WorkHorseFormatters.time.string(from: referenceDate))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.whBlue)
            }

            VStack(spacing: 8) {
                ForEach(store.activeTasks) { task in
                    taskCard(task: task, at: referenceDate)
                }
            }
        }
    }

    private func taskCard(task: WorkTask, at referenceDate: Date) -> some View {
        let seconds = store.duration(for: task, at: referenceDate)
        let overtimeSeconds = store.overtimeSeconds(for: task, at: referenceDate)
        let isRunning = task.status == .running
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIndicator(isRunning: isRunning)
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.whTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isRunning ? "正在计时" : "已暂停")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.whMuted)
                    Text(WorkHorseFormatters.timerString(seconds: seconds))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.whTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                taskControlButtons(task: task)
            }

            if overtimeSeconds > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("加班 \(WorkHorseFormatters.durationString(seconds: overtimeSeconds))")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(Color.orange.opacity(0.30), lineWidth: 1))
                .accessibilityLabel("已加班 \(WorkHorseFormatters.durationString(seconds: overtimeSeconds))")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: isRunning
                    ? [
                        Color.whBlue.opacity(0.14),
                        Color.whSky.opacity(0.10),
                        Color.white.opacity(0.12)
                    ]
                    : [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.18)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isRunning ? Color.whBlue.opacity(0.30) : Color.white.opacity(0.55),
                    lineWidth: 1
                )
        )
    }

    private func statusIndicator(isRunning: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isRunning ? Color.whBlue.opacity(0.18) : Color.whMuted.opacity(0.18))
            Image(systemName: isRunning ? "timer" : "pause.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isRunning ? .whBlue : .whMuted)
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private func taskControlButtons(task: WorkTask) -> some View {
        if task.status == .running {
            HStack(spacing: 6) {
                iconButton(systemName: "pause.fill", help: "暂停") {
                    actions.pauseCurrentTask()
                }
                iconButton(systemName: "checkmark", help: "完成") {
                    actions.completeTaskByID(task.id)
                }
            }
        } else {
            HStack(spacing: 6) {
                iconButton(systemName: "play.fill", help: "继续") {
                    actions.resumeTask(task.id)
                }
                iconButton(systemName: "checkmark", help: "完成") {
                    actions.completeTaskByID(task.id)
                }
            }
        }
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.whBlue)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(Color.whBlue.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func idleStatusContent(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.whBlue)
                Spacer()
                Text(WorkHorseFormatters.time.string(from: referenceDate))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.whBlue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(store.isClockedOutToday ? "今日已下班" : "还没有开始计时")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.whTitle)
                Text(store.isClockedOutToday ? "去看看今天的成果吧" : "开始一项任务后，我会帮你记住时间")
                    .font(.system(size: 13))
                    .foregroundColor(.whMuted)
            }
        }
    }

    private var actionGrid: some View {
        VStack(spacing: 10) {
            Button(action: actions.showTaskPrompt) {
                Label("开始新任务", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!store.canStartNewTask)
            .opacity(store.canStartNewTask ? 1 : 0.5)

            if !store.canStartNewTask, !store.isClockedOutToday {
                Text("最多同时追踪 \(WorkHorseStore.maxTrackedTasks) 个任务")
                    .font(.system(size: 11))
                    .foregroundColor(.whMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: actions.showReport) {
                Label("今日报告", systemImage: "chart.pie")
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundColor(.whBlue)
            Text("数据保存在本地")
                .font(.system(size: 12))
                .foregroundColor(.whMuted)
            Spacer()
            Button("退出", action: actions.quit)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.whMuted)
        }
        .padding(.top, 2)
    }

    private var statusTitle: String {
        switch store.status {
        case .idle: return store.activeTasks.isEmpty ? "待开始" : "待开始新任务"
        case .running: return "正在计时"
        case .waiting: return "等待确认"
        case .clockedOut: return "已下班"
        }
    }

    private var statusSymbol: String {
        switch store.status {
        case .idle: return "clock"
        case .running: return "timer"
        case .waiting: return "bell"
        case .clockedOut: return "checkmark.circle"
        }
    }
}

private struct MenuPanelHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
