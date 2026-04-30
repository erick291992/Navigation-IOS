import SwiftUI
import PhotosUI
import Photos

/// "Elite Picker Style B"
/// A gorgeous, distinct alternative to the primary Elite Picker.
/// Features a unique geometric layout (modes strictly under the viewfinder),
/// an Instagram-styled edge-to-edge 1px grid, and high-contrast green accents.
public struct EliteStyleBPickView: View {
    @State private var viewModel: EliteStyleBPickViewModel
    
    @Environment(\.scenePhase) private var scenePhase
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: EliteStyleBPickViewModel(
            configuration: configuration,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                let viewWidth = proxy.size.width
                let maxViewfinderHeight = proxy.size.height * 0.48
                let viewfinderHeight = min(viewWidth, maxViewfinderHeight)
                
                VStack(spacing: 0) {
                    // MARK: - Premium Navbar
                    HStack {
                        Button(action: { viewModel.cancel() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                        
                        Spacer()
                        
                        Text("New Post")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { viewModel.handleNext() }) {
                            Text("Next")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(viewModel.canProceed ? .green : .gray)
                        }
                        .disabled(!viewModel.canProceed)
                        .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .background(Color.black)
                    
                    // MARK: - Viewfinder
                    viewfinderArea
                        .frame(width: viewWidth, height: viewfinderHeight)
                        .clipped()
                    
                    // MARK: - Mode Strip (Unique to Style B)
                    modeStrip
                        .frame(height: 50)
                        .background(Color(uiColor: .systemGray6).opacity(0.1))
                    
                    // MARK: - Dynamic Bottom Area
                    bottomArea
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            viewModel.setup()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.updateAuth()
            }
        }
        .photosPicker(isPresented: $viewModel.isShowingSystemPicker, selection: $viewModel.selection)
        .onChange(of: viewModel.selection) { _, items in
            viewModel.handleSystemPickerSelection(items)
        }
    }
    
    // MARK: - Mode Strip
    private var modeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                Spacer().frame(width: 8)
                ForEach(EliteStyleBPickViewModel.CreatorMode.allCases, id: \.self) { mode in
                    Button(action: { viewModel.setMode(mode) }) {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: viewModel.selectedMode == mode ? .black : .bold))
                            .foregroundColor(viewModel.selectedMode == mode ? .white : .gray)
                            .padding(.vertical, 8)
                            .overlay(
                                Rectangle()
                                    .fill(viewModel.selectedMode == mode ? Color.green : Color.clear)
                                    .frame(height: 2),
                                alignment: .bottom
                            )
                    }
                }
                Spacer().frame(width: 8)
            }
        }
    }
    
    // MARK: - Viewfinder Area
    @ViewBuilder
    private var viewfinderArea: some View {
        switch viewModel.selectedMode {
        case .library:
            if let asset = viewModel.previewAsset ?? viewModel.recentAssets.first {
                GeometryReader { geo in
                    AssetThumbnailView(asset: asset, size: geo.size.width, cornerRadius: 0) { _ in }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                CameraPreviewView()
            }
        case .reuse:
            if let item = viewModel.previewHistoryItem ?? viewModel.history.first {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                    .overlay(Text("No Recents").foregroundColor(.gray))
            }
        case .photo, .video:
            CameraPreviewView()
        }
    }
    
    // MARK: - Bottom Area
    @ViewBuilder
    private var bottomArea: some View {
        switch viewModel.selectedMode {
        case .library:
            libraryGrid
        case .reuse:
            reuseGrid
        case .photo, .video:
            cameraControls
        }
    }
    
    // MARK: - Library Edge-to-Edge Grid
    private var libraryGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 1),
            GridItem(.flexible(), spacing: 1),
            GridItem(.flexible(), spacing: 1)
        ]
        
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(viewModel.recentAssets, id: \.localIdentifier) { (asset: PHAsset) in
                    let isSelected = viewModel.selectedAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
                    let selectionOffset = viewModel.selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
                    
                    ZStack(alignment: .topTrailing) {
                        AsyncFlexibleAssetView(asset: asset)
                            .scaleEffect(isSelected ? 0.95 : 1.0)
                        
                        if let idx = selectionOffset {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 20, height: 20)
                                .overlay(Text("\(idx + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(.black))
                                .padding(4)
                        } else {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                                .padding(4)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectAsset(asset)
                    }
                }
            }
        }
        .background(Color.black)
    }
    
    // MARK: - Reuse Grid
    private var reuseGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 100), spacing: 2)
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.history, id: \.id) { item in
                    let isSelected = viewModel.previewHistoryItem == item
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                        .border(Color.green, width: isSelected ? 3 : 0)
                        .onTapGesture {
                            viewModel.selectHistoryItem(item)
                        }
                }
            }
            .padding(2)
        }
    }
    
    // MARK: - Camera Controls
    private var cameraControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 60) {
                Button(action: {
                    viewModel.isShowingSystemPicker = true
                }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
                
                Button(action: {
                    if viewModel.selectedMode == .video {
                        print("Video recording not implemented in tier 3 demo yet")
                    } else {
                        viewModel.capturePhoto()
                    }
                }) {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                        .overlay(
                            Circle()
                                .fill(viewModel.isRecording ? Color.red : (viewModel.selectedMode == .video ? Color.red.opacity(0.8) : Color.white))
                                .frame(width: viewModel.isRecording ? 32 : 64, height: viewModel.isRecording ? 32 : 64)
                                .cornerRadius(viewModel.isRecording ? 8 : 32)
                        )
                }
                
                Button(action: {
                    viewModel.flipCamera()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
            }
            Spacer()
        }
    }
}
