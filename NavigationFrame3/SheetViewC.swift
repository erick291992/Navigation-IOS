//
//  SheetViewC.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//
import SwiftUI

struct ViewC: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager
    private var id = UUID()
    @State private var tapCount = 0   // survives in .stacked, resets in .swap

    init() {
        id = UUID()
        print("🔧 ViewC init with ID: \(id)")
    }

    var body: some View {
        logBodyRender()
        return ScrollView { VStack(spacing: 20) {
            Text("🌊 ViewC (Presented from B)")
                .font(.title2)
                .padding(.top)

            Text("This is a sheet - no back button by default")
                .font(.caption)
                .foregroundColor(.secondary)

            OpenSheetsReadout()

            Button("Taps: \(tapCount)  (+1)") { tapCount += 1 }

            GroupBox("Present ViewD as…") {
                VStack(spacing: 12) {
                    Button("Sheet · stacked (C stays behind)") {
                        navigationManager.presentSheet(presentation: .stacked) { ViewD() } onDismiss: {
                            print("🔥 ViewD (stacked) was dismissed")
                        }
                    }
                    Button("Sheet · swap (C slides away)") {
                        navigationManager.presentSheet(presentation: .swap) { ViewD() } onDismiss: {
                            print("🔥 ViewD (swap) was dismissed")
                        }
                    }
                    Button("Full screen · stacked") {
                        navigationManager.presentFullScreen(presentation: .stacked) { ViewD() } onDismiss: {
                            print("🔥 ViewD (full screen) was dismissed")
                        }
                    }
                    Button("Replace last (C closed for good)") {
                        navigationManager.presentSheet(style: .replaceLast) { ViewD() } onDismiss: {
                            print("🔥 ViewD (replaceLast) was dismissed")
                        }
                    }
                    Button("Replace all (every sheet closed)") {
                        navigationManager.presentSheet(style: .replaceAll) { ViewD() } onDismiss: {
                            print("🔥 ViewD (replaceAll) was dismissed")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

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
            Button("Dismiss") {
                navigationManager.dismiss()
            }
            
            Button("Dismiss back") {
                navigationManager.dismissBack()
            }
            
            Button("Push ViewB") {
                navigationManager.push {
                    ViewB()
                } onDismiss: {
                    print("🔥 Pushed ViewB was dismissed")
                }
            }            
            Button("Dismiss to ViewB") {
                navigationManager.dismissTo(ViewB.self)
            }
        }
        .padding() }
        .onAppear {
            print("👀 ViewC appeared [ID: \(id)] → likely entering view hierarchy")
        }
        .onDisappear {
            print("🚪 ViewC disappeared")
        }
        .onChange(of: navigationManager.modalPushPaths) { _ in
            print("💡 ViewC body reevaluated [ID: \(id)] → push path likely updated")
        }
        .background(Color.blue.opacity(0.5))
    }

    private func logBodyRender() {
        print("💡 ViewC body reevaluated [ID: \(id)] → preparing base")
    }
}

/// Shows the sheets currently in this tab's modal stack, bottom → top.
struct OpenSheetsReadout: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager

    var body: some View {
        let names = navigationManager.modalStack.compactMap { modal in
            navigationManager.fullNavigationHistory.first { $0.id == modal.id }?.viewTypeName
        }
        Text("Open sheets: \(names.isEmpty ? "none" : names.joined(separator: " → "))")
            .font(.caption.monospaced())
            .padding(6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
