import SwiftUI
import PhotosUI
import Photos

/// "Elite Picker Style B"
/// A gorgeous, distinct alternative to the primary Elite Picker.
/// Features a unique geometric layout (modes strictly under the viewfinder),
/// an Instagram-styled edge-to-edge 1px grid, and high-contrast green accents.
public struct EliteStyleBPickerView: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    // Services
    @StateObject private var cameraService = CameraService.shared
    @StateObject private var photoKit = PhotoKitService.shared
    private var historyManager = MediaHistoryManager.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Internal States
    @State private var selection: [PhotosPickerItem] = []
    @State private var selectedAssets: [PHAsset] = []
    @State private var isShowingSystemPicker = false
    @State private var selectedMode: CreatorMode = .library
    @State private var isRecording = false
    @State private var previewAsset: PHAsset?
    @State private var previewHistoryItem: MediaItem?
    
    enum CreatorMode: String, CaseIterable {
        case library = "LIBRARY"
        case reuse = "REUSE"
        case photo = "PHOTO"
        case video = "VIDEO"
    }
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
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
                        Button(action: onCancel) {
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
                        
                        Button(action: handleNext) {
                            Text("Next")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canProceed ? .green : .gray)
                        }
                        .disabled(!canProceed)
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
            photoKit.fetchRecentAssets()
            cameraService.setup()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                photoKit.updateAuthStatus()
                if photoKit.authStatus == .authorized || photoKit.authStatus == .limited {
                    photoKit.fetchRecentAssets()
                }
            }
        }
        .photosPicker(isPresented: $isShowingSystemPicker, selection: $selection)
        .onChange(of: selection) { _, items in
            if !items.isEmpty {
                Task {
                    if let results = try? await MediaPickerManager.shared.process(items) {
                        onCompletion(results)
                    }
                }
            }
        }
    }
    
    private var canProceed: Bool {
        if selectedMode == .library { return previewAsset != nil || !selectedAssets.isEmpty }
        if selectedMode == .reuse { return previewHistoryItem != nil }
        return false // Camera proceeds immediately on capture
    }
    
    private func handleNext() {
        if selectedMode == .reuse, let item = previewHistoryItem {
            onCompletion([item])
        } else if selectedMode == .library {
            let assetsToProcess = selectedAssets.isEmpty ? (previewAsset.map { [$0] } ?? []) : Array(selectedAssets)
            Task {
                if let processed = try? await MediaPickerEngine.shared.process(assetsToProcess) {
                    onCompletion(processed)
                }
            }
        }
    }
    
    // MARK: - Mode Strip
    private var modeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                Spacer().frame(width: 8)
                ForEach(CreatorMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMode = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: selectedMode == mode ? .black : .bold))
                            .foregroundColor(selectedMode == mode ? .white : .gray)
                            .padding(.vertical, 8)
                            .overlay(
                                Rectangle()
                                    .fill(selectedMode == mode ? Color.green : Color.clear)
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
        switch selectedMode {
        case .library:
            if let asset = previewAsset ?? photoKit.recentAssets.first {
                GeometryReader { geo in
                    AssetThumbnailView(asset: asset, size: geo.size.width, cornerRadius: 0) { _ in }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                CameraPreviewView()
            }
        case .reuse:
            if let item = previewHistoryItem ?? historyManager.history.first {
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
        switch selectedMode {
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
                ForEach(photoKit.recentAssets, id: \.localIdentifier) { (asset: PHAsset) in
                    let isSelected = selectedAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
                    let selectionOffset = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
                    
                    ZStack(alignment: .topTrailing) {
                        AsyncFlexibleAssetView(asset: asset)
                            .scaleEffect(isSelected ? 0.95 : 1.0)
                        
                        if configuration.selectionLimit > 1 {
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
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation {
                            if configuration.selectionLimit > 1 {
                                if isSelected {
                                    selectedAssets.removeAll { $0.localIdentifier == asset.localIdentifier }
                                    if previewAsset?.localIdentifier == asset.localIdentifier { 
                                        previewAsset = selectedAssets.last 
                                    }
                                } else {
                                    if selectedAssets.count < configuration.selectionLimit {
                                        selectedAssets.append(asset)
                                        previewAsset = asset
                                    } else {
                                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                                    }
                                }
                            } else {
                                previewAsset = asset
                            }
                        }
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
                ForEach(historyManager.history, id: \.id) { item in
                    let isSelected = previewHistoryItem == item
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                        .border(Color.green, width: isSelected ? 3 : 0)
                        .onTapGesture {
                            withAnimation { previewHistoryItem = item }
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
                    isShowingSystemPicker = true
                }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
                
                Button(action: {
                    if selectedMode == .video {
                        print("Video recording not implemented in tier 3 demo yet")
                    } else {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        cameraService.capture { image in
                            if let image = image {
                                Task {
                                    if let processed = try? await MediaPickerEngine.shared.process(image) {
                                        await MainActor.run { onCompletion([processed]) }
                                    }
                                }
                            }
                        }
                    }
                }) {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                        .overlay(
                            Circle()
                                .fill(isRecording ? Color.red : (selectedMode == .video ? Color.red.opacity(0.8) : Color.white))
                                .frame(width: isRecording ? 32 : 64, height: isRecording ? 32 : 64)
                                .cornerRadius(isRecording ? 8 : 32)
                        )
                }
                
                Button(action: {
                    cameraService.flipCamera()
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
