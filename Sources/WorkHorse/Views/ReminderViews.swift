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
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    WindowControls(
                        onClose: { closeCurrentWindow() },
                        onMinimize: { NSApp.keyWindow?.miniaturize(nil) },
                        onZoom: { NSApp.keyWindow?.zoom(nil) }
                    )
                    HStack(spacing: 12) {
                        AlarmHorseIcon(size: 46)
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
            .frame(width: 470, height: 360)
            .liquidPanel()
        }
    }
}

struct FocusReminderBubbleView: View {
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
            VStack(alignment: .leading, spacing: 16) {
                header
                reminderCard(at: context.date)
                actions
            }
            .padding(18)
            .frame(width: 340, height: 280)
            .background(WorkHorseWindowBackground())
            .liquidPanel(cornerRadius: 28)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AlarmHorseIcon(size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("专注提醒")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.whTitle)
                    .lineLimit(1)
                Text("\(store.settings.focusReminderInterval) 分钟到了")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.whMuted)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
        }
    }

    private func reminderCard(at referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.whTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.whBlue.opacity(0.14))
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.whBlue)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("已工作")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.whMuted)
                    Text(WorkHorseFormatters.timerString(seconds: elapsed(at: referenceDate)))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.whTitle)
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }

            ProgressView(value: progress(at: referenceDate))
                .tint(.whBlue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.whBlue.opacity(0.26), lineWidth: 1)
        )
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                onComplete()
            } label: {
                Label("完成当前", systemImage: "checkmark.circle")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                onContinue()
            } label: {
                Label("继续", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

struct OffworkReminderView: View {
    let onClockOut: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            WorkHorseWindowBackground()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                WindowControls(
                    onClose: { closeCurrentWindow() },
                    onMinimize: { NSApp.keyWindow?.miniaturize(nil) },
                    onZoom: { NSApp.keyWindow?.zoom(nil) }
                )
                HStack(spacing: 12) {
                    AlarmHorseIcon(size: 48)
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
        .frame(width: 440, height: 300)
        .liquidPanel()
    }
}
