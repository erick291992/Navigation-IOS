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
    /// Fires when the first asset in the loaded grid changes — typically
    /// the result of an album switch (Recents → Favorites etc.). Parent
    /// uses it to keep the top previewer in sync with the active album.
    let onFirstAssetChanged: (PHAsset?) -> Void

    @State private var viewModel: AssetGridViewModel

    init(
        configuration: MediaPickerConfiguration,
        currentAlbum: Binding<PhotoLibraryService.AlbumInfo?>,
        selectedMode: PickerMode,
        history: [MediaItem],
        onAssetTap: @escaping (GridAsset) -> Void,
        onSelectionChange: @escaping ([GridAsset]) -> Void,
        onFirstAssetChanged: @escaping (PHAsset?) -> Void
    ) {
        self.configuration = configuration
        self._currentAlbum = currentAlbum
        self.selectedMode = selectedMode
        self.history = history
        self.onAssetTap = onAssetTap
        self.onSelectionChange = onSelectionChange
        self.onFirstAssetChanged = onFirstAssetChanged
        self._viewModel = State(initialValue: AssetGridViewModel(selectionLimit: configuration.selectionLimit))
    }

    private var gridStyle: MediaPickerStyle.GridStyle {
        configuration.style.gridStyle
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Show skeleton placeholders while the asset list is empty —
                // either we're still loading (state.isLoading) or pre-warm
                // hasn't finished yet (first launch, no cache). The skeleton
                // matches the real grid's column count + spacing so the layout
                // doesn't shift when real cells take over. Modern iOS pattern:
                // Photos, Files, Mail all do this.
                if viewModel.assetGridState.assets.isEmpty {
                    skeletonGrid
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: gridStyle.spacing), count: gridStyle.columnCount),
                        spacing: gridStyle.spacing
                    ) {
                        ForEach(viewModel.assetGridState.assets, id: \.id) { asset in
                            AssetThumbnailCell(
                                source: asset,
                                gridStyle: gridStyle,
                                selectionIndex: viewModel.selectionIndex(for: asset),
                                accentColor: configuration.style.accentColor,
                                initialImage: viewModel.thumbnail(for: asset),
                                loadAsync: { await viewModel.requestThumbnail(for: asset) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.trigger(.selectAsset(asset))
                                onAssetTap(asset)
                            }
                            // Pagination sentinel — when the cell `sentinelBuffer`
                            // positions before the end appears, ask the VM to
                            // load the next page. View only compares IDs (O(1));
                            // the VM owns the actual page-load orchestration.
                            .onAppear {
                                if asset.id == viewModel.sentinelAssetID {
                                    viewModel.loadNextPageIfNeeded()
                                }
                            }
                        }
                    }
                    // Selection-aware haptic: fires on .selection only when the
                    // tracked array actually changes. At-limit no-op taps don't
                    // change the array (toggleAssetSelection's guard rejects the
                    // append silently), so they don't fire. Same array, no haptic
                    // — exactly the UX requested.
                    .sensoryFeedback(.selection, trigger: viewModel.assetGridState.selectedAssets)
                }
            }
            .task {
                // Initial selection from cache is already loaded by VM.init —
                // emit it once so the parent (PickerView) can sync its mirror
                // and the NEXT button reflects any restored selection.
                onSelectionChange(viewModel.assetGridState.selectedAssets)
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
            .onChange(of: viewModel.assetGridState.selectedAssets) { _, newSelection in
                // Mirror selection up to the parent so PickerView's NEXT button
                // count + handleShutter/handleNextTapped see the same selection
                // the user just made. The VM has already written through to
                // AssetGridSelectionCache; this callback just keeps the parent's
                // observable mirror in sync.
                onSelectionChange(newSelection)
            }
            .onChange(of: viewModel.assetGridState.assets.first?.id) { oldID, newID in
                // Bubble the new first asset up so the parent can refresh the
                // top previewer to match the active album (Trigger 3 — switching
                // Recents → Favorites → Screenshots etc. follows in the previewer).
                // Fires on initial load too, but the parent's setPreview is
                // idempotent for the same identifier so no harm.
                onFirstAssetChanged(viewModel.assetGridState.assets.first?.phAsset)

                // Reset scroll to top of the new content on album swap. Without
                // this, SwiftUI's ScrollView preserves its scroll offset across
                // content replacement — switching from a deep-scrolled Recents
                // to Selfies leaves Selfies clamped to the bottom of its (much
                // shorter) content, exactly the behavior Photos.app / Instagram /
                // every native iOS picker explicitly avoids. Also: LazyVGrid
                // would otherwise mount cells from the middle of the new album,
                // which are NOT in our prewarmed first-16 → cache misses →
                // empty squares → defeats recommendation #3. Resetting scroll
                // means LazyVGrid mounts cells 0-15, which ARE prewarmed.
                //
                // Guards:
                //  - `oldID != nil`: skip the initial mount (cold open, going
                //    from no assets → first album). No scroll position to reset.
                //  - `oldID != newID`: skip same-album refreshes (e.g. library
                //    change observer re-materializing the same first asset).
                guard let newID, oldID != nil, oldID != newID else { return }
                proxy.scrollTo(newID, anchor: .top)
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
