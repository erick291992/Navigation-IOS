import SwiftUI
import PhotosUI
import Photos
import AVFoundation

/// The "Gold Standard" entry point for media creation.
/// Merges a live camera preview with a quick-access library strip, video recording, and session history (REUSE).
public struct UnifiedCreatorView: View {
    @State private var viewModel: UnifiedCreatorViewModel
    @State private var isZoomExpanded = false
    // Lazy-mount gate for CameraPreviewView. The UIViewRepresentable's first
    // mount triggers ~50ms of UIKit/AVFoundation bridging (creating
    // VideoPreviewUIView + binding the AVCaptureVideoPreviewLayer to the
    // session). Deferring this for ~32ms lets the rest of the picker shell
    // (header, mode buttons, shutter, grid skeleton, etc.) appear immediately
    // when UnifiedCreatorView mounts — the camera area shows a small
    // ProgressView for that brief window. After the gate flips, CameraPreviewView
    // stays mounted for the rest of the picker's lifetime (so subsequent
    // mode-switches into photo mode are instant).
    @State private var isCameraMounted = false
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
    
    private func calculateItemSize(for width: CGFloat) -> CGFloat {
        let style = viewModel.configuration.style.gridStyle
        let columns = CGFloat(style.columnCount)
        let spacing = style.spacing
        return (width - (spacing * (columns - 1))) / columns
    }
    
