import AppKit
import SwiftUI

struct SuperWorkhorseBadgeArtwork: View {
    private static let image: NSImage? = {
        let subdirectory = "Assets.xcassets/super-workhorse-badge.imageset"
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "badge@3x", withExtension: "png", subdirectory: subdirectory),
            Bundle.module.url(forResource: "badge@2x", withExtension: "png", subdirectory: subdirectory),
            Bundle.module.url(forResource: "badge", withExtension: "png", subdirectory: subdirectory),
            Bundle.main.url(forResource: "badge@3x", withExtension: "png", subdirectory: subdirectory),
            Bundle.main.url(forResource: "badge@2x", withExtension: "png", subdirectory: subdirectory),
            Bundle.main.url(forResource: "badge", withExtension: "png", subdirectory: subdirectory),
            URL(fileURLWithPath: "/Users/hukang/Documents/Work Horse/Sources/WorkHorse/Resources/\(subdirectory)/badge@3x.png"),
            URL(fileURLWithPath: "/Users/hukang/Documents/Work Horse/Sources/WorkHorse/Resources/\(subdirectory)/badge@2x.png"),
            URL(fileURLWithPath: "/Users/hukang/Documents/Work Horse/Sources/WorkHorse/Resources/\(subdirectory)/badge.png")
        ]

        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "seal.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.whBlue)
        }
    }
}

struct SuperWorkhorseBadgeView: View {
    var size: CGFloat = 110
    var isEarned: Bool
    var isAnimated: Bool = false

    @State private var pulse = false

    var body: some View {
        ZStack {
            outerGlow
            badgeImage
            if !isEarned {
                lockedOverlay
            }
        }
        // 关键：用 .compositingGroup + 明确 frame 锁死外层 ZStack 的尺寸，
        // 避免 inner 的 outerGlow(内部 1.28×size 的 Circle)把建议尺寸泄漏给父布局，
        // 导致父布局 HStack 每秒 layout 时左右两列宽度反复协商、出现"宽度抖动"。
        .frame(width: size, height: size)
        .compositingGroup()
        .saturation(isEarned ? 1 : 0.18)
        .opacity(isEarned ? 1 : 0.72)
        .scaleEffect(isAnimated && pulse ? 1.045 : 1)
        .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.12).opacity(isEarned ? 0.42 : 0.10), radius: size * 0.12, x: 0, y: size * 0.08)
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var outerGlow: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.72, blue: 0.20).opacity(isEarned ? 0.34 : 0.10),
                            Color.whSky.opacity(isEarned ? 0.22 : 0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.12,
                        endRadius: size * 0.66
                    )
                )
                .frame(width: size * 1.28, height: size * 1.28)

            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(index % 2 == 0 ? Color(red: 1.0, green: 0.75, blue: 0.22) : Color.whSky)
                    .frame(width: size * 0.018, height: size * 0.16)
                    .offset(y: -size * 0.61)
                    .rotationEffect(.degrees(Double(index) * 30))
                    .opacity(isEarned ? 0.66 : 0.18)
            }
        }
        // 把 outerGlow 自身锁死为 size×size，内部 1.28×size 的渐变圆和 0.61 偏移的 Capsule
        // 只是"超出后被裁掉"，不再向 SwiftUI 报告"我比 size 更大"。
        // 这是修复"今日工作报告页面宽度抖动"的关键。
        .frame(width: size, height: size)
        .clipped()
    }

    private var badgeImage: some View {
        SuperWorkhorseBadgeArtwork()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var lockedOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.22))
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
                .shadow(radius: 4)
        }
        .padding(size * 0.18)
    }
}

struct SuperWorkhorseBadgeCelebrationView: View {
    let totalSeconds: Int
    let onDismiss: () -> Void

