import SwiftUI
import PhotosUI
import AVFoundation

/// The "Gold Standard" entry point for media creation.
/// Merges a live camera preview with a quick-access library strip.
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
    @State private var capturedImage: UIImage?
    @State private var selectedMode: CreatorMode = .photo
    
    enum CreatorMode {
        case library, photo, video
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Top 60%: Live Viewfinder
                ZStack {
                    if selectedMode == .photo || selectedMode == .video {
                        CameraPreviewView()
                            .transition(.opacity)
                    } else {
                        // Library mode: Show a blurred or dark background
                        Color.black.overlay(
                            Text("Select From Library")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                        )
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
                
                // MARK: - Bottom 40%: Controls & Library
                VStack(spacing: 24) {
                    // Recent Photos Strip
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RECENT")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1.0)
                            Spacer()
                            Button("ALL PHOTOS") {
                                isShowingSystemPicker = true
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photoKit.recentAssets, id: \.localIdentifier) { asset in
                                    AssetThumbnailView(asset: asset) { image in
                                        handleSelection(image)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 80)
                    }
                    .padding(.top, 20)
                    
                    // Shutter & Mode Bar
                    VStack(spacing: 32) {
                        // Shutter
                        Button(action: capturePhoto) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 68, height: 68)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        // Mode Switcher
                        HStack(spacing: 40) {
                            ModeButton(title: "LIBRARY", isSelected: selectedMode == .library) {
                                withAnimation { selectedMode = .library }
                            }
                            ModeButton(title: "PHOTO", isSelected: selectedMode == .photo) {
                                withAnimation { selectedMode = .photo }
                            }
                            ModeButton(title: "VIDEO", isSelected: selectedMode == .video) {
                                withAnimation { selectedMode = .video }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .background(Color.black)
                .frame(height: 380)
            }
        }
        .onAppear {
            photoKit.fetchRecentAssets()
            if selectedMode != .library {
                cameraService.setup()
            }
        }
        .photosPicker(isPresented: $isShowingSystemPicker, selection: $selection)
        .onChange(of: selection) { _, items in
            if !items.isEmpty {
                Task {
                    let processed = try? await MediaPickerManager.shared.process(items)
                    if let results = processed {
                        onCompletion(results)
                    }
                }
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
    
    private func handleSelection(_ image: UIImage) {
        Task {
            if let item = try? await MediaPickerManager.shared.process(image) {
                onCompletion([item])
            }
        }
    }
}

// MARK: - Helper Views

struct AssetThumbnailView: View {
    let asset: PHAsset
    let onTap: (UIImage) -> Void
    @State private var thumbnail: UIImage?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                    .clipped()
                    .onTapGesture { onTap(thumbnail) }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 80)
            }
        }
        .onAppear {
            PhotoKitService.shared.loadThumbnail(for: asset, size: CGSize(width: 200, height: 200)) { image in
                self.thumbnail = image
            }
        }
    }
}

struct ModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                .tracking(1.5)
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}
