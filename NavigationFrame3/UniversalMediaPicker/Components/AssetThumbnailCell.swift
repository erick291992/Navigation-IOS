import SwiftUI
import Photos

struct AssetThumbnailCell: View {
    let asset: PHAsset
    let gridStyle: MediaPickerStyle.GridStyle
    let selectionIndex: Int?
    let accentColor: Color
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Square Base
            Rectangle()
                .fill(Color.black)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Group {
                        if let thumbnail = thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                        }
                    }
                )
                .clipped()
                .cornerRadius(gridStyle.cornerRadius)
            
            // Video Duration Overlay
            if gridStyle.showVideoDuration && asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(asset.duration))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }
            }
            
            // Selection Indicator
            if let index = selectionIndex {
                selectionIndicator(for: index)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onAppear { loadThumbnail() }
    }
    
    @ViewBuilder
    private func selectionIndicator(for index: Int) -> some View {
        switch gridStyle.selectionIndicator {
        case .numbered:
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(accentColor)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
        case .checkmark:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(accentColor)
                .background(Circle().fill(.white))
        case .none:
            EmptyView()
        }
    }
    
    private func loadThumbnail() {
        let scale: CGFloat = 2.0 // Standard retina scale
        let targetSize = CGSize(width: 200 * scale, height: 200 * scale)
        
        PhotoKitService.shared.loadThumbnail(for: asset, size: targetSize) { image in
            self.thumbnail = image
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
