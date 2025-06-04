//
//  ViewD.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewD: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🆔 ViewD (Pushed inside SheetC)")
                .font(.title2)

            Button("Dismiss To ViewB") {
                Navigation.dismissTo(ViewB.self)
            }
            
            Button("Dismiss To ViewC") {
                Navigation.dismissTo(ViewC.self)
            }

            Button("Dismiss To ContentView") {
                Navigation.dismissTo(ContentView.self)
            }
            
            Button("Present SheetE") {
                Navigation.push { ViewE() }
            }
        }
        .padding()
    }
}


final class ViewDViewModel: ObservableObject {
    private let navigationManager = NavigationManager()

    func popOrDismiss() {
        navigationManager.popOrDismiss()
    }
    
    func dismissTopSheet() {
        navigationManager.dismissTopModal()
    }
}
