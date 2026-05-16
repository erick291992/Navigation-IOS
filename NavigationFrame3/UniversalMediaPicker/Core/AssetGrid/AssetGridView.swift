import SwiftUI
import Photos

struct AssetGridView: View {
    let configuration: MediaPickerConfiguration
    let onAssetTap: (GridAsset) -> Void
    let onSelectionComplete: ([GridAsset]) -> Void
    let showHeader: Bool
    
    @State private var vm: AssetGridViewModel
    
    // ---------------------------------------------------------
    // Initializer 1: STANDALONE (No ViewModel required)
    // ---------------------------------------------------------
    init(
        configuration: MediaPickerConfiguration,
        showHeader: Bool = true,
        onAssetTap: @escaping (GridAsset) -> Void,
        onSelectionComplete: @escaping ([GridAsset]) -> Void
    ) {
        self.configuration = configuration
        self.showHeader = showHeader
        self.onAssetTap = onAssetTap
        self.onSelectionComplete = onSelectionComplete
        self._vm = State(initialValue: AssetGridViewModel(selectionLimit: configuration.selectionLimit))
    }

    // ---------------------------------------------------------
    // Initializer 2: INJECTED (Pass a shared ViewModel)
    // ---------------------------------------------------------
    init(
        configuration: MediaPickerConfiguration,
        viewModel: AssetGridViewModel,
        showHeader: Bool = true,
        onAssetTap: @escaping (GridAsset) -> Void,
        onSelectionComplete: @escaping ([GridAsset]) -> Void
    ) {
        self.configuration = configuration
        self.showHeader = showHeader
        self.onAssetTap = onAssetTap
        self.onSelectionComplete = onSelectionComplete
        self._vm = State(initialValue: viewModel)
    }
    
    private var gridStyle: MediaPickerStyle.GridStyle {
        configuration.style.gridStyle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                // Header
                gridHeader
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(configuration.style.toolbarColor)
            }

            // The Grid
            ScrollView {
                // Show skeleton placeholders while the asset list is empty —
                // either we're still loading (state.isLoading) or pre-warm
                // hasn't finished yet (first launch, no cache). The skeleton
                // matches the real grid's column count + spacing so the layout
                // doesn't shift when real cells take over. Modern iOS pattern:
                // Photos, Files, Mail all do this.
                if vm.state.assets.isEmpty {
                    skeletonGrid
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: gridStyle.spacing), count: gridStyle.columnCount),
                        spacing: gridStyle.spacing
                    ) {
                        ForEach(vm.state.assets, id: \.id) { asset in
                            AssetThumbnailCell(
                                source: asset.phAsset != nil ? .phAsset(asset.phAsset!) : .mediaItem(asset.mediaItem!),
                                gridStyle: gridStyle,
                                selectionIndex: vm.selectionIndex(for: asset),
                                accentColor: configuration.style.accentColor
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                vm.trigger(.selectAsset(asset))
                                onAssetTap(asset)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Only auto-load library if we're not already populated with history
            if vm.state.assets.isEmpty {
                vm.trigger(.loadInitialData)
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
    
    private var gridHeader: some View {
        HStack {
            if gridStyle.showAlbumPicker && vm.state.currentAlbum != nil {
                AlbumDropdownMenu(viewModel: vm)
            } else {
                Text(vm.state.currentAlbum?.title ?? "Recents")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                nextButton
                    .disabled(vm.state.selectedAssets.isEmpty)
                    .opacity(vm.state.selectedAssets.isEmpty ? 0.3 : 1.0)
            }
        }
        .frame(minHeight: 32) // Prevent layout shift
        .animation(nil, value: vm.state.selectedAssets.count)
    }
    
    private var nextButton: some View {
        let count = vm.state.selectedAssets.count
        let limit = vm.selectionLimit
        let label = count > 0 ? "NEXT (\(count)/\(limit))" : "NEXT"
        
        return Button(label) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSelectionComplete(vm.state.selectedAssets)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(configuration.style.accentColor)
        .cornerRadius(12)
    }
}
