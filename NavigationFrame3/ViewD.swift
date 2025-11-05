//
//  ViewD.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//
import SwiftUI

struct ViewD: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager
    var onDismiss: (() -> Void)? = nil
    private let id = UUID()
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        let id = UUID()
        print("🔧 ViewD init with ID: \(id)")
    }

    var body: some View {
        let _ = print("🎨 ViewD body rendering - rootPushPath count: \(navigationManager.rootPushPath.count)")
        return HStack {
            Color.primary.opacity(0.001) // Virtually transparent but still interactive - allows seeing view behind
                .contentShape(Rectangle())
                .onTapGesture {
                    print("👆 ViewD: Transparent left side tapped")
                    onDismiss?()
                }
            
            VStack(spacing: 20) {
                Text("🧱 ViewD (Side Menu)")
                    .font(.title2)
                
                Text("Root Stack Count: \(navigationManager.rootPushPath.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("This view should show ViewB behind through transparent areas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let onDismiss = onDismiss {
                    Button("Dismiss Side Menu") {
                        onDismiss()
                    }
                }

                Button("Dismiss sheet") {
                    navigationManager.dismissSheet()
                }
                
                Button("Dismiss stack") {
                    navigationManager.dismissPush()
                }
                
                Button("Dismiss") {
                    navigationManager.dismiss()
                }
                
                Button("Dismiss back") {
                    navigationManager.dismissBack()
                }
                
                Button("Dismiss to ViewC") {
                    navigationManager.dismissTo(ViewC.self)
                }

                Button("Dismiss to ViewB") {
                    navigationManager.dismissTo(ViewB.self)
                }
                
                Button("📦 Present ViewE on Tab 2") {
                    routeToViewE()
                }
                
                Button("Present ViewE") {
                    navigationManager.presentSheet {
                        ViewE()
                    } onDismiss: {
                        print("🔥 ViewE was dismissed")
                    }


                }
                Button("Push ViewE") {
                    navigationManager.push {
                        ViewE()
                    } onDismiss: {
                        print("🔥 Pushed ViewE was dismissed")
                    }


                }
            }
            .padding()
            .onAppear {
                print("👀 ViewD appeared - rootPushPath count: \(navigationManager.rootPushPath.count)")
                print("👀 ViewD: rootPushPath: \(navigationManager.rootPushPath.map { $0.viewTypeName })")
            }
            .onDisappear {
                print("👋 ViewD disappeared - rootPushPath count: \(navigationManager.rootPushPath.count)")
            }
            .onChange(of: navigationManager.rootPushPath.count) { oldCount, newCount in
                print("📊 ViewD: rootPushPath count changed from \(oldCount) to \(newCount)")
                print("📊 ViewD: Current rootPushPath: \(navigationManager.rootPushPath.map { $0.viewTypeName })")
            }
            .background(Color.purple.opacity(0.5))
        }
//        .background(.clear)
        .onAppear {
            print("👀 ViewD (outer container) appeared")
        }
        .onDisappear {
            print("👋 ViewD (outer container) disappeared")
        }
    }

    private func routeToViewE() {
        if let manager = NavigationManagerRegistry.shared.manager(for: "tab2") {
            manager.presentSheet {
                ViewE()
            }
        } else {
            print("❌ NavigationManager for tab2 not ready yet")
        }
    }
}
