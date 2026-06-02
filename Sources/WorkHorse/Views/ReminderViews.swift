import SwiftUI

struct FocusReminderView: View {
    @ObservedObject var store: WorkHorseStore
    let task: WorkTask
    let onComplete: () -> Void
    let onContinue: () -> Void

    private func elapsed(at referenceDate: Date) -> Int {
        store.duration(for: task, at: referenceDate)
    }

    private func progress(at referenceDate: Date) -> Double {
        let interval = max(1, store.settings.focusReminderInterval) * 60
        return min(1, Double(elapsed(at: referenceDate)) / Double(interval))
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            ZStack {
                WorkHorseWindowBackground()
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "alarm")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.whBlue)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                        Text("专注 \(store.settings.focusReminderInterval) 分钟提醒")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.whTitle)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前任务")
                            .font(.system(size: 12))
                            .foregroundColor(.whMuted)
                        Text(task.title)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundColor(.whTitle)
                            .lineLimit(2)
                        Text(WorkHorseFormatters.timerString(seconds: elapsed(at: context.date)))
                            .font(.system(size: 46, weight: .medium, design: .rounded))
                            .foregroundColor(.whTitle)
                            .monospacedDigit()

                        ProgressView(value: progress(at: context.date))
                            .tint(.whBlue)
                    }
                    .padding(16)
                    .liquidCard()

                    HStack(spacing: 12) {
                        Button("完成", action: onComplete)
                            .buttonStyle(SecondaryButtonStyle())
                        Button("老牛还在干活", action: onContinue)
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(24)
            }
            .frame(width: 470, height: 330)
            .liquidPanel()
        }
    }
}

struct OffworkReminderView: View {
    let onClockOut: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            WorkHorseWindowBackground()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk.departure")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.whBlue)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("到点下班啦")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundColor(.whTitle)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("今天已经到下班时间了，是否已经下班？记得打卡。")
                            .font(.system(size: 13))
                            .foregroundColor(.whMuted)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button("还没下班", action: onContinue)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("已下班，去打卡", action: onClockOut)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(24)
        }
        .frame(width: 440, height: 280)
        .liquidPanel()
    }
}
