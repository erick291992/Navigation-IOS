import SwiftUI

struct MediaPickerResultGallery: View {
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Picked Results")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Image(uiImage: item.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 80)
        }
    }
}
