//
//  NavigationFrame3App.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//

import SwiftUI

@main
struct MyApp: App {
//    @StateObject private var navManager = NavigationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
//                .environmentObject(navManager) // ✅ Shared across all NavigationCoordinators
        }
    }
}
