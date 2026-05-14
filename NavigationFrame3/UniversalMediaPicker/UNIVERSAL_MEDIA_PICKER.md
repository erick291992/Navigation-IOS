# 💎 Universal Media Picker: Technical Handoff Guide

## 📌 Overview
The **Universal Media Picker** is a production-grade, multi-style media selection and processing framework for iOS. It follows a **Tiered Architecture** that allows it to be used as a drop-in UI component or a "Headless" engine for custom-built interfaces.

---

## 🏗 Architecture (The 3-Tier System)

### Tier 1: Core Engine (`MediaPickerEngine`)
- **Responsibility**: Pure data processing.
- **Capabilities**: Converts `PHAsset`s, `PhotosPickerItem`s, or `UIImage`s into unified `MediaItem` objects. Handles data extraction, thumbnail generation, and temporary URL management.
- **Usage**: Use this when you have raw assets and just need them "Meetsta-ready" without any UI.

### Tier 2: State Manager (`MediaPickerManager`)
- **Responsibility**: Coordinates flow and state.
- **Capabilities**: Manages the selection limit, crop flow logic, and history (Reuse) persistence.
- **Usage**: Powering custom UI views that need logic but not the default layouts.

### Tier 3: Elite UI Views
- **`UnifiedCreatorView`**: The flagship "Elite" picker. Merges camera, library, and reuse history.
- **`EliteGeometricPickerView`**: An alternative "Style B" layout with distinct geometry (Instagram-style).
- **`MediaPickerModifier`**: A SwiftUI `.mediaPicker(...)` modifier for effortless integration.

---

## 🚀 How to Use

### 1. Default Integration (ViewModifier)
The easiest way to add the picker to any view:

```swift
struct MyView: View {
    @State private var isPickerPresented = false
    
    var body: some View {
        Button("Select Media") {
            isPickerPresented = true
        }
        .mediaPicker(
            isPresented: $isPickerPresented,
            configuration: .init(selectionLimit: 5, crop: .square),
            onCompletion: { items in
                print("Picked \(items.count) items!")
            }
        )
    }
}
```

### 2. Manual Instantiation
If you need it in a specific navigation flow or sheet:

```swift
UnifiedCreatorView(
    configuration: .init(selectionLimit: 3),
    onCompletion: { items in ... },
    onCancel: { ... }
)
```

---

## 🎨 Custom Styling (`MediaPickerStyle`)
The picker is highly themeable. You can pass a `MediaPickerStyle` object in the configuration:

```swift
let myStyle = MediaPickerStyle(
    accentColor: .pink,
    doneButtonStyle: .capsule,
    gridStyle: .init(columnCount: 3, spacing: 2)
)

let config = MediaPickerConfiguration(style: myStyle)
```

---

## 🧪 Headless / Custom UI Mode
Developers can build their own grid entirely from scratch while using our engine for heavy lifting. Reference `AdvancedPickerExampleView.swift` in the `Demo` folder for a 1:1 example.

**Key Components for Headless:**
- **`AssetGridViewModel`**: Handles PhotoKit fetching, album switching, and selection logic.
- **`MediaPickerEngine.shared.process(assets)`**: Pass raw `PHAsset`s here to get `MediaItem`s back.

---

## 💾 Media History (Reuse Mode)
The `MediaHistoryManager` automatically persists successfully processed items. Users can access these in the "REUSE" tab of the Elite pickers. 
- **Location**: `Services/MediaHistoryManager.swift`
- **Persistence**: Stored via JSON in the local file system.

---

## 🛡 Requirements & Permissions
Ensure your `Info.plist` contains:
- `NSPhotoLibraryUsageDescription`
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription` (if video recording is enabled)

---

## 📁 Folder Structure
- `Entry/`: SwiftUI modifiers and entry points.
- `Core/`: The main UI implementations (UnifiedCreator, EliteGeometric).
- `Models/`: `MediaItem`, `MediaPickerConfiguration`, and `MediaPickerStyle`.
- `Services/`: The engine, manager, and hardware services (Camera/PhotoKit).
- `Components/`: Shared UI atoms (Buttons, Grid cells, Camera previews).
- `Demo/`: Example implementations and "Style B" reference code.

---

**Built with Elite Performance and Tier 3 Flexibility.** 🚀
