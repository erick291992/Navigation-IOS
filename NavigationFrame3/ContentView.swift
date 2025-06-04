//
//  ContentView.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🏠 ContentView (Root)")
                .font(.title2)

            Button("Push ViewA") {
//                NavigationManager.shared.push { ViewA() }
                Navigation.push {
                    ViewA()
                }
            }

            Button("Present ViewB") {
//                NavigationManager.shared.push { ViewB() }
                Navigation.presentSheet {
                    ViewB()
                }
            }
        }
        .padding()
    }
}


#Preview {
    NavigationCoordinator(rootView: ContentView())
}
