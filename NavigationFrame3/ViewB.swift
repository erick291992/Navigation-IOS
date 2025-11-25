//
//  ViewB.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewB: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager
    @State private var isShowingSideMenu = false
    private let id = UUID()
    
    init() {
        print("🔧 ViewB init with ID: \(UUID())")
    }

    var body: some View {
        let _ = print("🎨 ViewB body rendering - rootPushPath count: \(navigationManager.rootPushPath.count)")
        return ZStack {
            // Main content
            VStack(spacing: 20) {
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
                print("🔵 ViewB: About to push ViewC")
                print("🔵 ViewB: Current rootPushPath count: \(navigationManager.rootPushPath.count)")
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
                print("🔵 ViewB: About to push ViewB")
                print("🔵 ViewB: Current rootPushPath count: \(navigationManager.rootPushPath.count)")
                navigationManager.push {
                    ViewB()
                } onDismiss: {
                    print("🔥 Pushed ViewB was dismissed")
                }
            }
            
            Button("Push ViewD") {
                print("🔵 ViewB: About to push ViewD")
                print("🔵 ViewB: Current rootPushPath count: \(navigationManager.rootPushPath.count)")
                print("🔵 ViewB: Current rootPushPath: \(navigationManager.rootPushPath.map { $0.viewTypeName })")
                navigationManager.push {
                    ViewD()
                } onDismiss: {
                    print("🔥 Pushed ViewD was dismissed")
                }
                print("🔵 ViewB: After push call, rootPushPath count: \(navigationManager.rootPushPath.count)")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.green.opacity(0.8))
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
                key: "SideMenuView" // nil = transparent background
            )
            .transition(.move(edge: .trailing))
            .zIndex(1)
        }
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
