import SwiftUI

struct ReportView: View {
    @ObservedObject var store: WorkHorseStore
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            WorkHorseWindowBackground()

            VStack(alignment: .leading, spacing: 18) {
                header
                overview
                content
                footer
            }
            .padding(24)

            if let toast = store.toast {
                ToastBadge(message: toast)
                    .padding(.top, 16)
                    .transition(.opacity)
            }
        }
        .frame(width: 720, height: 560)
        .liquidPanel()
    }

    private var header: some View {
        HStack(spacing: 12) {
            LogoMark(size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("今日工作报告")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.whTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(WorkHorseFormatters.displayDayAndWeekday(for: store.now))
                    .font(.system(size: 13))
                    .foregroundColor(.whMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconCircleButtonStyle())
            .help("关闭")
        }
    }

    private var overview: some View {
        HStack(spacing: 12) {
            reportMetric(title: "总工作时长", value: WorkHorseFormatters.durationString(seconds: store.todayTotalSeconds), icon: "timer")
            reportMetric(title: "任务数量", value: "\(store.reportTasks.count)个", icon: "list.bullet")
            reportMetric(title: "开始时间", value: WorkHorseFormatters.clockTime(store.today.clockInTime), icon: "arrow.up.right.circle")
            reportMetric(title: "结束时间", value: WorkHorseFormatters.clockTime(store.today.clockOutTime), icon: "checkmark.circle")
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("任务明细")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.whTitle)

                if store.reportTasks.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.reportTasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .liquidCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("专注时长分布")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.whTitle)
                DonutChart(tasks: store.reportTasks, store: store)
                    .frame(height: 210)
                legend
            }
            .padding(16)
            .frame(width: 240)
            .frame(maxHeight: .infinity, alignment: .top)
            .liquidCard()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label("记录每一个认真工作的你", systemImage: "heart")
                .font(.system(size: 12))
                .foregroundColor(.whMuted)
            Spacer()
            Button {
                store.copyReportMarkdown()
            } label: {
                Label("复制日报", systemImage: "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(width: 132)

            Button {
                store.exportCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 132)
        }
    }

    private func reportMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.whBlue)
                Text(title)
                    .foregroundColor(.whMuted)
            }
            .font(.system(size: 12))
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.whTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func taskRow(_ task: WorkTask) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(chartColor(for: task))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.whTitle)
                    .lineLimit(1)
                Text("\(WorkHorseFormatters.clockTime(task.startTime)) - \(WorkHorseFormatters.clockTime(task.endTime))")
                    .font(.system(size: 11))
                    .foregroundColor(.whMuted)
            }
            Spacer()
            Text(WorkHorseFormatters.durationString(seconds: store.duration(for: task)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.whBody)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.whMuted)
            Text("今天还没有任务记录")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.whMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(store.reportTasks.prefix(5).enumerated()), id: \.element.id) { _, task in
                HStack(spacing: 7) {
                    Circle()
                        .fill(chartColor(for: task))
                        .frame(width: 7, height: 7)
                    Text(task.title)
                        .font(.system(size: 11))
                        .foregroundColor(.whMuted)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private func chartColor(for task: WorkTask) -> Color {
        let colors: [Color] = [.whBlue, .whSky, .green, .orange, .pink, .purple, .teal]
        guard let index = store.reportTasks.firstIndex(where: { $0.id == task.id }) else { return .whBlue }
        return colors[index % colors.count]
    }
}

private struct DonutChart: View {
    let tasks: [WorkTask]
    @ObservedObject var store: WorkHorseStore

    private let colors: [Color] = [.whBlue, .whSky, .green, .orange, .pink, .purple, .teal]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 28)

            if total > 0 {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    Circle()
                        .trim(from: startFraction(for: index), to: endFraction(for: index))
                        .stroke(colors[index % colors.count], style: StrokeStyle(lineWidth: 28, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }

            VStack(spacing: 3) {
                Text("总计")
                    .font(.system(size: 12))
                    .foregroundColor(.whMuted)
                Text(WorkHorseFormatters.durationString(seconds: store.todayTotalSeconds))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.whTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("专注时间")
                    .font(.system(size: 11))
                    .foregroundColor(.whMuted)
            }
        }
        .padding(18)
    }

    private var total: Int {
        max(0, tasks.reduce(0) { $0 + store.duration(for: $1) })
    }

    private func startFraction(for index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let previous = tasks.prefix(index).reduce(0) { $0 + store.duration(for: $1) }
        return CGFloat(Double(previous) / Double(total))
    }

    private func endFraction(for index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let through = tasks.prefix(index + 1).reduce(0) { $0 + store.duration(for: $1) }
        return CGFloat(Double(through) / Double(total))
    }
}
