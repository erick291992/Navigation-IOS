import SwiftUI
import Photos

/// "Elite Picker Style B"
/// A premium alternative layout demonstrating how developers can build
/// their own top-tier UIs on top of the Tier 3 engine.
struct AdvancedPickerExampleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AdvancedPickerExampleViewModel()
    @State private var rejectionTrigger = 0

    // High-density premium edge-to-edge grid (1px spacing like Instagram)
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Premium Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("Select Media")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("Select up to \(viewModel.maxSelection)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Invisible spacer for centering
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.95))
                
                // MARK: - Processed Results Preview
                if !viewModel.finishedItems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.finishedItems) { item in
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 70)
                    .background(Color(uiColor: .systemGray6).opacity(0.2))
                }
                
                // MARK: - Premium Grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(viewModel.gridViewModel.assetGridState.assets, id: \.id) { asset in
                            let isSelected = viewModel.gridViewModel.assetGridState.selectedAssets.contains(asset)
                            let selectionIndex = viewModel.gridViewModel.assetGridState.selectedAssets.firstIndex(of: asset)
                            
                            ZStack(alignment: .topTrailing) {
                                // Image with scale-down bounce when selected
                                AsyncFlexibleAssetView(
                                    id: asset.id,
                                    initialImage: viewModel.gridViewModel.thumbnail(for: asset),
                                    loadAsync: { await viewModel.gridViewModel.requestThumbnail(for: asset) }
                                )
                                    .scaleEffect(isSelected ? 0.95 : 1.0)
                                
                                // Sleek selection badges
                                if let index = selectionIndex {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Text("\(index + 1)")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.black)
                                        )
                                        .padding(6)
                                        // Prevents the badge from scaling down with the image
                                        .scaleEffect(isSelected ? 1.05 : 1.0)
                                } else {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                                        .frame(width: 22, height: 22)
                                        .padding(6)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isSelected && viewModel.gridViewModel.assetGridState.selectedAssets.count >= viewModel.maxSelection {
                                    rejectionTrigger += 1
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectAsset(asset)
                                }
                            }
                        }
                    }
                }
            }
            
            // MARK: - Floating Action Bar
            if !viewModel.gridViewModel.assetGridState.selectedAssets.isEmpty {
                VStack {
                    Spacer()
                    Button(action: viewModel.processSelectedAssets) {
                        HStack {
                            Text("Continue")
                                .font(.system(size: 16, weight: .bold))
                            
                            Spacer()
                            
                            Text("\(viewModel.gridViewModel.assetGridState.selectedAssets.count)")
                                .font(.system(size: 14, weight: .black))
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(30)
                        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarHidden(true)
        // Selection-aware haptic: fires when the array actually changes.
        // At-limit no-op taps fire `.error` via rejectionTrigger instead.
        .sensoryFeedback(.selection, trigger: viewModel.gridViewModel.assetGridState.selectedAssets)
        .sensoryFeedback(.error, trigger: rejectionTrigger)
        // MARK: - Modals
        .sheet(isPresented: Binding(
            get: { viewModel.flowState != .idle },
            set: { if !$0 { viewModel.cancelFlow() } }
        )) {
            if case .cropping(let index, _) = viewModel.flowState {
                NavigationStack {
                    CropView(
                        item: viewModel.itemsToCrop[index],
                        crop: viewModel.cropMode,
                        onDone: { result in
                            viewModel.didFinishCrop(result, at: index)
                        },
                        onCancel: {
                            viewModel.cancelFlow()
                        }
                    )
                }
            } else if viewModel.flowState == .processing {
                VStack(spacing: 20) {
                    ProgressView()
                        .tint(.green)
                    Text("Processing engine...")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

/// Pure presentational thumbnail view for the demo's edge-to-edge grid.
/// Same closure pattern as `AssetThumbnailCell`: parent provides `initialImage`
/// (synchronous cache peek) + `loadAsync` (async fetch); cell paints
/// `displayImage = asyncLoaded ?? initialImage` and uses `.task(id:)` so
/// cell recycles auto-cancel the in-flight load.
struct AsyncFlexibleAssetView: View {
    let id: String
    let initialImage: UIImage?
    let loadAsync: () async -> UIImage?

    @State private var asyncLoaded: UIImage?
    private var displayImage: UIImage? { asyncLoaded ?? initialImage }

    var body: some View {
        Group {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                    .overlay(ProgressView().tint(.white).opacity(0.3))
            }
        }
        .task(id: id) {
            guard displayImage == nil else { return }
            asyncLoaded = await loadAsync()
        }
    }
}
