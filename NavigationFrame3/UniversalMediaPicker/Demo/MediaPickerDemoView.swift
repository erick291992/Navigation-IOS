import SwiftUI

struct MediaPickerDemoView: View {
    @State private var isPickerPresented = false
    @State private var selectionLimit = 1
    @State private var cropMode: MediaCrop = .square
    @State private var showCamera = true
    @State private var pickedItems: [MediaItem] = []
    
    var body: some View {
        List {
            Section("Configuration") {
                Stepper("Selection Limit: \(selectionLimit)", value: $selectionLimit, in: 1...10)
                
                Picker("Crop Ratio", selection: $cropMode) {
                    Text("Square").tag(MediaCrop.square)
                    Text("Portrait (4:5)").tag(MediaCrop.portrait)
                    Text("Landscape (16:9)").tag(MediaCrop.landscape)
                    Text("Circle").tag(MediaCrop.circle)
                    Text("Freeform").tag(MediaCrop.freeform)
                    Text("None").tag(MediaCrop.none)
                }
                
                Toggle("Show Camera", isOn: $showCamera)
            }
            
            Section {
                Button(action: { isPickerPresented = true }) {
                    HStack {
                        Spacer()
                        Text("Launch Universal Media Picker")
                            .bold()
                        Spacer()
                    }
                }
                .listRowBackground(Color.blue)
                .foregroundColor(.white)
            }
            
            if !pickedItems.isEmpty {
                Section("Results (\(pickedItems.count))") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(pickedItems) { item in
                                VStack {
                                    Image(uiImage: item.thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(10)
                                    
                                    Text(item.contentType == .video ? "Video" : "Image")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Media Picker Demo")
        .sheet(isPresented: $isPickerPresented) {
            UniversalMediaPicker(
                configuration: .init(
                    selectionLimit: selectionLimit,
                    allowedTypes: [.images, .videos],
                    crop: cropMode,
                    showCamera: showCamera
                ),
                onCompletion: { items in
                    pickedItems = items
                    isPickerPresented = false
                },
                onCancel: {
                    isPickerPresented = false
                }
            )
        }
    }
}

#Preview {
    MediaPickerDemoView()
}
