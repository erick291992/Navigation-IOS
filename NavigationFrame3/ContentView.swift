//
//  ContentView.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = "tab1"

    var body: some View {
        VStack {
            Button("Present ViewE on Tab 2") {
                selectedTab = "tab2"
                routeToViewE()
            }
            .padding()

            TabView(selection: $selectedTab) {
                NavigationCoordinator(rootView: ViewB(), customKey: "tab1")
                    .tabItem { Label("Tab 1", systemImage: "1.circle") }
                    .tag("tab1")

                NavigationCoordinator(rootView: MasterGalleryView(), customKey: "tab2")
                    .tabItem { Label("Tab 2", systemImage: "2.circle") }
                    .tag("tab2")
            }
        }
    }

    func routeToViewE() {
        if let manager = NavigationManagerRegistry.shared.manager(forCustomKey: "tab2") {
            manager.presentSheet {
                ViewE()
            }
        } else {
            print("❌ NavigationManager for tab2 not ready yet")
        }
    }
}

#Preview {
    ContentView()
}
