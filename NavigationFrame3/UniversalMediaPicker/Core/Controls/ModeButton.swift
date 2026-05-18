import SwiftUI

struct ModeButton: View {
    let title: String
    let isSelected: Bool
    var accentColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                    .tracking(1.2)

                Circle()
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
    }
}
