import SwiftUI

/// Defines the visual appearance of the UniversalMediaPicker.
public struct MediaPickerStyle {
    public var accentColor: Color
    public var backgroundColor: Color
    public var toolbarColor: Color
    public var galleryIcon: Image
    public var cameraIcon: Image
    public var galleryLabel: String
    public var gallerySubtitle: String
    public var cameraLabel: String
    public var cameraSubtitle: String
    public var onboardingTitle: String
    public var doneButtonStyle: DoneButtonStyle
    public var font: Font
    public var gridStyle: GridStyle
    
    public enum DoneButtonStyle {
        case capsule
        case text
        case filled
    }

    public struct GridStyle {
        public var galleryMode: GalleryMode
        public var columnCount: Int
        public var spacing: CGFloat
        public var cornerRadius: CGFloat
        public var selectionIndicator: SelectionIndicator
        public var selectionBorderWidth: CGFloat
        public var showAlbumPicker: Bool
        public var showVideoDuration: Bool
        
        public enum GalleryMode {
            case grid    // Option A: Custom PhotoKit grid (Instagram-style)
            case native  // Option B: Apple's native PhotosPicker (lean)
        }
        
        public enum SelectionIndicator {
            case numbered, checkmark, none
        }
        
        public static let `default` = GridStyle(
            galleryMode: .grid,
            columnCount: 4,
            spacing: 1,
            cornerRadius: 0,
            selectionIndicator: .numbered,
            selectionBorderWidth: 3.0,
            showAlbumPicker: true,
            showVideoDuration: true
        )
    }
    
    public init(
        accentColor: Color = .yellow,
        backgroundColor: Color = .black,
        toolbarColor: Color = .black,
        galleryIcon: Image = Image(systemName: "photo.on.rectangle.angled"),
        cameraIcon: Image = Image(systemName: "camera.fill"),
        galleryLabel: String = "Open Gallery",
        gallerySubtitle: String = "Choose from your library",
        cameraLabel: String = "Take Photo",
        cameraSubtitle: String = "Capture a new moment",
        onboardingTitle: String = "Unified Creator V3",
        doneButtonStyle: DoneButtonStyle = .text,
        font: Font = .body,
        gridStyle: GridStyle = .default
    ) {
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.toolbarColor = toolbarColor
        self.galleryIcon = galleryIcon
        self.cameraIcon = cameraIcon
        self.galleryLabel = galleryLabel
        self.gallerySubtitle = gallerySubtitle
        self.cameraLabel = cameraLabel
        self.cameraSubtitle = cameraSubtitle
        self.onboardingTitle = onboardingTitle
        self.doneButtonStyle = doneButtonStyle
        self.font = font
        self.gridStyle = gridStyle
    }
    
    public static let `default` = MediaPickerStyle()
    
    public static let pinkSleek = MediaPickerStyle(
        accentColor: .pink,
        onboardingTitle: "Unified Creator V3",
        doneButtonStyle: .capsule,
        font: .system(.body, design: .rounded)
    )
}
