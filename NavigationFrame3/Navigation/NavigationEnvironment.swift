//
//  NavigationEnvironment.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/4/25.
//

import SwiftUI

private struct NavigationManagerKey: EnvironmentKey {
    static let defaultValue: NavigationManager = NavigationManager()
}

extension EnvironmentValues {
    var navigationManager: NavigationManager {
        get { self[NavigationManagerKey.self] }
        set { self[NavigationManagerKey.self] = newValue }
    }
} 