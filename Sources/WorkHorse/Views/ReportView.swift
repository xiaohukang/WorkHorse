import SwiftUI

struct ReportView: View {
    @ObservedObject var store: WorkHorseStore
    let onClose: () -> Void

    /// 报告弹窗的固定宽度；高度由内容自然撑开，超过屏幕可用区的部分
    /// 由任务明细区自身的 ScrollView 滚动承载，休息记录/图表区按真实高度展示。
    private static let panelWidth: CGFloat = 720
    private static let reportBadgeStampSize: CGFloat = 96
    private static let reportBadgeStampTilt = Angle.degrees(7)

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
                // 关键：只固定宽度，**不写死高度**，让 SwiftUI 按内容算出自然高度。
                // makeWindow 拿到 NSHostingController.view.fittingSize 后会再把窗口
                // 尺寸校正到这个高度，从而实现"窗口高度 = 内容高度"。
                .frame(width: Self.panelWidth, alignment: .top)

                if let toast = store.toast {
                    ToastBadge(message: toast)
                        .padding(.top, 16)
                        .transition(.opacity)
                }
            }
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
                if store.hasEarnedSuperWorkhorseBadge(at: referenceDate) {
                    reportBadgeStamp
                        .padding(.trailing, 10)
                }
            }
        }
    }

    private func overview(at referenceDate: Date) -> some View {
        let overtime = WorkHorseFormatters.durationString(seconds: store.totalOvertimeSeconds(at: referenceDate))
        let restSeconds = store.totalRestSeconds(at: referenceDate)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            reportMetric(title: "总工作时长", value: WorkHorseFormatters.durationString(seconds: store.totalSeconds(at: referenceDate)), icon: "timer")
            if store.totalOvertimeSeconds(at: referenceDate) > 0 {
                reportMetric(title: "加班时长", value: overtime, icon: "moon.zzz.fill", accent: .orange)
            }
            if restSeconds > 0 {
                reportMetric(
                    title: "休息时长",
                    value: WorkHorseFormatters.durationString(seconds: restSeconds),
                    icon: "cup.and.saucer.fill",
                    accent: .whSky
                )
            }
            reportMetric(title: "任务数量", value: "\(store.reportTaskSummaries(at: referenceDate).count)个", icon: "list.bullet")
            reportMetric(title: "开始时间", value: WorkHorseFormatters.clockTime(store.today.clockInTime), icon: "arrow.up.right.circle")
            reportMetric(title: endTimeTitle(at: referenceDate), value: endTimeValue(at: referenceDate), icon: endTimeIcon)
        }
    }

    private var reportBadgeStamp: some View {
        SuperWorkhorseBadgeArtwork()
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.reportBadgeStampSize, height: Self.reportBadgeStampSize)
            .rotationEffect(Self.reportBadgeStampTilt)
            .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.12).opacity(0.35), radius: 12, x: 0, y: 5)
            .accessibilityLabel("超级牛马认证")
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

                if store.reportTaskSummaries(at: referenceDate).isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.reportTaskSummaries(at: referenceDate)) { task in
                                taskRow(task, at: referenceDate)
                            }
                        }
                    }
                    // 任务列表做最大高度限制：单日内任务特别多时让 ScrollView 滚动，
                    // 避免整张报告弹窗被撑得过高（外层 VStack 会按内容自然撑开）。
                    .frame(maxHeight: 320)
                }

                if !store.finishedRestSegments.isEmpty || store.isResting {
                    restSection(at: referenceDate)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .top)
            .liquidCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("专注时长分布")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.whTitle)
                DonutChart(tasks: store.reportTaskSummaries(at: referenceDate))
                    .frame(height: 180)
                legend(at: referenceDate)
            }
            .padding(16)
            .frame(width: 240, alignment: .top)
            .liquidCard()
        }
    }

    /// 报告中的休息段清单：每条记录一次休息的开始时间、计划时长、实际时长。
    /// 把休息从工作明细里抽出来，避免和"专注任务"在视觉上混淆。
    private func restSection(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundColor(.whSky)
                Text("休息记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.whTitle)
                Spacer()
                Text("共 \(store.totalRestSeconds(at: referenceDate) > 0 ? WorkHorseFormatters.durationString(seconds: store.totalRestSeconds(at: referenceDate)) : "—")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.whMuted)
            }

            VStack(spacing: 6) {
                ForEach(restRowsToShow(at: referenceDate)) { row in
                    restRow(row)
                }
            }
        }
        .padding(10)
        .background(Color.whControlFill.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct RestRow: Identifiable {
        let id: String
        let startTime: Date
        let plannedSeconds: Int
        let actualSeconds: Int
        let isOngoing: Bool
    }

    private func restRowsToShow(at referenceDate: Date) -> [RestRow] {
        var rows = store.finishedRestSegments.map { segment in
            RestRow(
                id: segment.id,
                startTime: segment.startTime,
                plannedSeconds: segment.plannedDurationSeconds,
                actualSeconds: segment.actualDurationSeconds(at: referenceDate),
                isOngoing: false
            )
        }
        if let ongoing = store.currentRestSegment {
            rows.append(RestRow(
                id: ongoing.id,
                startTime: ongoing.startTime,
                plannedSeconds: ongoing.plannedDurationSeconds,
                actualSeconds: ongoing.actualDurationSeconds(at: referenceDate),
                isOngoing: true
            ))
        }
        return rows
    }

    private func restRow(_ row: RestRow) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(row.isOngoing ? Color.whSky : Color.whMuted.opacity(0.5))
                .frame(width: 6, height: 6)
            Text("\(WorkHorseFormatters.clockTime(row.startTime))")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.whBody)
                .lineLimit(1)
            Spacer()
            Text(plannedVsActualText(row: row))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(row.isOngoing ? .whSky : .whMuted)
                .lineLimit(1)
            if row.isOngoing {
                Text("进行中")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.whSky)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.whSky.opacity(0.14), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func plannedVsActualText(row: RestRow) -> String {
        let planned = WorkHorseFormatters.durationString(seconds: row.plannedSeconds)
        if row.isOngoing {
            return "\(WorkHorseFormatters.durationString(seconds: row.actualSeconds))/\(planned)"
        }
        return "\(WorkHorseFormatters.durationString(seconds: row.actualSeconds))"
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

    private func reportMetric(title: String, value: String, icon: String, accent: Color = .whBlue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(accent)
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
        .background(Color.whControlFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func taskRow(_ task: TaskTimeSummary, at referenceDate: Date) -> some View {
        let overtimeSeconds = task.overtimeSeconds
        return HStack(spacing: 10) {
            Circle()
                .fill(chartColor(for: task, at: referenceDate))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.whTitle)
                        .lineLimit(1)
                    if task.isOngoing {
                        Text(task.statusDisplayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(task.hasRunningTask ? .whBlue : .whMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (task.hasRunningTask ? Color.whBlue : Color.whMuted).opacity(0.14),
                                in: Capsule()
                            )
                    }
                    if task.taskCount > 1 {
                        Text("合并 \(task.taskCount) 次")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.whBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.whBlue.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    if overtimeSeconds > 0 {
                        Text("加班 \(WorkHorseFormatters.durationString(seconds: overtimeSeconds))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                }
                Text(timeRangeText(for: task))
                    .font(.system(size: 11))
                    .foregroundColor(.whMuted)
            }
            Spacer()
            Text(WorkHorseFormatters.durationString(seconds: task.durationSeconds))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.whBody)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.whControlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func timeRangeText(for task: TaskTimeSummary) -> String {
        let start = WorkHorseFormatters.clockTime(task.firstStartTime)
        if task.isOngoing {
            return "\(start) - 计时中"
        }
        if let end = task.lastEndTime {
            return "\(start) - \(WorkHorseFormatters.clockTime(end))"
        }
        return "\(start) - --:--"
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
            ForEach(Array(store.reportTaskSummaries(at: referenceDate).prefix(5).enumerated()), id: \.element.id) { _, task in
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

    private func chartColor(for task: TaskTimeSummary, at referenceDate: Date) -> Color {
        let colors: [Color] = [.whBlue, .whSky, .green, .orange, .pink, .purple, .teal]
        guard let index = store.reportTaskSummaries(at: referenceDate).firstIndex(where: { $0.id == task.id }) else { return .whBlue }
        return colors[index % colors.count]
    }
}

private struct DonutChart: View {
    let tasks: [TaskTimeSummary]

    private let colors: [Color] = [.whBlue, .whSky, .green, .orange, .pink, .purple, .teal]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.whChartTrack, lineWidth: 28)

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
                Text(WorkHorseFormatters.durationString(seconds: total))
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
        max(0, tasks.reduce(0) { $0 + $1.durationSeconds })
    }

    private func startFraction(for index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let previous = tasks.prefix(index).reduce(0) { $0 + $1.durationSeconds }
        return CGFloat(Double(previous) / Double(total))
    }

    private func endFraction(for index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let through = tasks.prefix(index + 1).reduce(0) { $0 + $1.durationSeconds }
        return CGFloat(Double(through) / Double(total))
    }
}
