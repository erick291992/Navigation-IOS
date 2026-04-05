//
//  ViewB.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI
import PhotosUI

struct ViewB: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager
    @State private var isShowingSideMenu = false
    @State private var vm = ViewBViewModel()
    
    init() {
        print("🔧 ViewB init with ID: \(UUID())")
    }

    var body: some View {
        @Bindable var vm = vm
        let _ = print("🎨 ViewB body rendering - rootPushPath count: \(navigationManager.rootPushPath.count)")
        return ZStack {
            Color.green.opacity(0.8).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    if !vm.pickedItems.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(vm.pickedItems) { item in
                                    Image(uiImage: item.thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 100)
                    }
                    
                    Group {
                        Text("Tier 1: Drop-In View")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        PickerButton(title: "Square (Drop-In)", icon: "square") {
                            vm.openPicker(crop: MediaCrop.square)
                        }
                        
                        PickerButton(title: "Freeform (Drop-In)", icon: "pencil.and.outline") {
                            vm.openPicker(crop: MediaCrop.freeform)
                        }
                        
                        PickerButton(title: "Multi-Select (Max 3)", icon: "stack") {
                            vm.openPicker(crop: MediaCrop.square, limit: 3)
                        }
                        
                        Text("Tier 2: One-Liner Modifier")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        PickerButton(title: "Sleek Pink (Modifier)", icon: "sparkles") {
                            vm.showModifierPicker = true
                        }
                        
                        Text("Tier 3: Headless Engine")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        PhotosPicker(selection: $vm.headlessSelection, maxSelectionCount: 3, matching: .images) {
                            HStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.1))
                                    .frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "cpu").foregroundColor(.orange))
                                Text("Custom UI (Headless)")
                                    .foregroundColor(.black)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(16)
                        }
                        .onChange(of: vm.headlessSelection) { _, items in
                            vm.didSelectHeadless(items)
                        }
                    }
                    .padding(.horizontal)
                    
                    Text("🅱️ ViewB")
                    .font(.largeTitle)
                
                    Text("Root Stack Count: \(navigationManager.rootPushPath.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
    
                    Button("Present ViewC") {
                        navigationManager.presentSheet {
                            ViewC()
                        } onDismiss: {
                            print("🔥 ViewC was dismissed")
                        }
                    }
                    
                    Button("Present Full Screen ViewC") {
                        navigationManager.presentFullScreen {
                            ViewC()
                        } onDismiss: {
                            print("🔥 ViewC was dismissed")
                        }
                    }
                    
                    Button("Push ViewC") {
                        navigationManager.push {
                            ViewC()
                        } onDismiss: {
                            print("🔥 Pushed ViewC was dismissed")
                        }
                    }
    
                    Button("Dismiss Sheet") {
                        navigationManager.dismissSheet()
                    }
                    
                    Button("Push ViewB") {
                        navigationManager.push {
                            ViewB()
                        } onDismiss: {
                            print("🔥 Pushed ViewB was dismissed")
                        }
                    }
                    
                    Button("Push ViewD") {
                        navigationManager.push {
                            ViewD()
                        } onDismiss: {
                            print("🔥 Pushed ViewD was dismissed")
                        }
                    }
                    
                    Button("Dismiss stack") {
                        navigationManager.dismissPush()
                    }
                    
                    Button("Dismiss to ViewB") {
                        navigationManager.dismissTo(ViewB.self)
                    }
                    
                    Button("Dismiss") {
                        navigationManager.dismiss()
                    }
                    
                    Button("intent") {
                        navigationManager.presentSheet(
                            detents: [.medium, .large],
                            dragIndicator: .visible
                        ) {
                            ViewC()
                        }
                    }
                    
                    Button("Show Side Menu (ViewD)") {
                        isShowingSideMenu = true
                    }
                }
                .padding(.vertical)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("👀 ViewB appeared - rootPushPath count: \(navigationManager.rootPushPath.count)")
        }
        .onDisappear {
            print("👋 ViewB disappeared - rootPushPath count: \(navigationManager.rootPushPath.count)")
        }
        .onChange(of: navigationManager.rootPushPath.count) { oldCount, newCount in
            print("📊 ViewB: rootPushPath count changed from \(oldCount) to \(newCount)")
            print("📊 ViewB: Current rootPushPath: \(navigationManager.rootPushPath.map { $0.viewTypeName })")
        }
        
            // Overlay side menu (ViewD) when shown
            if isShowingSideMenu {
                NavigationCoordinator(
                    rootView: ViewD(onDismiss: { isShowingSideMenu = false }),
                    customKey: "SideMenuView"
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .mediaPicker(
            isPresented: $vm.showModifierPicker,
            configuration: .init(crop: .square, style: .pinkSleek),
            onCompletion: { items in
                vm.handlePickerResult(items)
            }
        )
        .sheet(isPresented: $vm.showPicker) {
            UniversalMediaPicker(
                configuration: .init(
                    selectionLimit: vm.selectionLimit,
                    crop: vm.cropMode
                ),
                onCompletion: { items in
                    vm.handlePickerResult(items)
                },
                onCancel: {
                    vm.cancelPicker()
                }
            )
            .id(vm.pickerId) // Use the UUID to force fresh state
        }
        .sheet(isPresented: Binding(
            get: { if case .cropping = vm.flowState { return true } else { return false } },
            set: { if !$0 { vm.flowState = .idle } }
        )) {
            if case .cropping(let index, let total) = vm.flowState, index < vm.headlessItems.count {
                let item = vm.headlessItems[index]
                CropView(
                    item: item,
                    crop: .freeform,
                    subtitle: "Image \(index + 1)/\(total)",
                    thumbnails: vm.headlessItems.map { $0.thumbnail },
                    activeIndex: index,
                    croppedIndices: Set(vm.headlessResults.keys),
                    onJump: { vm.jumpTo(index: $0) },
                    onDone: { cropped in
                        vm.handleCropResult(cropped, at: index)
                    },
                    onCancel: {
                        vm.flowState = .idle
                    }
                )
            }
        }
    }
}

struct PickerButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
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
                    .foregroundColor(.black)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}




//final class ViewBViewModel: ObservableObject {
//    private let navigationManager = NavigationManager()
//
//    func goToC() {
//        navigationManager.push(view: { ViewC() })
//    }
//
//    func presentD() {
//        navigationManager.presentSheet(view: { ViewD() })
//    }
//}
