import SwiftUI

/// Pure presentational previewer — knows nothing about PhotoKit or
/// ThumbnailCache. The parent (LibraryViewfinderView) wires it to
/// LibraryViewfinderViewModel, which routes through PhotoKitService.
///
/// Two image inputs (same shape as AssetThumbnailCell):
/// - `initialImage`: parent-provided synchronous read (cache peek). Paints
///   instantly when the displayed asset changes so the user sees the new
///   image on the same frame as their tap.
/// - `loadAsync`: parent-provided async upgrade loader. Fetches the
///   high-res version (1000pt) and replaces `initialImage` when it arrives.
///   Unlike the grid cell, this ALWAYS runs even when `initialImage`
///   exists — the cached image is smaller (cell-sized) and we want to
///   upgrade to the previewer's larger size.
///
/// `assetID` is the `.task(id:)` key. When it changes (user taps a
/// different grid cell), SwiftUI cancels the in-flight upgrade and starts
/// a new one against the new asset; the local `@State asyncLoaded` resets
/// so `initialImage` (the new asset's cache peek) paints first.
struct LibraryPreviewer: View {
    let assetID: String?
    let initialImage: UIImage?
    let loadAsync: (() async -> UIImage?)?

    @State private var asyncLoaded: UIImage?
    private var displayImage: UIImage? { asyncLoaded ?? initialImage }

    var body: some View {
        ZStack {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
                ProgressView().tint(.white)
            }
        }
        .task(id: assetID) {
            PickerPerfLog.event("libraryPreviewer.task → enter (initialImage=\(initialImage != nil), assetID=\(assetID ?? "nil"))")
            // Reset so the new asset's `initialImage` (cached peek) paints
            // immediately instead of leaving the previous tap's high-res
            // image hanging while the new fetch runs.
            asyncLoaded = nil
            guard let loadAsync else { return }
            if let loaded = await loadAsync() {
                asyncLoaded = loaded
                PickerPerfLog.event("libraryPreviewer.task → high-res loaded")
            }
        }
    }
}
