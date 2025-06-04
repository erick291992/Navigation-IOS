//
//  NavigationContainerView.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationContainerView<Content: View>: View {
    @StateObject private var navigationManager = NavigationManager()
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        NavigationContainerStackView(navigationManager: navigationManager, content: content)
    }
}

private struct NavigationContainerStackView<Content: View>: View {
    @ObservedObject var navigationManager: NavigationManager
    let content: () -> Content

    var body: some View {
        Navigation.withLocal(navigationManager) {
            NavigationStack(path: $navigationManager.pushPath) {
                content()
                    .environmentObject(navigationManager)
                    .navigationDestination(for: NavigationItem.self) { item in
                        item.viewFactory()
                    }
            }
        }
    }
}
