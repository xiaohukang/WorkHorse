import SwiftUI

struct ReportView: View {
    @ObservedObject var store: WorkHorseStore
    let onClose: () -> Void

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            ZStack(alignment: .top) {
                WorkHorseWindowBackground()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    header(at: context.date)
                    overview(at: context.date)
                    content(at: context.date)
                    footer
                }
                .padding(24)

                if let toast = store.toast {
                    ToastBadge(message: toast)
                        .padding(.top, 16)
                        .transition(.opacity)
                }
            }
            .frame(width: 720, height: 660)
            .liquidPanel()
        }
    }

    private func header(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WindowControls(
                    onClose: onClose,
                    onMinimize: { NSApp.keyWindow?.miniaturize(nil) },
                    onZoom: { NSApp.keyWindow?.zoom(nil) }
                )
                Spacer()
            }

            HStack(spacing: 12) {
                AlarmHorseIcon(size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日工作报告")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.whTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(WorkHorseFormatters.displayDayAndWeekday(for: referenceDate))
                        .font(.system(size: 13))
                        .foregroundColor(.whMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer()
            }
        }
    }

    private func overview(at referenceDate: Date) -> some View {
        HStack(spacing: 12) {
            reportMetric(title: "总工作时长", value: WorkHorseFormatters.durationString(seconds: store.totalSeconds(at: referenceDate)), icon: "timer")
            reportMetric(title: "任务数量", value: "\(store.reportTasks(at: referenceDate).count)个", icon: "list.bullet")
            reportMetric(title: "开始时间", value: WorkHorseFormatters.clockTime(store.today.clockInTime), icon: "arrow.up.right.circle")
            reportMetric(title: endTimeTitle(at: referenceDate), value: endTimeValue(at: referenceDate), icon: endTimeIcon)
        }
    }

    private func endTimeTitle(at referenceDate: Date) -> String {
        store.isClockedOutToday ? "结束时间" : "距离下班"
    }

    private func endTimeValue(at referenceDate: Date) -> String {
        if store.isClockedOutToday {
            return WorkHorseFormatters.clockTime(store.today.clockOutTime)
        }
        let offworkDate = store.settings.date(on: referenceDate, from: store.settings.workEndTime)
        let remaining = Int(offworkDate.timeIntervalSince(referenceDate))
        if remaining <= 0 {
            return "已到下班"
        }
        return WorkHorseFormatters.timerString(seconds: remaining)
    }

    private var endTimeIcon: String {
        store.isClockedOutToday ? "checkmark.circle" : "hourglass"
    }

    private func content(at referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("任务明细")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.whTitle)

                if store.reportTasks(at: referenceDate).isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.reportTasks(at: referenceDate)) { task in
                                taskRow(task, at: referenceDate)
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
                DonutChart(tasks: store.reportTasks(at: referenceDate), store: store, referenceDate: referenceDate)
                    .frame(height: 210)
                legend(at: referenceDate)
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

    private func taskRow(_ task: WorkTask, at referenceDate: Date) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(chartColor(for: task, at: referenceDate))
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
            Text(WorkHorseFormatters.durationString(seconds: store.duration(for: task, at: referenceDate)))
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

    private func legend(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(store.reportTasks(at: referenceDate).prefix(5).enumerated()), id: \.element.id) { _, task in
                HStack(spacing: 7) {
                    Circle()
                        .fill(chartColor(for: task, at: referenceDate))
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

    private func chartColor(for task: WorkTask, at referenceDate: Date) -> Color {
        let colors: [Color] = [.whBlue, .whSky, .green, .orange, .pink, .purple, .teal]
        guard let index = store.reportTasks(at: referenceDate).firstIndex(where: { $0.id == task.id }) else { return .whBlue }
        return colors[index % colors.count]
    }
}

private struct DonutChart: View {
    let tasks: [WorkTask]
    @ObservedObject var store: WorkHorseStore
    let referenceDate: Date

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
                Text(WorkHorseFormatters.durationString(seconds: store.totalSeconds(at: referenceDate)))
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
        max(0, tasks.reduce(0) { $0 + store.duration(for: $1, at: referenceDate) })
    }

    private func startFraction(for index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let previous = tasks.prefix(index).reduce(0) { $0 + store.duration(for: $1, at: referenceDate) }
        return CGFloat(Double(previous) / Double(total))
    }

    private func endFraction(for index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let through = tasks.prefix(index + 1).reduce(0) { $0 + store.duration(for: $1, at: referenceDate) }
        return CGFloat(Double(through) / Double(total))
    }
}
