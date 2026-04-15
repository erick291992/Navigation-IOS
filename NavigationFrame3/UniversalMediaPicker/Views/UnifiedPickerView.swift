import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Observation

/// The "Gold Standard" entry point for media creation.
/// Merges a live camera preview with a quick-access library strip, video recording, and session history (REUSE).
public struct UnifiedPickerView: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
    }
    
    // Services
    @StateObject private var cameraService = CameraService.shared
    @StateObject private var photoKit = PhotoKitService.shared
    private var historyManager = MediaHistoryManager.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Internal States
    @State private var selection: [PhotosPickerItem] = []
    @State private var isShowingSystemPicker = false
    @State private var selectedMode: CreatorMode = .library
    @State private var isRecording = false
    @State private var previewAsset: PHAsset?
    @State private var previewHistoryItem: MediaItem?
    
    enum CreatorMode {
        case library, reuse, photo, video
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                let viewWidth = proxy.size.width
                // Force a perfectly square viewfinder on capable screens,
                // but scale it down slightly on smaller phones to protect the bottom panel
                let maxViewfinderHeight = proxy.size.height * 0.48
                let viewfinderHeight = min(viewWidth, maxViewfinderHeight)
                
                // The bottom panel gets exactly whatever space is left
                let bottomHeight = proxy.size.height - viewfinderHeight
                
                VStack(spacing: 0) {
                    // MARK: - Top Viewfinder / Previewer
                    viewfinderArea
                        .frame(width: viewWidth, height: viewfinderHeight)
                        .clipped()
                    
                    // MARK: - Bottom Control Panel
                    bottomPanel
                        .frame(width: viewWidth, height: bottomHeight)
                        .clipped()
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(Color.black)
        .onAppear {
            photoKit.fetchRecentAssets()
            cameraService.setup()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                photoKit.updateAuthStatus() // Silent refresh
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
    
    // MARK: - Viewfinder Components
    
    // MARK: - Sub-Views
    
    private var viewfinderArea: some View {
        ZStack {
            Group {
                if photoKit.authStatus == .notDetermined {
                    onboardingView
                } else {
                    mainViewfinderContent
                }
            }
            .transition(.opacity)
            
            // Exit Button (Always available to escape)
            exitButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
    }
    
    private var mainViewfinderContent: some View {
        ZStack {
            if selectedMode == .video {
                videoComingSoonView
            } else {
                switch selectedMode {
                case .library:
                    if photoKit.authStatus == .denied || photoKit.authStatus == .restricted {
                        PermissionNeededView(type: .library)
                    } else {
                        libraryViewfinder
                    }
                case .reuse:
                    historyViewfinder
                default:
                    if cameraService.isSourceReady {
                        CameraPreviewView()
                    } else {
                        PermissionNeededView(type: .camera)
                    }
                }
            }
            
            // Mode Overlay (Recording indicator)
            if isRecording {
                recordingIndicator
            }
        }
        .animation(nil, value: selectedMode)
    }
    
    private var videoComingSoonView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("Video Recording")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
            Text("Coming Soon in V4 Elite")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.blue.opacity(0.8))
                .tracking(1.0)
        }
    }
    
    private var onboardingView: some View {
        VStack(spacing: 30) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
            
            VStack(spacing: 12) {
                Text("Unified Creator V3")
                    .font(.title.bold())
                Text("To start creating elite content, we need access to your library and camera.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                photoKit.fetchRecentAssets()
                cameraService.setup()
            }) {
                Text("GET STARTED")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(30)
            }
        }
        .foregroundColor(.white)
    }
    
    private var libraryViewfinder: some View {
        Group {
            if photoKit.recentAssets.isEmpty {
                emptyLibraryState
            } else {
                LibraryPreviewer(asset: previewAsset ?? photoKit.recentAssets.first)
                    .onTapGesture { isShowingSystemPicker = true }
            }
        }
    }
    
    private var historyViewfinder: some View {
        Group {
            if historyManager.history.isEmpty {
                emptyHistoryState
            } else {
                HistoryPreviewer(item: previewHistoryItem ?? historyManager.history.first)
            }
        }
    }
    
    private var emptyLibraryState: some View {
        Color.black.overlay(
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.2))
                Text("No Recent Photos Found")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                Button("Open Library") { isShowingSystemPicker = true }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
            }
        )
    }
    
    private var emptyHistoryState: some View {
        Color.black.overlay(
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.2))
                Text("No Session History")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
        )
    }
    
    private var recordingIndicator: some View {
        VStack {
            HStack {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("REC").font(.caption.bold()).foregroundColor(.white)
            }
            .padding(8)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .padding(.top, 20)
            Spacer()
        }
    }
    
    private var exitButton: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(20)
                }
                Spacer()
            }
            .padding(.top, 40) // Add padding to avoid the notch/dynamic island
            Spacer()
        }
    }
    
    // MARK: - Bottom Panel Components
    
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if photoKit.authStatus == .notDetermined {
                Color.black
            } else if selectedMode == .library {
                let status = photoKit.authStatus
                if status == .denied || status == .restricted {
                    PermissionNeededView(type: .library)
                        .frame(maxHeight: .infinity)
                } else if configuration.style.gridStyle.galleryMode == .grid {
                    AssetGridView(
                        configuration: configuration,
                        onAssetTap: { asset in
                            previewAsset = asset
                        },
                        onSelectionComplete: { assets in
                            handleAssets(assets)
                        }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    nativeLibraryStrip
                        .padding(.top, 16)
                }
            } else if selectedMode == .reuse {
                reuseHistoryStrip
            }
            
            Spacer(minLength: 0) // Keeps the shutter bar pinned to the bottom
            
            // MAIN ACTION AREA
            shutterAndModeBar
                .padding(.top, 8)
                .padding(.bottom, 24) 
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var nativeLibraryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            stripHeader
            contentScrollView
        }
    }
    
    private var reuseHistoryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            stripHeader
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    historyStrip
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 70)
        }
    }
    
    private var stripHeader: some View {
        HStack {
            Text(selectedMode == .reuse ? "PICKED HISTORY" : "RECENT LIBRARY")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)
            Spacer()
            if selectedMode == .library {
                adaptiveLibraryButton
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var adaptiveLibraryButton: some View {
        Group {
            if photoKit.authStatus == .limited {
                Button("MANAGE") { photoKit.openLimitedPicker() }
            } else if photoKit.authStatus == .authorized {
                Button("SELECT") { isShowingSystemPicker = true }
            } else if photoKit.authStatus == .denied {
                Button("ENABLE ACCESS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.blue)
    }
    
    private var contentScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if selectedMode == .reuse {
                    historyStrip
                } else {
                    libraryStrip
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 70)
    }
    
    private var libraryStrip: some View {
        ForEach(photoKit.recentAssets, id: \.localIdentifier) { asset in
            AssetThumbnailView(asset: asset) { _ in
                previewAsset = asset
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: previewAsset?.localIdentifier == asset.localIdentifier ? 3 : 0)
            )
        }
    }
    
    private var historyStrip: some View {
        ForEach(historyManager.history, id: \.id) { item in
            Image(uiImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 70, height: 70)
                .cornerRadius(6)
                .clipped()
                .onTapGesture { self.previewHistoryItem = item }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue, lineWidth: previewHistoryItem?.id == item.id ? 3 : 0)
                )
        }
    }
    
    private var shutterAndModeBar: some View {
        VStack(spacing: 20) {
            HStack {
                // Left slot: Gallery Shortcut (fixed width for centering)
                galleryShortcut
                    .frame(width: 48, height: 48)
                
                Spacer()
                
                Button(action: onShutterTab) {
                    shutterView
                }
                .buttonStyle(ScaleButtonStyle())
                
                Spacer()
                
                // Right slot: Flip camera OR invisible spacer (same width as left)
                Group {
                    if selectedMode == .photo || selectedMode == .video {
                        Button(action: { cameraService.flipCamera() }) {
                            Circle().fill(.white.opacity(0.1)).frame(width: 44, height: 44)
                                .overlay(Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.white))
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 48, height: 48)
            }
            .padding(.horizontal, 30)
            
            // Mode labels — centered HStack, no ScrollView needed for 4 labels
            HStack(spacing: 24) {
                ForEach([CreatorMode.library, .reuse, .photo, .video], id: \.self) { mode in
                    ModeButton(title: modeTitle(mode), isSelected: selectedMode == mode) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMode = mode
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
    }
    
    private var shutterView: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 72, height: 72)
            
            if selectedMode == .video {
                RoundedRectangle(cornerRadius: isRecording ? 4 : 30)
                    .fill(Color.red)
                    .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                    .animation(.spring(), value: isRecording)
            } else if selectedMode == .library || selectedMode == .reuse {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 60, height: 60)
                    .background(Color.white)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
    }
    
    // MARK: - Actions
    
    private func onShutterTab() {
        switch selectedMode {
        case .photo: capturePhoto()
        case .video: toggleRecording()
        case .library:
            if let asset = previewAsset ?? photoKit.recentAssets.first {
                handleAsset(asset)
            }
        case .reuse:
            if let item = previewHistoryItem ?? historyManager.history.first {
                onCompletion([item])
            }
        }
    }
    
    private func capturePhoto() {
        cameraService.capture { image in
            if let image = image {
                handleSelection(image)
            }
        }
    }
    
    private func toggleRecording() {
        // VIDEO is currently a placeholder
    }
    
    private func handleSelection(_ image: UIImage) {
        Task {
            if let item = try? await MediaPickerManager.shared.process(image) {
                onCompletion([item])
            }
        }
    }
    
    private func handleAsset(_ asset: PHAsset) {
        handleAssets([asset])
    }
    
    private func handleAssets(_ assets: [PHAsset]) {
        Task {
            // Dogfooding: The Elite picker relies entirely on the Tier 3 Engine
            // to process raw PHAssets into MediaItems.
            if let processedItems = try? await MediaPickerEngine.shared.process(assets), !processedItems.isEmpty {
                await MainActor.run {
                    onCompletion(processedItems)
                }
            }
        }
    }
    
    private func modeTitle(_ mode: CreatorMode) -> String {
        switch mode {
        case .library: return "LIBRARY"
        case .reuse: return "REUSE"
        case .photo: return "PHOTO"
        case .video: return "VIDEO"
        }
    }
    
    private var galleryShortcut: some View {
        Button(action: galleryShortcutAction) {
            ZStack {
                if (photoKit.authStatus == .authorized || photoKit.authStatus == .limited), let firstAsset = photoKit.recentAssets.first {
                    // Full/Limited: Show latest photo thumbnail
                    AssetThumbnailView(asset: firstAsset) { _ in }
                        .allowsHitTesting(false)
                        .frame(width: 48, height: 48)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.6), lineWidth: 2))
                } else if photoKit.authStatus == .denied || photoKit.authStatus == .restricted {
                    // Denied: Show lock icon — tapping opens Settings
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2))
                        .overlay(Image(systemName: "lock.fill").foregroundColor(.white.opacity(0.4)))
                } else {
                    // Not Determined / no photos: Placeholder icon
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2))
                        .overlay(Image(systemName: "photo").foregroundColor(.white.opacity(0.4)))
                }
            }
        }
        .disabled(photoKit.authStatus == .notDetermined)
    }
    
    private func galleryShortcutAction() {
        switch photoKit.authStatus {
        case .authorized, .limited:
            isShowingSystemPicker = true
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }
}
