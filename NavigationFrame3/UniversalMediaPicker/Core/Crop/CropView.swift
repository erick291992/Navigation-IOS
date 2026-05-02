import SwiftUI

/// A high-performance, gesture-driven cropping view.
public struct CropView: View {
    public let item: MediaItem
    public let crop: MediaCrop
    public let style: MediaPickerStyle
    public let onDone: (UIImage) -> Void
    public let onCancel: () -> Void
    
    // Multi-image progress (Optional)
    public let subtitle: String?
    public let thumbnails: [UIImage]?
    public let activeIndex: Int?
    public let croppedIndices: Set<Int>
    public let onJump: ((Int) -> Void)?
    
    // MARK: - State
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var currentRatio: MediaCrop = .square
    
    // Freeform specific
    @State private var freeformArea: CGRect?
    
    // View state
    @State private var containerSize: CGSize = .zero
    @State private var isProcessing: Bool = false
    
    public init(
        item: MediaItem, 
        crop: MediaCrop, 
        style: MediaPickerStyle = .default, 
        subtitle: String? = nil,
        thumbnails: [UIImage]? = nil,
        activeIndex: Int? = nil,
        croppedIndices: Set<Int> = [],
        onJump: ((Int) -> Void)? = nil,
        onDone: @escaping (UIImage) -> Void, 
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        self.crop = crop
        self.style = style
        self.subtitle = subtitle
        self.thumbnails = thumbnails
        self.activeIndex = activeIndex
        self.croppedIndices = croppedIndices
        self.onJump = onJump
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundColor(style.accentColor)
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Crop")
                        .font(style.font.bold())
                        .foregroundColor(.white)
                    
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                Button(action: {
                    isProcessing = true
                    renderCroppedImage()
                }) {
                    if isProcessing {
                        ProgressView().tint(style.accentColor)
                    } else {
                        Text(croppedIndices.count == (thumbnails?.count ?? 1) ? "Done" : "Next")
                    }
                }
                .font(style.font.bold())
                .foregroundColor(style.accentColor)
                .disabled(isProcessing)
            }
            .padding()
            .background(style.toolbarColor)
            
            // Cropping Area
            GeometryReader { geo in
                let size = geo.size
                let activeCropArea = getActiveCropArea(for: size)
                
                ZStack {
                    style.backgroundColor.ignoresSafeArea()
                    
                    // The Image layer
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    validateBounds(in: size, cropArea: activeCropArea)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                    validateBounds(in: size, cropArea: activeCropArea)
                                }
                        )
                    
                    // Overlay Mask
                    CropOverlay(
                        cropArea: activeCropArea, 
                        isCircular: currentRatio == .circle, 
                        isFreeform: currentRatio == .freeform,
                        style: style
                    ) { newArea in
                        freeformArea = newArea
                    }
                    
                    // Interaction Layer
                    VStack {
                        Spacer()
                        
                        if let thumbs = thumbnails, thumbs.count > 1 {
                            thumbnailStrip(thumbs)
                                .padding(.bottom, 10)
                        }
                        
                        ratioPicker
                            .padding(.bottom, 20)
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .onAppear {
                    containerSize = size
                    currentRatio = crop
                    isProcessing = false 
                }
                .onChange(of: item) { _, _ in
                    // 🛡️ Ironclad Reset: Force spinner OFF the moment the data swaps
                    isProcessing = false
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                    freeformArea = nil
                }
            }
        }
        .background(style.backgroundColor.ignoresSafeArea())
    }
    
    // MARK: - Logic
    
    private func getActiveCropArea(for size: CGSize) -> CGRect {
        if currentRatio == .freeform, let area = freeformArea {
            return area
        }
        return calculateDefaultCropArea(for: size, ratio: currentRatio)
    }
    
    private func calculateDefaultCropArea(for size: CGSize, ratio: MediaCrop) -> CGRect {
        guard let r = ratio.size(in: size) else {
            let w = size.width * 0.8
            return CGRect(x: (size.width - w)/2, y: (size.height - w)/2, width: w, height: w)
        }
        return CGRect(
            x: (size.width - r.width) / 2,
            y: (size.height - r.height) / 2,
            width: r.width,
            height: r.height
        )
    }
    
    private var ratioPicker: some View {
        HStack(spacing: 20) {
            if crop == .freeform {
                RatioButton(title: "Square", isSelected: currentRatio == .square, style: style) { withAnimation { currentRatio = .square } }
                RatioButton(title: "4:5", isSelected: currentRatio == .portrait, style: style) { withAnimation { currentRatio = .portrait } }
                RatioButton(title: "16:9", isSelected: currentRatio == .landscape, style: style) { withAnimation { currentRatio = .landscape } }
                RatioButton(title: "Free", isSelected: currentRatio == .freeform, style: style) { withAnimation { currentRatio = .freeform } }
            } else {
                RatioButton(title: currentRatio.title, isSelected: true, style: style) { }
                    .disabled(true)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }
    
    private func validateBounds(in size: CGSize, cropArea: CGRect) {
        // Minimum scale allowed is 0.3 for a "bird's eye" view
        if scale < 0.3 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 0.3
                lastScale = 0.3
            }
        }
    }
    
    private func renderCroppedImage() {
        let image = item.thumbnail
        let size = containerSize
        let cropArea = getActiveCropArea(for: size)
        
        let renderer = UIGraphicsImageRenderer(size: cropArea.size)
        let cropped = renderer.image { ctx in
            // Move coordinate system so 0,0 is the top-left of the crop area
            ctx.cgContext.translateBy(x: -cropArea.origin.x, y: -cropArea.origin.y)
            
            // Calculate where the image should be drawn in the view's coordinate space
            let aspect = image.size.width / image.size.height
            var drawWidth = size.width
            var drawHeight = size.width / aspect
            
            if drawHeight > size.height {
                drawHeight = size.height
                drawWidth = size.height * aspect
            }
            
            let drawRect = CGRect(
                x: (size.width - drawWidth*scale)/2 + offset.width,
                y: (size.height - drawHeight*scale)/2 + offset.height,
                width: drawWidth*scale,
                height: drawHeight*scale
            )
            
            image.draw(in: drawRect)
        }
        
        onDone(cropped)
    }
    
    private func thumbnailStrip(_ thumbs: [UIImage]) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<thumbs.count, id: \.self) { index in
                let isActive = index == activeIndex
                
                Button(action: { onJump?(index) }) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: thumbs[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isActive ? style.accentColor : Color.white.opacity(0.3), lineWidth: 2)
                            )
                            .opacity(isActive ? 1.0 : 0.6)
                        
                        if croppedIndices.contains(index) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                                .background(Circle().fill(.white).frame(width: 12, height: 12))
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }
}

