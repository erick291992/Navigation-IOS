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
    // MARK: - Generic Type-Safe API (Default)
    func register<T: View>(_ manager: NavigationManager, for target: T.Type) {
        register(manager, withCustomKey: String(describing: target))
    }
    func manager<T: View>(for target: T.Type) -> NavigationManager? {
        return manager(forCustomKey: String(describing: target))
    }
    func perform<T: View>(on target: T.Type, action: @escaping (NavigationManager) -> Void) {
        perform(onCustomKey: String(describing: target), action: action)
    }
    
    func unregister<T: View>(for target: T.Type) {
        unregister(customKey: String(describing: target))
    }
    // MARK: - Custom Key API (For Duplicate Roots)
    func register(_ manager: NavigationManager, withCustomKey key: String) {
        managers[key] = WeakBox(manager)
        // Run any queued actions
        if let actions = queuedActions.removeValue(forKey: key) {
            for action in actions {
                action(manager)
            }
        }
    }
    func manager(forCustomKey key: String) -> NavigationManager? {
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
    func perform(onCustomKey key: String, action: @escaping (NavigationManager) -> Void) {
        if let manager = manager(forCustomKey: key) {
            action(manager)
        } else {
            queuedActions[key, default: []].append(action)
        }
    }
    
    func unregister(customKey key: String) {
        managers.removeValue(forKey: key)
        queuedActions.removeValue(forKey: key)
    }
    // Internal fallback for LifecycleObservers that only hold the raw string key
    func unregister(key: String) {
        unregister(customKey: key)
    }
    
    func clearAll() {
        managers.removeAll()
        queuedActions.removeAll()
    }
}
