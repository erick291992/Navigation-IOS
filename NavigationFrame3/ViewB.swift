//
//  ViewB.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewB: View {
    @EnvironmentObject var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🅱️ ViewB")
                .font(.largeTitle)

            Button("Present ViewC") {
                navigationManager.presentSheet {
                    ViewC()
                }
            }

            Button("Dismiss Sheet") {
                navigationManager.dismissSheet()
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