    @State private var show = false
    @State private var raySpin = false
    @State private var badgePulse = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                celebrationBackground
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                rays(in: proxy.size)
                    .allowsHitTesting(false)
                centeredBadgeStage(in: proxy.size)
                    .allowsHitTesting(false)
                celebrationControls(in: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.66)) {
                show = true
            }
            withAnimation(.linear(duration: 11).repeatForever(autoreverses: false)) {
                raySpin = true
            }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                badgePulse = true
            }
        }
    }

    private var celebrationBackground: some View {
        ZStack {
            WorkHorseWindowBackground()
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.26)
            RadialGradient(
                colors: [
                    Color.white.opacity(0.62),
                    Color.whSky.opacity(0.24),
                    .clear
                ],
                center: .center,
                startRadius: 80,
                endRadius: 560
            )
            RadialGradient(
                colors: [Color.whBlue.opacity(0.16), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private func rays(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<28, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.whBlue.opacity(index % 2 == 0 ? 0.14 : 0.07),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: max(size.width, size.height) * 0.82)
                    .offset(y: -max(size.width, size.height) * 0.34)
                    .rotationEffect(.degrees(Double(index) * (360.0 / 28.0) + (raySpin ? 360 : 0)))
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(show ? 1 : 0)
    }

    private func centeredBadgeStage(in size: CGSize) -> some View {
        let badgeSize = celebrationBadgeSize(in: size)

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.24), lineWidth: 2)
                .frame(width: badgeSize * 1.28, height: badgeSize * 1.28)
                .scaleEffect(show ? 1.16 : 0.72)
                .opacity(show ? 0 : 1)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: show)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.28).opacity(0.72),
                            Color.whSky.opacity(0.18),
                            Color.white.opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: badgeSize * 1.10, height: badgeSize * 1.10)
                .rotationEffect(.degrees(raySpin ? 360 : 0))

            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.78, blue: 0.30).opacity(0.62),
                    Color(red: 1.0, green: 0.44, blue: 0.18).opacity(0.18),
                    Color.whSky.opacity(0.10),
                    .clear
                ],
                center: .center,
                startRadius: badgeSize * 0.14,
                endRadius: badgeSize * 0.78
            )
            .frame(width: badgeSize * 1.65, height: badgeSize * 1.65)

            SuperWorkhorseBadgeArtwork()
                .aspectRatio(contentMode: .fit)
                .frame(width: badgeSize, height: badgeSize)
                .scaleEffect(show ? (badgePulse ? 1.06 : 1) : 0.46)
                .shadow(color: Color(red: 1.0, green: 0.68, blue: 0.20).opacity(0.62), radius: badgeSize * 0.09, y: badgeSize * 0.03)
                .shadow(color: Color.whSky.opacity(0.36), radius: badgeSize * 0.12)
        }
        .frame(width: badgeSize * 1.72, height: badgeSize * 1.72)
        .opacity(show ? 1 : 0)
        .position(x: size.width / 2, y: size.height / 2)
    }

    private func celebrationControls(in size: CGSize) -> some View {
        let badgeSize = celebrationBadgeSize(in: size)
        let contentWidth = max(280, min(620, size.width - 48))

        return VStack(spacing: 16) {
            celebrationTextBlock
            celebrationDismissButton
        }
        .frame(width: contentWidth)
        .scaleEffect(show ? 1 : 0.86)
        .opacity(show ? 1 : 0)
        .position(
            x: size.width / 2,
            y: min(size.height - 88, size.height / 2 + badgeSize * 0.62 + 104)
        )
    }

    private func celebrationBadgeSize(in size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.34, 230), 340)
    }

    private var celebrationTextBlock: some View {
        VStack(spacing: 8) {
            Text("超级牛马认证")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(.whTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .shadow(color: Color.whBlue.opacity(0.22), radius: 14, y: 7)
            Text("今日累计工作 \(WorkHorseFormatters.durationString(seconds: totalSeconds))，10 小时徽章已点亮")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.whMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }

    private var celebrationDismissButton: some View {
        Button(action: onDismiss) {
            Label("收下徽章", systemImage: "sparkles")
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(width: 160)
        .help("关闭庆祝动画")
    }
}
