import SwiftUI

struct TaskPromptView: View {
    let mode: TaskPromptMode
    let onStart: (String) -> Void
    let onPostpone: () -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            WorkHorseWindowBackground()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    LogoMark(size: 46)
                    Text(mode.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.whTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer()
                }

                TextField("", text: $title, prompt: Text(mode.placeholder).foregroundColor(.whMuted))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(.whTitle)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onSubmit(start)

                HStack(spacing: 12) {
                    Button("稍后提醒", action: onPostpone)
                        .buttonStyle(SecondaryButtonStyle())
                    Button(mode.buttonTitle, action: start)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
                }
            }
            .padding(24)
        }
        .frame(width: 460, height: 250)
        .liquidPanel()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }

    private func start() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onStart(trimmed)
    }
}
