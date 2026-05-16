import SwiftUI

/// First-launch prompt shown in the viewfinder area when authorization is
/// `.notDetermined`. Dumb view — parent passes the title (from the picker
/// style), the accent color, and an `onGetStarted` callback that should
/// trigger the permission-request flow.
struct OnboardingPromptView: View {
    let title: String
    let accentColor: Color
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(accentColor)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title.bold())
                Text("To start creating elite content, we need access to your library and camera.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onGetStarted()
            }) {
                Text("GET STARTED")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(accentColor)
                    .cornerRadius(30)
            }
        }
        .foregroundColor(.white)
    }
}
