import SwiftUI
import Photos
import PhotosUI

/// Composed bottom-of-shell control: shutter row (gallery shortcut +
/// shutter button + flip-camera) plus mode row (Library / Reuse / Photo).
///
/// Fully dumb — receives all state as props and fires callbacks for events.
/// Parent (PickerView) decides what each event means based on the active mode.
struct ShutterAndModeBarView: View {
    let mode: PickerMode
    let accentColor: Color
    let authStatus: PHAuthorizationStatus
    /// Pre-resolved bitmap for the gallery shortcut thumb. Parent loads it
    /// once via `PickerViewModel.loadGalleryThumbIfNeeded()` and passes
    /// the value down — the leaf stays a pure renderer.
    let firstAssetImage: UIImage?
    let selectionLimit: Int
    /// Driven by `PhotosPicker` when authStatus is `.authorized`. Parent
    /// observes via `.onChange` and routes to `processPicked(_:)`.
    @Binding var pickerSelection: [PhotosPickerItem]
    let onShutter: () -> Void
    let onFlipCamera: () -> Void
    let onSelectMode: (PickerMode) -> Void
    /// Limited-access path AND denied/restricted path. The authorized
    /// path is handled by `GalleryShortcutButton`'s internal
    /// `PhotosPicker` — no callback needed for it.
    let onGalleryShortcut: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            shutterRow
            modeRow
        }
    }

    private var shutterRow: some View {
        ZStack {
            // 1. Gallery Shortcut (Left)
            HStack {
                GalleryShortcutButton(
                    authStatus: authStatus,
                    image: firstAssetImage,
                    selectionLimit: selectionLimit,
                    pickerSelection: $pickerSelection,
                    onLimitedOrDeniedTap: onGalleryShortcut
                )
                .frame(width: 48, height: 48)
                Spacer()
            }

            // 2. Shutter Button (Dead Center)
            ShutterButton(
                mode: mode == .photo ? .capture : .submit,
                action: onShutter
            )

            // 3. Flip Camera (Right) — only in photo mode.
            HStack {
                Spacer()
                if mode == .photo {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onFlipCamera()
                    }) {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.white)
                            )
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
            ForEach([PickerMode.library, .reuse, .photo], id: \.self) { mode in
                ModeButton(
                    title: mode.title,
                    isSelected: self.mode == mode,
                    accentColor: accentColor,
                    action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelectMode(mode)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}
