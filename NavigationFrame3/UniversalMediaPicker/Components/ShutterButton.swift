import SwiftUI

/// The center capture/submit button.
///
/// `mode == .capture` renders a plain white filled circle inside a white
/// stroke (photo mode); `mode == .submit` renders a white-on-white checkmark
/// (library/reuse mode). Parent decides which based on the active `PickerMode`.
struct ShutterButton: View {
    enum Mode {
        case capture
        case submit
    }

    let mode: Mode
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                switch mode {
                case .submit:
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 60, height: 60)
                        .background(Color.white)
                        .clipShape(Circle())
                case .capture:
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
