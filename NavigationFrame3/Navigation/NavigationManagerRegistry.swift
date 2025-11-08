//
//  NavigationManagerRegistry.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/5/25.
//

import Foundation
import SwiftUI

final class NavigationManagerRegistry {
    static let shared = NavigationManagerRegistry()

    // Wrapper class to hold weak references
    private class WeakBox<T: AnyObject> {
        weak var value: T?
        init(_ value: T) {
            self.value = value
        }
    }

    // Change from strong to weak references
    private var managers: [String: WeakBox<NavigationManager>] = [:]
    private var queuedActions: [String: [(NavigationManager) -> Void]] = [:]

    func register(_ manager: NavigationManager, for key: String) {
        managers[key] = WeakBox(manager)

        // Run any queued actions
        if let actions = queuedActions.removeValue(forKey: key) {
            for action in actions {
                action(manager)
            }
        }
    }

    func manager(for key: String) -> NavigationManager? {
        // Clean up nil references automatically
        if let box = managers[key] {
            if box.value == nil {
                managers.removeValue(forKey: key)
                return nil
            }
            return box.value
        }
        return nil
    }

    func perform(_ key: String, action: @escaping (NavigationManager) -> Void) {
        if let manager = manager(for: key) {  // Uses the updated manager(for:) method
            action(manager)
        } else {
            queuedActions[key, default: []].append(action)
        }
    }
    
    func unregister(key: String) {
        managers.removeValue(forKey: key)
        queuedActions.removeValue(forKey: key)
    }
    
    func clearAll() {
        managers.removeAll()
        queuedActions.removeAll()
    }
}
