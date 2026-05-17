import SwiftUI
import Photos
import PhotosUI

/// The picker shell that replaces the monolithic `UnifiedCreatorView`.
///
/// Holds ONLY its own `PickerViewModel`. Every subview is self-contained
/// (instantiates its own VM internally). Cross-cutting state flows DOWN as
/// View parameters; events flow UP via callbacks routed to `viewModel`
/// methods. No view-model references another view-model — and no view
/// reaches through `viewModel` to a child VM.
public struct PickerView: View {
    @State private var viewModel: PickerViewModel
    @Environment(\.scenePhase) private var scenePhase

    /// Binding driven by SwiftUI `PhotosPicker` instances inside the
    /// gallery shortcut + previewer-tap path. On change → `processPicked`.
    @State private var systemPickerSelection: [PhotosPickerItem] = []

    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: PickerViewModel(
            configuration: configuration,
            onCompletion: onCompletion,
            onCancel: onCancel
        ))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                layoutContent(in: proxy.size)
            }
            .ignoresSafeArea(.container, edges: .top)

            // 🛡️ Sovereign Layer: Always on Top
            ExitButton { viewModel.handleCancel() }
                .zIndex(100)
        }
        .background(Color.black)
        .task {
            // Bootstrap the initial album so AssetGridView's binding
            // observer can load its first batch of assets.
            await viewModel.loadInitialAlbumIfNeeded()
            // Resolve the gallery-shortcut thumbnail eagerly. Covers the
            // common case where the modifier's prewarm finished before this
            // view mounted (recentAssets is already populated) — onChange
            // won't fire for that, so we need an initial pass here.
            await viewModel.loadGalleryThumbIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { viewModel.refreshAuthIfNeeded() }
        }
        .onChange(of: viewModel.recentAssets) { _, newValue in
            // Auto-populate library preview from the first recent the moment
            // recents arrive (parity with the original onChange in UnifiedCreatorView).
            if viewModel.previewAsset == nil, let first = newValue.first {
                viewModel.setPreview(first)
            }
            // Refresh the gallery-shortcut thumbnail whenever recents shift
            // (library change observer, limited-access pick set updates).
            Task { await viewModel.loadGalleryThumbIfNeeded() }
        }
        .onChange(of: systemPickerSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await viewModel.processPicked(items)
                // Reset so the next pick of the same item still fires
                // .onChange. SwiftUI dedupes identical values, so without
                // this reset, picking the same photo twice in a row would
                // not trigger a second processing pass.
                systemPickerSelection = []
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func layoutContent(in size: CGSize) -> some View {
        let viewfinderHeight = min(size.width, size.height * 0.48)
        let bottomHeight = size.height - viewfinderHeight

        VStack(spacing: 0) {
            viewfinderSection
                .frame(width: size.width, height: viewfinderHeight)
                .clipped()

            bottomSection
                .frame(width: size.width, height: bottomHeight)
                .clipped()
        }
    }

    // MARK: - Viewfinder section (top)

    @ViewBuilder
    private var viewfinderSection: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if viewModel.authStatus == .notDetermined {
                    OnboardingPromptView(
                        title: viewModel.configuration.style.onboardingTitle,
                        accentColor: viewModel.configuration.style.accentColor,
                        onGetStarted: { viewModel.requestPermissions() }
                    )
                } else {
                    ViewfinderArea(
                        mode: viewModel.selectedMode,
                        previewAsset: viewModel.previewAsset,
                        previewHistoryItem: viewModel.previewHistoryItem,
                        history: viewModel.history,
                        accentColor: viewModel.configuration.style.accentColor,
                        selectionLimit: viewModel.configuration.selectionLimit,
                        pickerSelection: $systemPickerSelection,
                        onLimitedTap: { viewModel.handleGalleryShortcut() },
                        onAuthorizedEmptyStateFallback: { viewModel.openSystemPicker() }
                    )
                }
            }
            .transition(.opacity)
            .animation(.spring(), value: viewModel.authStatus)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
    }

    // MARK: - Bottom panel section

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 0) {
            if viewModel.authStatus != .notDetermined {
                stripHeader

                mainContentArea
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

            ShutterAndModeBarView(
                mode: viewModel.selectedMode,
                accentColor: viewModel.configuration.style.accentColor,
                authStatus: viewModel.authStatus,
                firstAssetImage: viewModel.galleryThumbImage,
                selectionLimit: viewModel.configuration.selectionLimit,
                pickerSelection: $systemPickerSelection,
                onShutter: { viewModel.handleShutter() },
                onFlipCamera: { viewModel.flipCamera() },
                onSelectMode: { viewModel.selectMode($0) },
                onGalleryShortcut: { viewModel.handleGalleryShortcut() }
            )
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var gridAndZoomArea: some View {
        ZStack(alignment: .bottom) {
            AssetGridView(
                configuration: viewModel.configuration,
                currentAlbum: $viewModel.currentAlbum,   // ← binding (single source of truth)
                selectedMode: viewModel.selectedMode,
                history: viewModel.history,
                onAssetTap: { gridAsset in
                    viewModel.handleGridAssetTap(gridAsset)
                },
                onSelectionChange: { assets in
                    viewModel.updateSelection(assets)
                }
            )

            if viewModel.selectedMode == .photo {
                ZoomDialView(
                    accentColor: viewModel.configuration.style.accentColor,
                    availableZoomFactors: viewModel.availableZoomFactors,
                    currentZoom: viewModel.zoomFactor,
                    onSelectZoom: { viewModel.setZoom($0) }
                )
                .padding(.bottom, 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Strip header (album dropdown + NEXT button)

    @ViewBuilder
    private var stripHeader: some View {
        HStack {
            headerTitle
            Spacer()
            nextButton
        }
        .frame(height: 44) // Fixed height to prevent vertical "bounce" during mode switches.
        .padding(.horizontal, 20)
        .background(viewModel.configuration.style.toolbarColor)
    }

    @ViewBuilder
    private var headerTitle: some View {
        if viewModel.selectedMode == .reuse {
            Text("History")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        } else if viewModel.configuration.style.gridStyle.showAlbumPicker {
            // Always render the dropdown when the configuration allows it.
            // AlbumDropdownMenu handles both the loading state (faded + spinner)
            // and the loaded state (chevron + interactive menu) internally —
            // no `currentAlbum != nil` gate needed at this layer (eliminates
            // the "tap-on-non-interactive-Text" window that existed before).
            AlbumDropdownMenu(
                albums: viewModel.albums,
                currentAlbum: $viewModel.currentAlbum
            )
        } else {
            Text(viewModel.currentAlbum?.title ?? "Recents")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var nextButton: some View {
        let count = viewModel.selectionCount
        let limit = viewModel.configuration.selectionLimit
        let label = count > 0 ? "NEXT (\(count)/\(limit))" : "NEXT"

        return Button(label) {
            viewModel.handleNextTapped()
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
