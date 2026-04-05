import SwiftUI
import PhotosUI

/// Lightweight wrapper around native PhotosPicker to fit our custom flow.
struct PhotosPickerView: View {
    @Binding var selection: [PhotosPickerItem]
    let limit: Int
    let filter: [PHPickerFilter]
    let style: MediaPickerStyle
    
    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: limit,
            matching: filter.isEmpty ? .images : PHPickerFilter.any(of: filter)
        ) {
            HStack(spacing: 16) {
                // Icon in a circle
                ZStack {
                    Circle()
                        .fill(style.accentColor.opacity(0.1))
                        .frame(width: 54, height: 54)
                    
                    style.galleryIcon
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(style.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.galleryLabel)
                        .font(style.font.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Text(style.gallerySubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
    }
}
