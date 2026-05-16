import SwiftUI

/// Floating X button anchored at the top-left of the picker, above all other
/// content (callers pin via `.zIndex` at the parent). Dumb view — fires
/// `onTap` callback when pressed, parent decides what dismissal means.
struct ExitButton: View {
    let onTap: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTap()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.5), radius: 10)
                }
                .padding(20)
                .contentShape(Rectangle())

                Spacer()
            }
            .padding(.top, 44) // Align with modern iPhone status bars
            Spacer()
        }
    }
}
