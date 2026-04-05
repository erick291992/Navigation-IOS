import SwiftUI
import PhotosUI
import AVFoundation

/// The "Gold Standard" entry point for media creation.
/// Merges a live camera preview with a quick-access library strip and video recording.
public struct UnifiedPickerView: View {
    let configuration: MediaPickerConfiguration
    let onCompletion: ([MediaItem]) -> Void
    let onCancel: () -> Void
    
    // Services
    @StateObject private var cameraService = CameraService.shared
    @StateObject private var photoKit = PhotoKitService.shared
    
    // Internal States
    @State private var selection: [PhotosPickerItem] = []
    @State private var isShowingSystemPicker = false
    @State private var selectedMode: CreatorMode = .photo
    @State private var isRecording = false
    @State private var previewAsset: PHAsset?
    @State private var previewImage: UIImage?
    
    enum CreatorMode {
        case library, photo, video
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Top Viewfinder / Previewer
                ZStack {
                    if selectedMode == .library {
                        // Library Preview: Show the large version of the selected asset
                        LibraryPreviewer(asset: previewAsset ?? photoKit.recentAssets.first)
                            .transition(.opacity)
                    } else {
                        // Camera Feed (Photo/Video)
                        CameraPreviewView()
                            .transition(.opacity)
                    }
                    
                    // Mode Overlay (Recording indicator)
                    if isRecording {
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
                    
                    // Exit Button
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
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped()
                
                // MARK: - Bottom Control Panel
                VStack(spacing: 20) {
                    // Recent Assets Strip
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RECENT")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1.5)
                            Spacer()
                            Button("ALL PHOTOS") {
                                isShowingSystemPicker = true
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(photoKit.recentAssets, id: \.localIdentifier) { asset in
                                    AssetThumbnailView(asset: asset) { image in
                                        if selectedMode == .library {
                                            self.previewAsset = asset
                                        } else {
                                            handleSelection(image)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.blue, lineWidth: previewAsset?.localIdentifier == asset.localIdentifier ? 3 : 0)
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 70)
                    }
                    .padding(.top, 16)
                    
                    // MAIN ACTION AREA
                    VStack(spacing: 24) {
                        // Shutter
                        Button(action: onShutterTab) {
                            shutterView
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        // Mode Switcher
                        HStack(spacing: 30) {
                            ForEach([CreatorMode.library, .photo, .video], id: \.self) { mode in
                                ModeButton(title: modeTitle(mode), isSelected: selectedMode == mode) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedMode = mode
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .background(Color.black)
                .frame(height: 340)
            }
        }
        .onAppear {
            photoKit.fetchRecentAssets()
            cameraService.setup()
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
    
    // MARK: - Actions
    
    private func onShutterTab() {
        switch selectedMode {
        case .photo:
            capturePhoto()
        case .video:
            toggleRecording()
        case .library:
            if let asset = previewAsset ?? photoKit.recentAssets.first {
                handleAsset(asset)
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
        isRecording.toggle()
        // Here we would call cameraService.start/stopRecording()
    }
    
    private func handleSelection(_ image: UIImage) {
        Task {
            if let item = try? await MediaPickerManager.shared.process(image) {
                onCompletion([item])
            }
        }
    }
    
    private func handleAsset(_ asset: PHAsset) {
        // Fetch high-res image and hand off to completion
        PhotoKitService.shared.loadThumbnail(for: asset, size: CGSize(width: 2000, height: 2000)) { image in
            if let image = image {
                handleSelection(image)
            }
        }
    }
    
    // MARK: - Components
    
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
            } else {
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
    }
    
    private func modeTitle(_ mode: CreatorMode) -> String {
        switch mode {
        case .library: return "LIBRARY"
        case .photo: return "PHOTO"
        case .video: return "VIDEO"
        }
    }
}

// MARK: - Library Previewer
struct LibraryPreviewer: View {
    let asset: PHAsset?
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
                ProgressView().tint(.white)
            }
        }
        .onChange(of: asset) { _, newValue in
            loadImage(for: newValue)
        }
        .onAppear {
            loadImage(for: asset)
        }
    }
    
    private func loadImage(for asset: PHAsset?) {
        guard let asset = asset else { return }
        PhotoKitService.shared.loadThumbnail(for: asset, size: CGSize(width: 1000, height: 1000)) { img in
            self.image = img
        }
    }
}
