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
    let onRest: () -> Void

    private func elapsed(at referenceDate: Date) -> Int {
        store.duration(for: task, at: referenceDate)
    }

    private func progress(at referenceDate: Date) -> Double {
        let interval = max(1, store.settings.focusReminderInterval) * 60
        return min(1, Double(elapsed(at: referenceDate)) / Double(interval))
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                header
                reminderCard(at: context.date)
                actions
            }
            .padding(18)
            .frame(width: 340, height: 320)
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
        .background(Color.whControlFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.whBlue.opacity(0.26), lineWidth: 1)
        )
    }

    private var actions: some View {
        VStack(spacing: 8) {
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

            Button {
                onRest()
            } label: {
                Label("休息 5 分钟", systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(RestLinkButtonStyle())
        }
    }
}

/// 用于提醒弹窗里"休息 N 分钟"次级操作的链接式按钮：透明背景 + 蓝色文字，
/// 视觉权重低于主操作按钮，但比纯文字更易点。
private struct RestLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.whBlue)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(
                Color.whControlFill.opacity(configuration.isPressed ? 0.4 : 0.25),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.whBlue.opacity(0.20), lineWidth: 1)
            )
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

/// 「牛马需要休息」时间选择弹窗。展示一组预置按钮（2/5/10/15/20 分钟）+ 自定义滑杆。
/// 范围硬编码为 2~20 分钟；具体校验由调用方（AppDelegate.handleStartRest）兜底。
struct RestPickerView: View {
    /// 预置分钟数按钮。覆盖 2~20 的常用档位，剩下的用户用滑杆微调。
    private static let presetMinutes: [Int] = [2, 5, 10, 15, 20]

    let onPick: (Int) -> Void
    let onCancel: () -> Void

    @State private var customMinutes: Double = 5
    @State private var selectedPreset: Int? = 5

    private let minMinutes: Int = 2
    private let maxMinutes: Int = 20

    private var effectiveMinutes: Int {
        if let preset = selectedPreset { return preset }
        return Int(customMinutes.rounded())
    }

    var body: some View {
        ZStack {
            WorkHorseWindowBackground()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                header
                presetSection
                sliderSection
                actionRow
            }
            .padding(28)
            // 仅约束宽度，高度交给 SwiftUI 内部按内容自然撑开。
            // AppDelegate 的 makeWindow 会用 NSHostingController 测出 fittingSize 二次校正窗口尺寸。
            .frame(width: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
        .liquidPanel()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowControls(
                onClose: onCancel,
                onMinimize: { NSApp.keyWindow?.miniaturize(nil) },
                onZoom: { NSApp.keyWindow?.zoom(nil) }
            )

            HStack(alignment: .center, spacing: 14) {
                AlarmHorseIcon(size: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text("牛马需要休息")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.whTitle)
                        .lineLimit(1)
                    Text("选好时间就去放空一会儿，时间到会自动恢复。")
                        .font(.system(size: 13))
                        .foregroundColor(.whMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("快速选择")
            HStack(spacing: 8) {
                ForEach(Self.presetMinutes, id: \.self) { minute in
                    Button {
                        selectedPreset = minute
                        customMinutes = Double(minute)
                    } label: {
                        Text("\(minute) 分钟")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RestPresetButtonStyle(isSelected: selectedPreset == minute))
                }
            }
        }
    }

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("自定义")
                Spacer()
                Text("\(effectiveMinutes) 分钟")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.whBlue)
                    .monospacedDigit()
            }
            Slider(
                value: $customMinutes,
                in: Double(minMinutes)...Double(maxMinutes),
                step: 1
            ) {
                Text("休息分钟数")
            } onEditingChanged: { editing in
                if editing {
                    // 用户开始拖动滑杆时清空预选，UI 状态完全跟随滑杆。
                    selectedPreset = nil
                }
            }
            .tint(.whBlue)
            .accessibilityValue("\(effectiveMinutes) 分钟")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("取消", action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
            Button {
                onPick(effectiveMinutes)
            } label: {
                Label("休息 \(effectiveMinutes) 分钟", systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.whMuted)
    }
}

private struct RestPresetButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isSelected ? .white : .whTitle)
            .frame(height: 40)
            .background(
                isSelected
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.whBlue, Color.whBlueDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.whBlue.opacity(0.4) : Color.whCardStroke,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
