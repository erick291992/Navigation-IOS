import SwiftUI

struct MediaPickerButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MediaPickerButtonLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

struct MediaPickerButtonLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                )

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
    }
}
