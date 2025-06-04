//
//  ViewA.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewA: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🅰️ ViewA (Pushed)")
                .font(.title2)

            Button("Push ViewB") {
//                NavigationManager.shared.push { ViewB() }
            }

            Button("Present SheetC") {
//                NavigationManager.shared.presentSheet { ViewC() }
            }
        }
        .padding()
    }
}


final class ViewAViewModel: ObservableObject {
    private let navigationManager = NavigationManager()

    func goToB() {
        navigationManager.push(view: { ViewB() })
    }

    func presentC() {
        navigationManager.presentSheet(view: { ViewC() })
    }

    func presentD() {
        navigationManager.presentFullscreen(view: { ViewD() })
    }
}
