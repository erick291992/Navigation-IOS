//
//  ViewD.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewE: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🟣 ViewE (Sheet)")
                .font(.largeTitle)

            OpenSheetsReadout()

            GroupBox("Present ViewF as…") {
                VStack(spacing: 12) {
                    Button("Sheet · stacked (E stays behind)") {
                        navigationManager.presentSheet(presentation: .stacked) { ViewF() } onDismiss: {
                            print("🔥 ViewF (stacked) was dismissed")
                        }
                    }
                    Button("Replace last (E closed for good)") {
                        navigationManager.presentSheet(style: .replaceLast, presentation: .stacked) { ViewF() } onDismiss: {
                            print("🔥 ViewF (replaceLast) was dismissed")
                        }
                    }
                    Button("Replace all (every sheet closed)") {
                        navigationManager.presentSheet(style: .replaceAll, presentation: .stacked) { ViewF() } onDismiss: {
                            print("🔥 ViewF (replaceAll) was dismissed")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Button("Dismiss sheet") {
                navigationManager.dismissSheet()
            }
            
            Button("Dismiss to ViewB") {
                navigationManager.dismissTo(ViewB.self)
            }
            Button("Dismiss to ViewC") {
                navigationManager.dismissTo(ViewC.self)
            }
            Button("Dismiss tab") {
                NavigationManagerRegistry.shared.manager(forCustomKey: "tab2")?.dismissSheet()
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
        .background(Color.yellow.opacity(0.5))
        .onAppear {
            print("👀 ViewE appeared")
        }
        .onDisappear {
            print("👋 ViewE disappeared")
        }
    }
}
