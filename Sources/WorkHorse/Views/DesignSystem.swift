import AppKit
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
    func closeCurrentWindow() {
        NSApp.keyWindow?.performClose(nil)
        // NSPanel 在 nonactivatingPanel 状态下可能不是 keyWindow，回退到当前可见的 frontmost 面板。
        if NSApp.keyWindow == nil, let panel = frontmostWorkHorsePanel() {
            panel.performClose(nil)
        }
    }
}

/// 找到当前最前面、可见的 NSPanel（用于在 NSPanel 不是 keyWindow 时回退操作）。
func frontmostWorkHorsePanel() -> NSWindow? {
    NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })
}

extension View {
    func liquidPanel(cornerRadius: CGFloat = 32) -> some View {
        // 用圆角矩形同时作为背景容器、描边容器、裁剪遮罩，
        // 这样内部的渐变背景、material、shadow 都不会溢出圆角。
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
        AlarmHorseIcon(size: size, isActive: false)
    }
}

struct AlarmHorseIcon: View {
    var size: CGFloat = 46
    var isActive: Bool = true

    var body: some View {
        iconBody
            // symbolEffect 在 macOS 14+ 才可用，macOS 15+ 才有 .repeat。
            // 低版本上静默跳过这个修饰符，保证 App 能在 13+ 系统启动。
            .modifier(SymbolEffectIfAvailable(isActive: isActive))
    }

    private var iconBody: some View {
        Image(nsImage: BrandImageProvider.popupIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: Color.whBlue.opacity(0.30), radius: 12, x: 0, y: 6)
    }
}

private enum BrandImageProvider {
    static let popupIcon: NSImage = {
        let candidateURLs = [
            Bundle.main.url(forResource: "popup-brand-icon", withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("popup-brand-icon.png"),
            Bundle.module.url(forResource: "popup-brand-icon", withExtension: "png"),
            URL(fileURLWithPath: "/Users/hukang/Documents/Work Horse/Sources/WorkHorse/Resources/popup-brand-icon.png")
        ].compactMap { $0 }

        for url in candidateURLs {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return NSImage()
    }()
}

/// 把 macOS 14+ 的 .symbolEffect 调用包到 ViewModifier 里，配合 #available
/// 实现低版本系统下编译通过、运行时静默跳过。
private struct SymbolEffectIfAvailable: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.symbolEffect(.bounce, options: .repeat(.continuous), value: isActive)
        } else if #available(macOS 14.0, *) {
            content.symbolEffect(.bounce, value: isActive)
        } else {
            content
        }
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

struct WindowControlButton: View {
    enum Kind { case close, minimize, zoom }
    let kind: Kind
    let action: () -> Void
    @State private var isHovering = false

    private var color: Color {
        switch kind {
        case .close: return Color(red: 1.0, green: 0.37, blue: 0.36)
        case .minimize: return Color(red: 1.0, green: 0.78, blue: 0.20)
        case .zoom: return Color(red: 0.20, green: 0.78, blue: 0.36)
        }
    }

    private var systemImage: String {
        switch kind {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .zoom: return "plus"
        }
    }

    var body: some View {
        Button {
            performAction()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isHovering ? Color.black.opacity(0.75) : Color.clear)
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
    }

    /// 先执行 action 闭包（业务自定义：保存设置、清理状态等），
    /// 再通过系统 selector 操作当前窗口（关闭/最小化/缩放）。
    /// 目标窗口的查找规则：
    ///   1. NSApp.keyWindow（通常就是当前弹窗）
    ///   2. 否则从 NSApp.windows 中找到第一个可见的 NSPanel（处理 nonactivatingPanel 场景）
    /// 找不到目标时仅执行 action，避免空操作。
    private func performAction() {
        action()
        let selector: Selector
        switch kind {
        case .close:    selector = #selector(NSWindow.performClose(_:))
        case .minimize: selector = #selector(NSWindow.performMiniaturize(_:))
        case .zoom:     selector = #selector(NSWindow.performZoom(_:))
        }
        let target = NSApp.keyWindow ?? frontmostWorkHorsePanel()
        guard let target, target.responds(to: selector) else { return }
        _ = target.perform(selector, with: nil)
    }

    private var helpText: String {
        switch kind {
        case .close: return "关闭"
        case .minimize: return "最小化"
        case .zoom: return "缩放"
        }
    }
}

struct WindowControls: View {
    let onClose: () -> Void
    let onMinimize: (() -> Void)?
    let onZoom: (() -> Void)?

    init(onClose: @escaping () -> Void, onMinimize: (() -> Void)? = nil, onZoom: (() -> Void)? = nil) {
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }

    var body: some View {
        HStack(spacing: 8) {
            WindowControlButton(kind: .close, action: onClose)
            if let onMinimize {
                WindowControlButton(kind: .minimize, action: onMinimize)
            }
            if let onZoom {
                WindowControlButton(kind: .zoom, action: onZoom)
            }
        }
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
