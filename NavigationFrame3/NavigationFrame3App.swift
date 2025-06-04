//
//  NavigationFrame3App.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//

import SwiftUI

@main
struct NavigationFrame3App: App {
    var body: some Scene {
        WindowGroup {
            NavigationCoordinator(rootView: ContentView())
        }
    }
}
