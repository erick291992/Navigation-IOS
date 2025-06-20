//
//  ViewD.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//
import SwiftUI

struct ViewD: View {
    @EnvironmentObject var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🧱 ViewD (Presented from C)")
                .font(.title2)

            Button("Dismiss sheet") {
                navigationManager.dismissSheet()
            }
            
            Button("Dismiss stack") {
                navigationManager.dismissPush()
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
            print("👀 ViewD appeared")
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
