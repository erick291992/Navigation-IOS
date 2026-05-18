import PhotosUI

/// Configuration for the Universal Media Picker.
public struct MediaPickerConfiguration {
    public let selectionLimit: Int
    public let allowedTypes: [PHPickerFilter]
    public let crop: MediaCrop
    public let showCamera: Bool
    public let style: MediaPickerStyle

    public init(
        selectionLimit: Int = 1,
        allowedTypes: [PHPickerFilter] = [.images, .videos],
        crop: MediaCrop = .freeform,
        showCamera: Bool = true,
        style: MediaPickerStyle = .default
    ) {
        self.selectionLimit = selectionLimit
        self.allowedTypes = allowedTypes
        self.crop = crop
        self.showCamera = showCamera
        self.style = style
    }
}
