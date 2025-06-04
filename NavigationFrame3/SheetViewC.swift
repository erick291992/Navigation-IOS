//
//  SheetViewC.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewC: View {
    
    @EnvironmentObject private var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 20) {
            Text("🆑 ViewC (Presented Sheet)")
                .font(.title2)

            Button("Push ViewD Inside SheetC") {
                Navigation.push { ViewD() }
            }

            Button("Dismiss To ViewB") {
                Navigation.dismissTo(ViewB.self)
            }

            Button("Dismiss To ContentView") {
                Navigation.dismissTo(ContentView.self)
            }
        }
        .padding()
    }
}


final class ViewCViewModel: ObservableObject {
    private let navigationManager = NavigationManager()

    func goToD() {
        navigationManager.push(view: { ViewD() })
    }

    func popOrDismiss() {
        navigationManager.popOrDismiss()
    }
    
    func presentD() {
        navigationManager.presentSheet(view: { ViewD() })
    }

}
