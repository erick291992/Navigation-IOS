import SwiftUI
import PhotosUI
import Photos

/// "Elite Geometric Picker" (Style B)
/// A gorgeous, distinct alternative to the primary Elite Picker.
/// Features a unique geometric layout (modes strictly under the viewfinder),
/// an Instagram-styled edge-to-edge 1px grid, and high-contrast green accents.
public struct EliteGeometricPickerView: View {
    @State private var viewModel: EliteGeometricPickerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: EliteGeometricPickerViewModel(
            configuration: configuration,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.currentStage == .select {
                GeometryReader { proxy in
                    let viewWidth = proxy.size.width
                    let maxViewfinderHeight = proxy.size.height * 0.48
                    let viewfinderHeight = min(viewWidth, maxViewfinderHeight)
                    
                    VStack(spacing: 0) {
                        // Spacer to preserve layout while Navbar is an overlay
                        Color.clear.frame(height: 54)
                        
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
                .transition(.opacity)
            }
            
            if viewModel.currentStage == .crop {
                CropFlowView(
                    configuration: viewModel.configuration,
                    initialItems: viewModel.processedItems,
                    onCompletion: { items in
                        viewModel.finalizeFlow(items: items)
                        dismiss()
                    },
                    onCancel: {
                        viewModel.cancelCrop()
                    },
                    onGoBack: {
                        viewModel.cancelCrop()
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .overlay(alignment: .top) {
            if viewModel.currentStage == .select {
                // MARK: - Premium Navbar (Pro Max Hardened)
                ZStack {
                    HStack {
                        Button(action: { 
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.onCancelAction() 
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.3)) // Contrast backing
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 10)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle()) 
                        
                        Spacer()
                        
                        Button(action: { 
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.handleNext() 
                        }) {
                            Text("Next")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(viewModel.canProceed ? .green : .gray)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(viewModel.canProceed ? Color.green.opacity(0.1) : Color.clear)
                                .cornerRadius(12)
                        }
                        .disabled(!viewModel.canProceed)
                        .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    
                    Text("New Post")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                }
                .padding(.top, 44) // 🛡️ Dynamic Island / StatusBar Clearance
                .frame(height: 100, alignment: .bottom) // Combined height for nav
                .background(Color.black)
                .zIndex(100)
                .transition(.move(edge: .top).combined(with: .opacity))
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
        .onChange(of: viewModel.recentAssets) { _, assets in
            if viewModel.previewAsset == nil, let first = assets.first {
                viewModel.toggleAsset(first)
            }
        }
        .onChange(of: viewModel.selection) { _, items in
            viewModel.handleSystemPickerSelection(items)
        }
    }
    
    // MARK: - Mode Strip
    private var modeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                Spacer().frame(width: 8)
                ForEach(EliteGeometricPickerViewModel.CreatorMode.allCases, id: \.self) { mode in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectMode(mode)
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: viewModel.selectedMode == mode ? .black : .bold))
                            .foregroundColor(viewModel.selectedMode == mode ? .white : .gray)
                            .padding(.vertical, 12)
                            .overlay(
                                Capsule()
                                    .fill(viewModel.selectedMode == mode ? Color.green : Color.clear)
                                    .frame(height: 3),
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
        ZStack(alignment: .bottom) {
            // 1. Photo/Video Viewfinder (Persistent & Warm)
            CameraPreviewView()
                .opacity((viewModel.selectedMode == .photo || viewModel.selectedMode == .video) ? 1 : 0)
            
            // 2. Library Preview (Overlay)
            if viewModel.selectedMode == .library {
                Group {
                    if viewModel.authStatus == .denied || viewModel.authStatus == .restricted {
                        PermissionNeededView(type: .library, accentColor: viewModel.configuration.style.accentColor)
                    } else if let asset = viewModel.previewAsset ?? viewModel.recentAssets.first {
                        LibraryPreviewer(
                            assetID: asset.localIdentifier,
                            initialImage: viewModel.thumbnail(for: asset),
                            loadAsync: { await viewModel.requestThumbnail(for: asset) }
                        )
                            .id(asset.localIdentifier)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Color.black
                            .overlay(Text("No Media").foregroundColor(.gray))
                    }
                }
                .transition(.opacity)
            }
            
            // 3. Reuse Preview (Overlay)
            if viewModel.selectedMode == .reuse {
                Group {
                    if let item = viewModel.previewHistoryItem ?? viewModel.history.first {
                        Image(uiImage: item.thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                            .overlay(Text("No Recents").foregroundColor(.gray))
                    }
                }
                .transition(.opacity)
            }
            
            // 4. Zoom Dial Overlay
            if viewModel.selectedMode == .photo {
                zoomDial
                    .padding(.bottom, 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedMode)
    }
    
    private var zoomDial: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.availableZoomFactors, id: \.self) { factor in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.setZoom(factor)
                }) {
                    Text(String(format: "%.1fx", factor))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.zoomFactor == factor ? Color.green : .white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(viewModel.zoomFactor == factor ? .white.opacity(0.2) : .clear))
                }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
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
                    
                    GeometryReader { geometry in
                        Color.black // Background for square letterboxing
                            .overlay(
                                AsyncFlexibleAssetView(assetSource: .phAsset(asset))
                                    .scaleEffect(isSelected ? 0.95 : 1.0)
                                    .aspectRatio(contentMode: .fit) // 🎞️ No Zoom: Touch sides, letterbox top/bottom
                                    .frame(width: geometry.size.width) // 📐 Force Width to Column
                                    .clipped()
                            )
                            .overlay(alignment: .topTrailing) {
                                if viewModel.configuration.selectionLimit > 1 {
                                    if let idx = selectionOffset {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 22, height: 22)
                                            .overlay(Text("\(idx + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(.black))
                                            .padding(6)
                                    } else {
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                            .padding(6)
                                    }
                                }
                            }
                    }
                    .aspectRatio(1284.0/2778.0, contentMode: .fit) // 📱 Match iPhone Screen Ratio (0.46)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation {
                            viewModel.toggleAsset(asset)
                        }
                    }
                }
            }
            
            // MARK: - Limited Access Footer
            if viewModel.authStatus == .limited {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.openLimitedPicker()
                }) {
                    VStack(spacing: 4) {
                        Divider().background(Color.white.opacity(0.1))
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text("Manage Selection")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color.black)
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
                            viewModel.setPreviewHistoryItem(item)
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
                    viewModel.toggleSystemPicker()
                }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
                
                Button(action: {
                    viewModel.onShutterTab()
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
