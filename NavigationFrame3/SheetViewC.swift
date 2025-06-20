//
//  SheetViewC.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//
import SwiftUI
struct ViewC: View {
    @EnvironmentObject var navigationManager: NavigationManager
    private var id = UUID()

    init() {
        id = UUID()
        print("🔧 ViewC init with ID: \(id)")
    }

    var body: some View {
        logBodyRender()
        return VStack(spacing: 20) {
            Text("🌊 ViewC (Presented from B)")
                .font(.title2)

            Button("Present ViewD") {
//                navigationManager.presentSheet {
//                    ViewD()
//                }
                navigationManager.presentSheet {
                    ViewD()
                } onDismiss: {
                    print("🔥 ViewD was dismissed")
                }


            }
            Button("Push ViewD") {
                navigationManager.push {
                    ViewD()
                } onDismiss: {
                    print("🔥 Pushed ViewD was dismissed")
                }
            }
            Button("Dismiss sheet/fullscreen") {
                navigationManager.dismissSheet()
            }
            
            Button("Dismiss stack") {
                navigationManager.dismissPush()
            }
        }
        .padding()
        .onAppear {
            print("👀 ViewC appeared [ID: \(id)] → likely entering view hierarchy")
        }
        .onDisappear {
            print("🚪 ViewC disappeared")
        }
        .onChange(of: navigationManager.modalPushPaths) { _ in
            print("💡 ViewC body reevaluated [ID: \(id)] → push path likely updated")
        }
    }

    private func logBodyRender() {
        print("💡 ViewC body reevaluated [ID: \(id)] → preparing base")
    }
}
