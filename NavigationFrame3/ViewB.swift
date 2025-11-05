//
//  ViewB.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewB: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🅱️ ViewB")
                .font(.largeTitle)

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
                navigationManager.presentSheet(detents: [.medium], dragIndicator: .visible) {
                    ViewC()
                } onDismiss: {
                    
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.green.opacity(0.2))
        .onAppear {
            print("👀 ViewB appeared")
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
