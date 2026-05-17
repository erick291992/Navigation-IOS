import SwiftUI
import Photos

/// The asset grid. **Self-contained** — instantiates its own
/// `AssetGridViewModel` via plain `@State`. The user's selection survives
/// SwiftUI's upstream identity churn because `AssetGridViewModel.init`
/// restores it from `AssetGridSelectionCache` (a small process-wide cache
/// for `[GridAsset]` only).
///
/// Cross-cutting inputs flow DOWN as parameters (Apple's primitive shape):
/// - `currentAlbum: Binding` — picker owns the truth; we observe via `.onChange`.
/// - `selectedMode: PickerMode` — picker owns; we observe to swap data source.
/// - `history: [MediaItem]` — picker provides for reuse-mode loading.
///
/// Events flow UP via callbacks:
/// - `onAssetTap(GridAsset)` — fires when user taps a cell.
/// - `onSelectionChange([GridAsset])` — fires whenever the VM's selection
///   array changes, so the parent (PickerView) can mirror count + selection
///   for its NEXT-button and shutter-handler logic.
struct AssetGridView: View {
    let configuration: MediaPickerConfiguration
    @Binding var currentAlbum: PhotoLibraryService.AlbumInfo?
    let selectedMode: PickerMode
    let history: [MediaItem]
    let onAssetTap: (GridAsset) -> Void
    let onSelectionChange: ([GridAsset]) -> Void

    @State private var viewModel: AssetGridViewModel

    init(
        configuration: MediaPickerConfiguration,
        currentAlbum: Binding<PhotoLibraryService.AlbumInfo?>,
        selectedMode: PickerMode,
        history: [MediaItem],
        onAssetTap: @escaping (GridAsset) -> Void,
        onSelectionChange: @escaping ([GridAsset]) -> Void
    ) {
        self.configuration = configuration
        self._currentAlbum = currentAlbum
        self.selectedMode = selectedMode
        self.history = history
        self.onAssetTap = onAssetTap
        self.onSelectionChange = onSelectionChange
        self._viewModel = State(initialValue: AssetGridViewModel(selectionLimit: configuration.selectionLimit))
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
                            // TODO: restore haptic feedback once Core Haptics
                            // pre-warm is solved without re-introducing the
                            // first-tap stall. Previous approach (prewarm in
                            // `MediaPickerModifier.onAppear` + shared static
                            // `UIImpactFeedbackGenerator`) cured the stall on
                            // simulator but reintroduced it intermittently —
                            // needs proper device testing + a measured warm
                            // window before re-adding. Diagnosis notes are in
                            // chat history; root cause is Core Haptics engine
                            // cold-start blocking the main thread for
                            // ~400-1000 ms on first `.impactOccurred()`.
                            viewModel.trigger(.selectAsset(asset))
                            onAssetTap(asset)
                        }
                    }
                }
            }
        }
        .task {
            // Initial selection from cache is already loaded by VM.init —
            // emit it once so the parent (PickerView) can sync its mirror
            // and the NEXT button reflects any restored selection.
            onSelectionChange(viewModel.state.selectedAssets)
        }
        .onChange(of: currentAlbum) { _, newAlbum in
            // Parent updated currentAlbum (dropdown selection or initial bootstrap).
            // Skip if we're in reuse mode — history is the data source there.
            guard selectedMode != .reuse else { return }
            if let newAlbum {
                viewModel.trigger(.selectAlbum(newAlbum))
            }
        }
        .onChange(of: selectedMode) { _, newMode in
            // Mode switch — swap the data source. In reuse mode the grid
            // shows history items; otherwise it shows the current album's
            // assets.
            switch newMode {
            case .reuse:
                viewModel.trigger(.loadHistory(history))
            case .library, .photo:
                if let album = currentAlbum {
                    viewModel.trigger(.selectAlbum(album))
                }
            }
        }
        .onChange(of: viewModel.state.selectedAssets) { _, newSelection in
            // Mirror selection up to the parent so PickerView's NEXT button
            // count + handleShutter/handleNextTapped see the same selection
            // the user just made. The VM has already written through to
            // AssetGridSelectionCache; this callback just keeps the parent's
            // observable mirror in sync.
            onSelectionChange(newSelection)
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