struct RatioButton: View {
    let title: String
    let isSelected: Bool
    let style: MediaPickerStyle
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? style.accentColor : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(Capsule())
        }
    }
}

struct CropOverlay: View {
    let cropArea: CGRect
    let isCircular: Bool
    let isFreeform: Bool
    let style: MediaPickerStyle
    let onAreaChange: (CGRect) -> Void
    
    @State private var dragBaseArea: CGRect?
    @State private var containerSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            // Darkened exterior
            Color.black.opacity(0.5)
                .mask(
                    ZStack {
                        Rectangle()
                        if isCircular {
                            Circle()
                                .frame(width: cropArea.width, height: cropArea.height)
                                .position(x: cropArea.midX, y: cropArea.midY)
                                .blendMode(.destinationOut)
                        } else {
                            Rectangle()
                                .frame(width: cropArea.width, height: cropArea.height)
                                .position(x: cropArea.midX, y: cropArea.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                )
                .allowsHitTesting(false)
            
            // Border
            Group {
                if isCircular {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                } else {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                }
            }
            .frame(width: cropArea.width, height: cropArea.height)
            .position(x: cropArea.midX, y: cropArea.midY)
            .allowsHitTesting(false)
            
            // Handles
            if isFreeform && !isCircular {
                handleView(at: CGPoint(x: cropArea.minX, y: cropArea.minY)) { drag in
                    updateArea(delta: drag, corner: .topLeft)
                }
                handleView(at: CGPoint(x: cropArea.maxX, y: cropArea.minY)) { drag in
                    updateArea(delta: drag, corner: .topRight)
                }
                handleView(at: CGPoint(x: cropArea.minX, y: cropArea.maxY)) { drag in
                    updateArea(delta: drag, corner: .bottomLeft)
                }
                handleView(at: CGPoint(x: cropArea.maxX, y: cropArea.maxY)) { drag in
                    updateArea(delta: drag, corner: .bottomRight)
                }
            }
        }
    }
    
    @ViewBuilder
    private func handleView(at position: CGPoint, onDrag: @escaping (CGSize) -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragBaseArea == nil {
                            dragBaseArea = cropArea
                        }
                        onDrag(value.translation)
                    }
                    .onEnded { _ in
                        dragBaseArea = nil
                    }
            )
    }
    
    private enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private func updateArea(delta: CGSize, corner: Corner) {
        guard let base = dragBaseArea else { return }
        var newArea = base
        
        switch corner {
        case .topLeft:
            newArea.origin.x += delta.width
            newArea.origin.y += delta.height
            newArea.size.width -= delta.width
            newArea.size.height -= delta.height
        case .topRight:
            newArea.origin.y += delta.height
            newArea.size.width += delta.width
            newArea.size.height -= delta.height
        case .bottomLeft:
            newArea.origin.x += delta.width
            newArea.size.width -= delta.width
            newArea.size.height += delta.height
        case .bottomRight:
            newArea.size.width += delta.width
            newArea.size.height += delta.height
        }
        
        if newArea.size.width > 50 && newArea.size.height > 50 {
            onAreaChange(newArea)
        }
    }
}