    public var body: some View {
        rootContent
            .task {
                // One-shot lazy-mount of CameraPreviewView. See the
                // `isCameraMounted` declaration above for the rationale.
                // .task auto-cancels if the view disappears within the 32ms
                // window, so a quick open-then-close doesn't trigger the
                // UIKit bridging work.
                guard !isCameraMounted else { return }
                try? await Task.sleep(for: .milliseconds(32))
                isCameraMounted = true
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.updateAuth()
                }
            }
            .onChange(of: viewModel.recentAssets) { (oldValue: [PHAsset], newValue: [PHAsset]) in
                if viewModel.previewAsset == nil, let first = newValue.first {
                    viewModel.setPreviewGridAsset(.phAsset(first))
                }
            }
        // Note: `.animation(value: authStatus)` previously lived here on the
        // whole body, which prepared animation contexts for every subtree on
        // every body re-eval. It's now scoped onto `viewfinderArea`'s inner
        // Group where the auth-driven content swap actually happens.
    }

    private var rootContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { proxy in
                layoutContent(with: proxy)
            }
            .ignoresSafeArea(.container, edges: .top)
            
            // 🛡️ Sovereign Layer: Always on Top
            exitButton
                .zIndex(100)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func layoutContent(with proxy: GeometryProxy) -> some View {
        let viewWidth = proxy.size.width
        let maxViewfinderHeight = proxy.size.height * 0.48
        let viewfinderHeight = min(viewWidth, maxViewfinderHeight)
        let bottomHeight = proxy.size.height - viewfinderHeight
        let panelItemSize = calculateItemSize(for: viewWidth)
        
        VStack(spacing: 0) {
            viewfinderArea
                .frame(width: viewWidth, height: viewfinderHeight)
                .clipped()
            
            bottomPanel(itemSize: panelItemSize)
                .frame(width: viewWidth, height: bottomHeight)
                .clipped()
        }
    }

    // MARK: - Viewfinder Area
    
    private var viewfinderArea: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if viewModel.authStatus == .notDetermined {
                    onboardingView
                } else {
                    mainViewfinderContent
                }
            }
            .transition(.opacity)
            .animation(.spring(), value: viewModel.authStatus)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
    }
    
    private var mainViewfinderContent: some View {
        ZStack {
            // 1. Photo Viewfinder (Persistent & Warm, after lazy gate)
            if viewModel.cameraService.isSourceReady {
                if isCameraMounted {
                    CameraPreviewView()
                        .opacity(viewModel.selectedMode == .photo ? 1 : 0)
                }
                // Before isCameraMounted flips: nothing renders here. The
                // black background from .background(Color.black) on viewfinderArea
                // shows through, and the spinner below provides the loading hint.
            } else {
                PermissionNeededView(type: .camera, accentColor: viewModel.configuration.style.accentColor)
                    .opacity(viewModel.selectedMode == .photo ? 1 : 0)
            }

            // 1a. Camera loading spinner — shown while either:
            //   - CameraPreviewView hasn't been lazy-mounted yet (32ms window), OR
            //   - The AVCaptureSession isn't yet producing frames
            // Both conditions disappear automatically as state propagates.
            if viewModel.selectedMode == .photo
                && viewModel.cameraService.isSourceReady
                && (!isCameraMounted || !viewModel.cameraService.isSessionRunning) {
                ProgressView()
                    .tint(.white.opacity(0.7))
            }

            // 2. Library Viewfinder
            if viewModel.selectedMode == .library {
                if viewModel.authStatus == .denied || viewModel.authStatus == .restricted {
                    PermissionNeededView(type: .library, accentColor: viewModel.configuration.style.accentColor)
                } else if viewModel.recentAssets.isEmpty
                    && (viewModel.authStatus == .authorized || viewModel.authStatus == .limited) {
                    // Library loading spinner — disappears when PhotoKit
                    // propagates recentAssets via @Observable.
                    ProgressView()
                        .tint(.white.opacity(0.7))
                } else {
                    libraryViewfinder
                }
            }

            // 3. Reuse Viewfinder
            if viewModel.selectedMode == .reuse {
                historyViewfinder
            }

            // Mode Overlay (Recording indicator)
            if viewModel.isRecording {
                recordingIndicator
            }
        }
    }
    
    private var onboardingView: some View {
        VStack(spacing: 30) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(viewModel.configuration.style.accentColor)
            
            VStack(spacing: 12) {
                Text(viewModel.configuration.style.onboardingTitle)
                    .font(.title.bold())
                Text("To start creating elite content, we need access to your library and camera.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.setup()
            }) {
                Text("GET STARTED")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(viewModel.configuration.style.accentColor)
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
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.toggleSystemPicker()
                    }
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
                Button("Open Library") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if viewModel.authStatus == .limited {
                        viewModel.openLimitedPicker()
                    } else {
                        viewModel.toggleSystemPicker()
                    }
                }
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
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.onCancelAction()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.3)) // Subtle background for contrast
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.5), radius: 10) // 🛡️ Visible on any background
                }
                .padding(20)
                .contentShape(Rectangle())
                
                Spacer()
            }
            .padding(.top, 44) // Align with modern iPhone status bars
            Spacer()
        }
    }
    
    // MARK: - Bottom Panel Area
    
    @ViewBuilder
    private func bottomPanel(itemSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            if viewModel.authStatus != .notDetermined {
                VStack(spacing: 0) {
                    stripHeader
                    mainContentArea
                }
            } else {
                Color.black
            }
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContentArea: some View {
        VStack(spacing: 0) {
            gridAndZoomArea
                .background(Color.black)
            
            Spacer(minLength: 0)
            
            shutterAndModeBar
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
    }

    private var gridAndZoomArea: some View {
        ZStack(alignment: .bottom) {
            AssetGridView(
                configuration: viewModel.configuration,
                viewModel: viewModel.gridViewModel,
                showHeader: false,
                onAssetTap: { asset in
                    viewModel.setPreviewGridAsset(asset)
                },
                onSelectionComplete: { assets in
                    viewModel.handleGridAssets(assets)
                }
            )
            // No opacity toggle - keep grid as a persistent base layer for a unified feel
            
            if viewModel.selectedMode == .photo {
                zoomDial
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private var stripHeader: some View {
        HStack {
            headerTitle
            Spacer()
            nextButton
        }
        .frame(height: 44) // Fixed height to prevent vertical "bounce" during mode switches
        .padding(.horizontal, 20)
        .background(viewModel.configuration.style.toolbarColor)
    }

    @ViewBuilder
    private var headerTitle: some View {
        if viewModel.selectedMode == .reuse {
            Text("History")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        } else {
            if viewModel.configuration.style.gridStyle.showAlbumPicker && viewModel.gridViewModel.state.currentAlbum != nil {
                AlbumDropdownMenu(viewModel: viewModel.gridViewModel)
            } else {
                Text(viewModel.gridViewModel.state.currentAlbum?.title ?? "Recents")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private var nextButton: some View {
        Group {
            let count = viewModel.gridViewModel.state.selectedAssets.count
            let limit = viewModel.gridViewModel.selectionLimit
            let label = count > 0 ? "NEXT (\(count)/\(limit))" : "NEXT"
            
            Button(label) {
                viewModel.handleGridAssets(viewModel.gridViewModel.state.selectedAssets)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(viewModel.configuration.style.accentColor)
            .cornerRadius(12)
            .disabled(count == 0)
            .opacity(count == 0 ? 0.3 : 1.0)
            .animation(.spring(), value: count)
        }
    }
    
    private var zoomDial: some View {
        HStack(spacing: 6) {
            if isZoomExpanded {
                ForEach(viewModel.cameraService.availableZoomFactors, id: \.self) { factor in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.cameraService.setZoom(factor)
                        isZoomExpanded = false
                    }) {
                        Text(String(format: "%.1fx", factor))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(viewModel.cameraService.zoomFactor == factor ? viewModel.configuration.style.accentColor : .white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(viewModel.cameraService.zoomFactor == factor ? .white.opacity(0.2) : .clear))
                    }
                }
            } else {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isZoomExpanded = true
                    }
                }) {
                    Text(String(format: "%.1f", viewModel.cameraService.zoomFactor))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.configuration.style.accentColor)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(isZoomExpanded ? 4 : 0)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isZoomExpanded)
    }
    
    @ViewBuilder
    private var shutterAndModeBar: some View {
        VStack(spacing: 20) {
            shutterRow
            modeRow
        }
    }
    
    private var shutterRow: some View {
        ZStack {
            // 1. Gallery Shortcut (Left)
            HStack {
                galleryShortcut
                    .frame(width: 48, height: 48)
                Spacer()
            }
            
            // 2. Shutter Button (Dead Center)
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.onShutterTab()
            }) {
                shutterView
            }
            .buttonStyle(ScaleButtonStyle())
            
            // 3. Flip Camera (Right)
            HStack {
                Spacer()
                if viewModel.selectedMode == .photo {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.flipCamera()
                    }) {
                        Circle().fill(.white.opacity(0.1)).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.white))
                    }
                    .frame(width: 48, height: 48)
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
            }
        }
        .padding(.horizontal, 30)
    }
    
    private var modeRow: some View {
        HStack(spacing: 24) {
            ForEach([UnifiedCreatorViewModel.CreatorMode.library, .reuse, .photo], id: \.self) { mode in
                ModeButton(
                    title: viewModel.modeTitle(mode),
                    isSelected: viewModel.selectedMode == mode,
                    accentColor: viewModel.configuration.style.accentColor,
                    action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectMode(mode)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
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
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.galleryShortcutAction()
        }) {
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
                } else if viewModel.authStatus == .authorized || viewModel.authStatus == .limited {
                    // Authorized but recentAssets hasn't propagated yet —
                    // show a small spinner instead of the generic photo icon
                    // so the user knows this square is loading, not empty.
                    // Disappears the moment `recentAssets.first` returns
                    // a value (via the @Observable cascade from PhotoKitService).
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 2))
                        .overlay(ProgressView().tint(.white.opacity(0.5)))
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



