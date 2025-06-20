//
//  ViewD.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewE: View {
    @EnvironmentObject var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🟣 ViewE (Sheet)")
                .font(.largeTitle)
            
            Button("Dismiss to ViewB") {
                navigationManager.dismissTo(ViewB.self)
            }
            Button("Dismiss to ViewC") {
                navigationManager.dismissTo(ViewC.self)
            }
            Button("Dismiss") {
                NavigationManagerRegistry.shared.manager(for: "tab2")?.dismissSheet()
            }
            
            Button("Dismiss stack") {
                navigationManager.dismissPush()
            }
            
            Button("Present ViewF") {
//                navigationManager.presentSheet {
//                    ViewD()
//                }
                navigationManager.presentSheet {
                    ViewF()
                } onDismiss: {
                    print("🔥 ViewF was dismissed")
                }


            }
            Button("Push ViewF") {
                navigationManager.push {
                    ViewF()
                } onDismiss: {
                    print("🔥 Pushed ViewF was dismissed")
                }
            }
        }
        .padding()
        .onAppear {
            print("👀 ViewE appeared")
        }
    }
}
