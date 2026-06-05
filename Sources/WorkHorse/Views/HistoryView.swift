import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: WorkHorseStore
    let onClose: () -> Void

    private static let panelWidth: CGFloat = 760

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let records = store.historyRecords(at: context.date)

            ZStack(alignment: .top) {
                WorkHorseWindowBackground()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    header(recordCount: records.count)
                    overview(records: records)
                    content(records: records)
                }
                .padding(24)
                .frame(width: Self.panelWidth, alignment: .top)
            }
            .liquidPanel()
        }
    }

    private func header(recordCount: Int) -> some View {
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
                    Text("历史工作记录")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.whTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recordCount > 0 ? "共 \(recordCount) 天记录" : "暂无历史记录")
                        .font(.system(size: 13))
                        .foregroundColor(.whMuted)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer()
            }
        }
    }

    private func overview(records: [DailyWorkSummary]) -> some View {
        let totalSeconds = records.reduce(0) { $0 + $1.totalSeconds }
        let overtimeSeconds = records.reduce(0) { $0 + $1.overtimeSeconds }
        let restSeconds = records.reduce(0) { $0 + $1.restSeconds }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

        return LazyVGrid(columns: columns, spacing: 12) {
            historyMetric(title: "累计工作", value: WorkHorseFormatters.durationString(seconds: totalSeconds), icon: "timer")
            historyMetric(title: "记录天数", value: "\(records.count)天", icon: "calendar")
            historyMetric(title: "累计加班", value: WorkHorseFormatters.durationString(seconds: overtimeSeconds), icon: "moon.zzz.fill", accent: .orange)
            historyMetric(title: "累计休息", value: WorkHorseFormatters.durationString(seconds: restSeconds), icon: "cup.and.saucer.fill", accent: .whSky)
        }
    }

    @ViewBuilder
    private func content(records: [DailyWorkSummary]) -> some View {
        if records.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(records) { record in
                        dayCard(record)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 520)
        }
    }

    private func dayCard(_ record: DailyWorkSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayDate(for: record.date))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.whTitle)
                        .lineLimit(1)
                    Text(dayTimeRange(record))
                        .font(.system(size: 12))
                        .foregroundColor(.whMuted)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 10)

                Text("\(record.taskCount) 个任务")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.whBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.whBlue.opacity(0.13), in: Capsule())
            }

            HStack(spacing: 8) {
                compactMetric("工作", seconds: record.totalSeconds, color: .whBlue)
                compactMetric("加班", seconds: record.overtimeSeconds, color: .orange)
                compactMetric("休息", seconds: record.restSeconds, color: .whSky)
            }

            if record.taskSummaries.isEmpty {
                Text("这一天没有任务明细")
                    .font(.system(size: 12))
                    .foregroundColor(.whMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 7) {
                    ForEach(record.taskSummaries) { task in
                        historyTaskRow(task)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.whCardStroke, lineWidth: 1)
        )
    }

    private func historyTaskRow(_ task: TaskTimeSummary) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(task.hasRunningTask ? Color.whBlue : Color.whMuted.opacity(0.45))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.whTitle)
                        .lineLimit(1)

                    if task.taskCount > 1 {
                        Text("合并 \(task.taskCount) 次")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.whBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.whBlue.opacity(0.12), in: Capsule())
                    }

                    if task.isOngoing {
                        Text(task.statusDisplayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(task.hasRunningTask ? .whBlue : .whMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((task.hasRunningTask ? Color.whBlue : Color.whMuted).opacity(0.14), in: Capsule())
                    }
                }

                Text(timeRangeText(for: task))
                    .font(.system(size: 11))
                    .foregroundColor(.whMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text(WorkHorseFormatters.durationString(seconds: task.durationSeconds))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.whBody)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.whControlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func historyMetric(title: String, value: String, icon: String, accent: Color = .whBlue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Text(title)
                    .foregroundColor(.whMuted)
            }
            .font(.system(size: 12))

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.whTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.whControlFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactMetric(_ title: String, seconds: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.whMuted)
            Text(WorkHorseFormatters.durationString(seconds: seconds))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.whControlFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func displayDate(for dateKey: String) -> String {
        guard let date = WorkHorseFormatters.dayKey.date(from: dateKey) else { return dateKey }
        return WorkHorseFormatters.displayDayAndWeekday(for: date)
    }

    private func dayTimeRange(_ record: DailyWorkSummary) -> String {
        let start = WorkHorseFormatters.clockTime(record.clockInTime)
        let end = WorkHorseFormatters.clockTime(record.clockOutTime)
        return "开始 \(start) · 结束 \(end)"
    }

    private func timeRangeText(for task: TaskTimeSummary) -> String {
        let start = WorkHorseFormatters.clockTime(task.firstStartTime)
        if task.isOngoing {
            return "\(start) - 计时中"
        }
        if let endTime = task.lastEndTime {
            return "\(start) - \(WorkHorseFormatters.clockTime(endTime))"
        }
        return "\(start) - --:--"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30))
                .foregroundColor(.whMuted)
            Text("还没有可查看的历史记录")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.whMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.whCardStroke, lineWidth: 1)
        )
    }
}
