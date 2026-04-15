import SwiftUI
import Photos

struct AssetGridView: View {
    let configuration: MediaPickerConfiguration
    let onAssetTap: (PHAsset) -> Void
    let onSelectionComplete: ([PHAsset]) -> Void
    
    @State private var vm: AssetGridViewModel
    
    init(configuration: MediaPickerConfiguration, onAssetTap: @escaping (PHAsset) -> Void, onSelectionComplete: @escaping ([PHAsset]) -> Void) {
        self.configuration = configuration
        self.onAssetTap = onAssetTap
        self.onSelectionComplete = onSelectionComplete
        self._vm = State(initialValue: AssetGridViewModel(selectionLimit: configuration.selectionLimit))
    }
    
    private var gridStyle: MediaPickerStyle.GridStyle {
        configuration.style.gridStyle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            gridHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(configuration.style.toolbarColor)
            
            // The Grid
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: gridStyle.spacing), count: gridStyle.columnCount),
                    spacing: gridStyle.spacing
                ) {
                    ForEach(vm.state.assets, id: \.localIdentifier) { asset in
                        AssetThumbnailCell(
                            asset: asset,
                            gridStyle: gridStyle,
                            selectionIndex: vm.selectionIndex(for: asset),
                            accentColor: configuration.style.accentColor
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.trigger(.selectAsset(asset))
                            onAssetTap(asset)
                            
                            // AUTO-FINISH ONLY if it's a double tap or single select + no preview mode
                            // But for V3 Elite, we prefer explicit NEXT or tapping to preview.
                            // So we remove the auto-finish here.
                        }
                    }
                }
            }
        }
        .onAppear { vm.trigger(.loadInitialData) }
    }
    
    private var gridHeader: some View {
        HStack {
            if gridStyle.showAlbumPicker {
                AlbumDropdownMenu(viewModel: vm)
            } else {
                Text(vm.state.currentAlbum?.title ?? "Recents")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // If not multi-select, and user has ONE asset selected, show NEXT
                if !vm.state.isMultiSelectActive && !vm.state.selectedAssets.isEmpty {
                    nextButton
                }
                
                if configuration.selectionLimit > 1 {
                    Button(vm.state.isMultiSelectActive ? "CANCEL" : "SELECT") {
                        vm.trigger(.toggleMultiSelect)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(vm.state.isMultiSelectActive ? .red : .blue)
                }
                
                if vm.state.isMultiSelectActive && !vm.state.selectedAssets.isEmpty {
                    nextButton
                }
            }
        }
        .frame(minHeight: 32) // Prevent layout shift when NEXT button appears/disappears
        .animation(nil, value: vm.state.selectedAssets.count)
    }
    
    private var nextButton: some View {
        Button("NEXT\(vm.state.selectedAssets.count > 1 ? " (\(vm.state.selectedAssets.count))" : "")") {
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
