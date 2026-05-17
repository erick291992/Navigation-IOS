import SwiftUI
import Photos

// These components are used across the UniversalMediaPicker demos and internal views.

struct MediaPickerResultGallery: View {
    let items: [MediaItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Picked Results")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Image(uiImage: item.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 80)
        }
    }
}

struct MediaPickerButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            MediaPickerButtonLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

struct MediaPickerButtonLabel: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                )
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle()) // Ensure entire area is tappable
    }
}

struct MediaPickerNavCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(color)
                        )
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

struct ModeButton: View {
    let title: String
    let isSelected: Bool
    var accentColor: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                    .tracking(1.2)
                
                Circle()
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct PermissionNeededView: View {
    public enum PermissionType { case library, camera }
    public let type: PermissionType
    public var accentColor: Color
    
    public init(type: PermissionType, accentColor: Color = .blue) {
        self.type = type
        self.accentColor = accentColor
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: type == .library ? "photo.on.rectangle.angled" : "camera.shutter.button")
                .font(.system(size: 80))
                .foregroundStyle(accentColor)
            
            VStack(spacing: 8) {
                Text(type == .library ? "Allow Access to Photos" : "Allow Access to Camera")
                    .font(.title2.bold())
                Text(type == .library ? "This lets you share photos from your library." : "This lets you take photos and record videos.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.headline.bold())
            .foregroundColor(accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundColor(.white)
    }
}

/// Pure presentational previewer — knows nothing about PhotoKit or
/// ThumbnailCache. The parent (LibraryViewfinderView) wires it to
/// LibraryViewfinderViewModel, which routes through PhotoKitService.
///
/// Two image inputs (same shape as AssetThumbnailCell):
/// - `initialImage`: parent-provided synchronous read (cache peek). Paints
///   instantly when the displayed asset changes so the user sees the new
///   image on the same frame as their tap.
/// - `loadAsync`: parent-provided async upgrade loader. Fetches the
///   high-res version (1000pt) and replaces `initialImage` when it arrives.
///   Unlike the grid cell, this ALWAYS runs even when `initialImage`
///   exists — the cached image is smaller (cell-sized) and we want to
///   upgrade to the previewer's larger size.
///
/// `assetID` is the `.task(id:)` key. When it changes (user taps a
/// different grid cell), SwiftUI cancels the in-flight upgrade and starts
/// a new one against the new asset; the local `@State asyncLoaded` resets
/// so `initialImage` (the new asset's cache peek) paints first.
struct LibraryPreviewer: View {
    let assetID: String?
    let initialImage: UIImage?
    let loadAsync: (() async -> UIImage?)?

    @State private var asyncLoaded: UIImage?
    private var displayImage: UIImage? { asyncLoaded ?? initialImage }

    var body: some View {
        ZStack {
            if let image = displayImage {
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
        .task(id: assetID) {
            // Reset so the new asset's `initialImage` (cached peek) paints
            // immediately instead of leaving the previous tap's high-res
            // image hanging while the new fetch runs.
            asyncLoaded = nil
            guard let loadAsync else { return }
            if let loaded = await loadAsync() {
                asyncLoaded = loaded
            }
        }
    }
}

struct HistoryPreviewer: View {
    let item: MediaItem?
    
    var body: some View {
        ZStack {
            if let item = item {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
            }
        }
    }
}
