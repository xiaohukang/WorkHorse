import SwiftUI

struct WorkHorseActions {
    var showSettings: () -> Void
    var showTaskPrompt: () -> Void
    var completeTask: () -> Void
    var showReport: () -> Void
    var quit: () -> Void
}

enum TaskPromptMode {
    case start
    case next

    var title: String {
        switch self {
        case .start: return "你现在在干什么？"
        case .next: return "下一个工作是什么？"
        }
    }

    var placeholder: String {
        switch self {
        case .start: return "输入任务内容，例如：撰写产品方案"
        case .next: return "输入下一个任务，例如：参加产品评审会"
        }
    }

    var buttonTitle: String { "开始计时" }
}

extension Color {
    static let whBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let whSky = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let whTitle = Color(red: 0.04, green: 0.07, blue: 0.13)
    static let whBody = Color(red: 0.20, green: 0.25, blue: 0.33)
    static let whMuted = Color(red: 0.39, green: 0.45, blue: 0.55)
    static let whLine = Color.white.opacity(0.45)
}

extension View {
    func liquidPanel(cornerRadius: CGFloat = 28) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.82), .white.opacity(0.26)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.14), radius: 32, x: 0, y: 20)
    }

    func liquidCard(cornerRadius: CGFloat = 20) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.50), lineWidth: 1)
            )
    }
}

struct WorkHorseWindowBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.98, blue: 1.0),
                    Color(red: 0.86, green: 0.93, blue: 1.0),
                    Color.white.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.whSky.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            RadialGradient(
                colors: [Color.whBlue.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

struct LogoMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.78), Color.whBlue.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )

            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.whBlue.opacity(0.45), radius: 8, y: 4)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.whBlue.opacity(0.35), radius: 14, x: 0, y: 8)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.whBlue, Color(red: 0.02, green: 0.38, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.whBlue.opacity(configuration.isPressed ? 0.12 : 0.30), radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.whTitle)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct IconCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.whMuted)
            .frame(width: 30, height: 30)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.50), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct ToastBadge: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.whTitle)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.56), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
    }
}
