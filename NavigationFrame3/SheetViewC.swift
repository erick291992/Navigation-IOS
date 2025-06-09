//
//  SheetViewC.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//
import SwiftUI
struct ViewC: View {
    @EnvironmentObject var navigationManager: NavigationManager
    private let id = UUID()

    init() {
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
                }

            }
        }
        .padding()
        .onAppear {
            print("👀 ViewC appeared")
        }
        .onDisappear {
            print("🚪 ViewC disappeared")
        }
    }

    private func logBodyRender() {
        print("💡 ViewC body re-evaluated for ID: \(id)")
    }
}
