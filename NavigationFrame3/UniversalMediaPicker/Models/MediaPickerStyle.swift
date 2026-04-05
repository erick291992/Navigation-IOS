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
    public var doneButtonStyle: DoneButtonStyle
    public var font: Font
    
    public enum DoneButtonStyle {
        case capsule
        case text
        case filled
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
        doneButtonStyle: DoneButtonStyle = .text,
        font: Font = .body
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
        self.doneButtonStyle = doneButtonStyle
        self.font = font
    }
    
    public static let `default` = MediaPickerStyle()
    
    public static let pinkSleek = MediaPickerStyle(
        accentColor: .pink,
        doneButtonStyle: .capsule,
        font: .system(.body, design: .rounded)
    )
}
