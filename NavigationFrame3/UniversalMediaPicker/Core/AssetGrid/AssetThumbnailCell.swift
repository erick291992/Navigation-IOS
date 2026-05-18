import SwiftUI
import Photos

/// Pure presentational cell — knows nothing about PhotoKit, ThumbnailCache,
/// or how thumbnails are fetched. The parent (AssetGridView) wires it to the
/// grid VM, which routes through PhotoKitService.
///
/// Two image inputs:
/// - `initialImage`: painted immediately on body evaluation. Parent computes
///   synchronously (cache peek or MediaItem.thumbnail) so cell paints on
///   first frame without an async hop. nil → placeholder.
/// - `loadAsync`: optional async loader invoked from `.task(id:)`. Auto-cancels
///   on cell recycle (LazyVGrid reuses the View with a new asset; SwiftUI
///   cancels the old task and starts a new one keyed on `source.id`).
///
/// The cell keeps `@State asyncLoaded` for the resolved image so that when
/// the load finishes only THIS cell re-renders — moving the image into the
/// VM's observable state would cascade a re-render across every cell on each
/// load completion. Per-cell granularity preserved.
struct AssetThumbnailCell: View {
    let source: GridAsset
    let gridStyle: MediaPickerStyle.GridStyle
    let selectionIndex: Int?
    let accentColor: Color
    let initialImage: UIImage?
    let loadAsync: (() async -> UIImage?)?

    @State private var asyncLoaded: UIImage?
    private var displayImage: UIImage? { asyncLoaded ?? initialImage }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Square Base
            Rectangle()
                .fill(Color.black)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Group {
                        if let image = displayImage {
                            Image(uiImage: image)
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
        .task(id: source.id) {
            let shouldLog = PickerPerfLog.shouldLogCell()
            if shouldLog {
                PickerPerfLog.event("gridCell.task → enter (initialImage=\(initialImage != nil), id=\(source.id.suffix(8)))")
            }
            // Kick off the parent's async load only if we don't already have
            // an image to show and a loader was provided. `.task(id:)`
            // auto-cancels on cell recycle / disappear, so we don't waste
            // work loading thumbnails for cells that scrolled offscreen.
            guard displayImage == nil, let loadAsync else {
                if shouldLog {
                    PickerPerfLog.event("gridCell.task → skipped (cache hit, no async needed)")
                }
                return
            }
            asyncLoaded = await loadAsync()
            if shouldLog {
                PickerPerfLog.event("gridCell.task → async loaded (id=\(source.id.suffix(8)))")
            }
        }
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
