import SwiftUI
import PhotosUI
import Photos
import AVFoundation

/// The "Gold Standard" entry point for media creation.
/// Merges a live camera preview with a quick-access library strip, video recording, and session history (REUSE).
public struct UnifiedCreatorView: View {
    @State private var viewModel: UnifiedCreatorViewModel
    @Environment(\.scenePhase) private var scenePhase
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: UnifiedCreatorViewModel(
            configuration: configuration,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.authStatus == .denied || viewModel.authStatus == .restricted {
                PermissionNeededView(type: .library)
                    .transition(.opacity)
            } else {
                GeometryReader { proxy in
                    let viewWidth = proxy.size.width
                    let maxViewfinderHeight = proxy.size.height * 0.48
                    let viewfinderHeight = min(viewWidth, maxViewfinderHeight)
                    let bottomHeight = proxy.size.height - viewfinderHeight
                    
                    VStack(spacing: 0) {
                        viewfinderArea
                            .frame(width: viewWidth, height: viewfinderHeight)
                            .clipped()
                        
                        bottomPanel
                            .frame(width: viewWidth, height: bottomHeight)
                            .clipped()
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .transition(.opacity)
            }
            
            // Exit Button (Always available to escape)
            if viewModel.authStatus != .notDetermined {
                exitButton
            }
        }
        .background(Color.black)
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
                viewModel.setPreviewAsset(first)
            }
        }
        .onChange(of: viewModel.selection) { _, items in
            viewModel.handleSystemPickerSelection(items)
        }
        .animation(.spring(), value: viewModel.authStatus)
    }
    
    // MARK: - Viewfinder Area
    
    private var viewfinderArea: some View {
        ZStack {
            Group {
                if viewModel.authStatus == .notDetermined {
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
            switch viewModel.selectedMode {
            case .library:
                libraryViewfinder
            case .reuse:
                historyViewfinder
            case .photo:
                if viewModel.cameraService.isSourceReady {
                    CameraPreviewView()
                } else {
                    // Fallback if camera specific permission is missing
                    PermissionNeededView(type: .camera)
                }
            }
            
            // Mode Overlay (Recording indicator)
            if viewModel.isRecording {
                recordingIndicator
            }
        }
        .animation(nil, value: viewModel.selectedMode)
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
                viewModel.setup()
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
            if viewModel.recentAssets.isEmpty {
                emptyLibraryState
            } else {
                LibraryPreviewer(asset: viewModel.previewAsset ?? viewModel.recentAssets.first)
                    .onTapGesture { viewModel.toggleSystemPicker() }
            }
        }
    }
    
    private var historyViewfinder: some View {
        Group {
            if viewModel.history.isEmpty {
                emptyHistoryState
            } else {
                HistoryPreviewer(item: viewModel.previewHistoryItem ?? viewModel.history.first)
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
                Button("Open Library") { viewModel.toggleSystemPicker() }
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
                Button(action: { viewModel.onCancelAction() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(20)
                }
                Spacer()
            }
            .padding(.top, 40)
            Spacer()
        }
    }
    
    // MARK: - Bottom Panel Area
    
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if viewModel.authStatus == .notDetermined {
                Color.black
            } else if viewModel.selectedMode == .library {
                if viewModel.configuration.style.gridStyle.galleryMode == .grid {
                    AssetGridView(
                        configuration: viewModel.configuration,
                        onAssetTap: { asset in
                            viewModel.setPreviewAsset(asset)
                        },
                        onSelectionComplete: { assets in
                            viewModel.handleAssets(assets)
                        }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    nativeLibraryStrip
                        .padding(.top, 16)
                }
            } else if viewModel.selectedMode == .photo {
                ZStack(alignment: .top) {
                    verticalLibraryGrid
                        .opacity(0.6) // Content-filled background
                    
                    VStack(spacing: 0) {
                        pullUpHandle
                        
                        stripHeader
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        zoomDial
                            .padding(.bottom, 8)
                    }
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.8), .black.opacity(0.2), .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else if viewModel.selectedMode == .reuse {
                reuseHistoryStrip
            }
            
            Spacer(minLength: 0)
            
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
            Text(viewModel.selectedMode == .reuse ? "PICKED HISTORY" : "RECENT LIBRARY")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)
            Spacer()
            if viewModel.selectedMode == .library {
                adaptiveLibraryButton
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var adaptiveLibraryButton: some View {
        Group {
            if viewModel.authStatus == .limited {
                Button("MANAGE") { viewModel.openLimitedPicker() }
            } else if viewModel.authStatus == .authorized {
                Button("SELECT") { viewModel.toggleSystemPicker() }
            } else if viewModel.authStatus == .denied {
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
                if viewModel.selectedMode == .reuse {
                    historyStrip
                } else {
                    libraryStrip
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 70)
    }
    
    private var pullUpHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(width: 40, height: 4)
            .padding(.top, 8)
    }
    
    private var verticalLibraryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                ForEach(viewModel.recentAssets, id: \.localIdentifier) { asset in
                    AssetThumbnailView(asset: asset) { _ in
                        viewModel.setPreviewAsset(asset)
                    }
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(viewModel.configuration.style.accentColor, lineWidth: viewModel.previewAsset?.localIdentifier == asset.localIdentifier ? 3 : 0)
                    )
                }
            }
        }
    }
    
    private var libraryStrip: some View {
        ForEach(viewModel.recentAssets, id: \.localIdentifier) { asset in
            AssetThumbnailView(asset: asset) { _ in
                viewModel.setPreviewAsset(asset)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(viewModel.configuration.style.accentColor, lineWidth: viewModel.previewAsset?.localIdentifier == asset.localIdentifier ? 3 : 0)
            )
        }
    }
    
    private var zoomDial: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.cameraService.availableZoomFactors, id: \.self) { factor in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        viewModel.cameraService.setZoom(factor)
                    }
                }) {
                    Text(String(format: "%.1fx", factor))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.cameraService.zoomFactor == factor ? .white : .white) // Keep white for premium look
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(viewModel.cameraService.zoomFactor == factor ? viewModel.configuration.style.accentColor : Color.white.opacity(0.15))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var historyStrip: some View {
        ForEach(viewModel.history, id: \.id) { item in
            Image(uiImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 70, height: 70)
                .cornerRadius(6)
                .clipped()
                .onTapGesture { viewModel.setPreviewHistoryItem(item) }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.configuration.style.accentColor, lineWidth: viewModel.previewHistoryItem?.id == item.id ? 3 : 0)
                )
        }
    }
    
    private var shutterAndModeBar: some View {
        VStack(spacing: 20) {
            HStack {
                galleryShortcut
                    .frame(width: 48, height: 48)
                
                Spacer()
                
                Button(action: { viewModel.onShutterTab() }) {
                    shutterView
                }
                .buttonStyle(ScaleButtonStyle())
                
                Spacer()
                
                Group {
                    if viewModel.selectedMode == .photo {
                        Button(action: { viewModel.flipCamera() }) {
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
            
            HStack(spacing: 24) {
                ForEach([UnifiedCreatorViewModel.CreatorMode.library, .reuse, .photo], id: \.self) { mode in
                    ModeButton(
                        title: viewModel.modeTitle(mode),
                        isSelected: viewModel.selectedMode == mode,
                        accentColor: viewModel.configuration.style.accentColor,
                        action: { viewModel.selectMode(mode) }
                    )
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
            
            if viewModel.selectedMode == .library || viewModel.selectedMode == .reuse {
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
    
    private var galleryShortcut: some View {
        Button(action: { viewModel.galleryShortcutAction() }) {
            ZStack {
                if (viewModel.authStatus == .authorized || viewModel.authStatus == .limited), let firstAsset = viewModel.recentAssets.first {
                    AssetThumbnailView(asset: firstAsset) { _ in }
                        .allowsHitTesting(false)
                        .frame(width: 48, height: 48)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.6), lineWidth: 2))
                } else if viewModel.authStatus == .denied || viewModel.authStatus == .restricted {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2))
                        .overlay(Image(systemName: "lock.fill").foregroundColor(.white.opacity(0.4)))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2))
                        .overlay(Image(systemName: "photo").foregroundColor(.white.opacity(0.4)))
                }
            }
        }
        .disabled(viewModel.authStatus == .notDetermined)
    }
}

// Helpers from original code



