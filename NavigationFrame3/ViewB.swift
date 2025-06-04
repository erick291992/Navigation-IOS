//
//  ViewB.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewB: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🅱️ ViewB (Pushed)")
                .font(.title2)

            Button("Present SheetC") {
//                NavigationManager.shared.presentSheet { ViewC() }
            }
        }
        .padding()
    }
}


final class ViewBViewModel: ObservableObject {
    private let navigationManager = NavigationManager()

    func goToC() {
        navigationManager.push(view: { ViewC() })
    }

    func presentD() {
        navigationManager.presentSheet(view: { ViewD() })
    }
}
