import SwiftUI
import Photos

struct AssetThumbnailCell: View {
    let source: AssetThumbnailSource
    let gridStyle: MediaPickerStyle.GridStyle
    let selectionIndex: Int?
    let accentColor: Color
    
    enum AssetThumbnailSource {
        case phAsset(PHAsset)
        case mediaItem(MediaItem)
        
        var phAsset: PHAsset? {
            if case .phAsset(let asset) = self { return asset }
            return nil
        }
        
        var mediaItem: MediaItem? {
            if case .mediaItem(let item) = self { return item }
            return nil
        }
    }
    
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
                .overlay(
                    RoundedRectangle(cornerRadius: gridStyle.cornerRadius)
                        .stroke(accentColor, lineWidth: selectionIndex != nil ? gridStyle.selectionBorderWidth : 0)
                )
                .cornerRadius(gridStyle.cornerRadius)
            
            // Video Duration Overlay
            if gridStyle.showVideoDuration {
                if let asset = source.phAsset, asset.mediaType == .video {
                    durationOverlay(duration: asset.duration)
                } else if let item = source.mediaItem, item.contentType == .video {
                    // Note: MediaItem doesn't currently store duration, but we could add it.
                    durationOverlay(duration: 0) 
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
    private func durationOverlay(duration: TimeInterval) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(formatDuration(duration))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .padding(4)
            }
        }
    }
    
    @ViewBuilder
    private func selectionIndicator(for index: Int) -> some View {
        switch gridStyle.selectionIndicator {
        case .numbered:
            Text("\(index)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 2)
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
        if let item = source.mediaItem {
            self.thumbnail = item.thumbnail
            return
        }
        
        guard let asset = source.phAsset else { return }
        
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
