import SwiftUI
import Photos

/// The asset grid. Self-contained — instantiates its own
/// `AssetGridViewModel` via the shared-cache resolver (so identity churn
/// upstream doesn't reset selected-asset state mid-session).
///
/// Takes `currentAlbum` as a `Binding` from the parent (Apple's
/// `Picker(selection:)` pattern). When the binding's value changes (because
/// the parent — `PickerView` — owns the truth and updates it from the
/// album dropdown or its own initial-album bootstrap), the view's
/// `.onChange` fires and the VM loads the assets for the new album.
struct AssetGridView: View {
    let configuration: MediaPickerConfiguration
    @Binding var currentAlbum: PhotoLibraryService.AlbumInfo?
    let onAssetTap: (GridAsset) -> Void

    @State private var viewModel: AssetGridViewModel

    init(
        configuration: MediaPickerConfiguration,
        currentAlbum: Binding<PhotoLibraryService.AlbumInfo?>,
        onAssetTap: @escaping (GridAsset) -> Void
    ) {
        self.configuration = configuration
        self._currentAlbum = currentAlbum
        self.onAssetTap = onAssetTap
        // Resolve the shared cache instance — survives upstream identity churn.
        self._viewModel = State(initialValue: AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit))
    }

    private var gridStyle: MediaPickerStyle.GridStyle {
        configuration.style.gridStyle
    }

    var body: some View {
        ScrollView {
            // Show skeleton placeholders while the asset list is empty —
            // either we're still loading (state.isLoading) or pre-warm
            // hasn't finished yet (first launch, no cache). The skeleton
            // matches the real grid's column count + spacing so the layout
            // doesn't shift when real cells take over. Modern iOS pattern:
            // Photos, Files, Mail all do this.
            if viewModel.state.assets.isEmpty {
                skeletonGrid
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: gridStyle.spacing), count: gridStyle.columnCount),
                    spacing: gridStyle.spacing
                ) {
                    ForEach(viewModel.state.assets, id: \.id) { asset in
                        AssetThumbnailCell(
                            source: asset.phAsset != nil ? .phAsset(asset.phAsset!) : .mediaItem(asset.mediaItem!),
                            gridStyle: gridStyle,
                            selectionIndex: viewModel.selectionIndex(for: asset),
                            accentColor: configuration.style.accentColor
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.trigger(.selectAsset(asset))
                            onAssetTap(asset)
                        }
                    }
                }
            }
        }
        .onChange(of: currentAlbum) { _, newAlbum in
            // When the parent (PickerView) sets currentAlbum (either from the
            // album dropdown or from its initial-album bootstrap), load the
            // assets for it. The VM caches the album internally for the
            // PhotoKit change observer's refresh path.
            if let newAlbum {
                viewModel.trigger(.selectAlbum(newAlbum))
            }
        }
    }

    /// Skeleton placeholder grid shown while real assets are loading. Renders
    /// the same column structure as the real grid so when assets arrive the
    /// layout doesn't shift — only the cell contents fade in. We size the
    /// placeholder count to fill roughly two screens (40 cells at 4 columns =
    /// 10 rows, which covers anything reasonable). LazyVGrid only renders the
    /// on-screen cells anyway, so off-screen placeholders are essentially free.
    private var skeletonGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: gridStyle.spacing), count: gridStyle.columnCount),
            spacing: gridStyle.spacing
        ) {
            ForEach(0..<40, id: \.self) { _ in
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(gridStyle.cornerRadius)
            }
        }
    }
}
