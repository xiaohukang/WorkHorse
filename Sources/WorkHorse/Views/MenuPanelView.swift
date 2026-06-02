import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var store: WorkHorseStore
    let actions: WorkHorseActions

    var body: some View {
        ZStack(alignment: .top) {
            WorkHorseWindowBackground()

            VStack(alignment: .leading, spacing: 16) {
                header
                Divider().opacity(0.45)
                statusBlock
                actionGrid
                footer
            }
            .padding(18)
        }
        .frame(width: 340, height: 430)
    }

    private var header: some View {
        HStack(spacing: 12) {
            LogoMark(size: 48)
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

    private func statusBlockContent(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.whMuted)
                Spacer()
                Text(WorkHorseFormatters.time.string(from: referenceDate))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.whMuted)
            }

            if let task = store.currentTask {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.whTitle)
                        .lineLimit(2)
                    Text("已工作 \(WorkHorseFormatters.timerString(seconds: store.duration(for: task, at: referenceDate)))")
                        .font(.system(size: 13))
                        .foregroundColor(.whMuted)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.isClockedOutToday ? "今日已下班" : "还没有开始计时")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.whTitle)
                    Text(store.isClockedOutToday ? "去看看今天的成果吧" : "开始一项任务后，我会帮你记住时间")
                        .font(.system(size: 13))
                        .foregroundColor(.whMuted)
                }
            }

            HStack(spacing: 10) {
                metric(title: "今日总计", value: WorkHorseFormatters.durationString(seconds: store.totalSeconds(at: referenceDate)))
                metric(title: "任务数量", value: "\(store.reportTasks(at: referenceDate).count)个")
            }
        }
        .padding(14)
        .liquidCard()
    }

    private var actionGrid: some View {
        VStack(spacing: 10) {
            Button(action: actions.showTaskPrompt) {
                Label("开始新任务", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 10) {
                Button(action: actions.completeTask) {
                    Label("完成当前", systemImage: "checkmark.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.currentTask == nil)
                .opacity(store.currentTask == nil ? 0.45 : 1)

                Button(action: actions.showReport) {
                    Label("今日报告", systemImage: "chart.pie")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
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

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.whMuted)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusTitle: String {
        switch store.status {
        case .idle: return "待开始"
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
