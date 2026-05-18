import SwiftUI

struct MediaPickerNavCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(color)
                        )

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundColor(.gray.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}
