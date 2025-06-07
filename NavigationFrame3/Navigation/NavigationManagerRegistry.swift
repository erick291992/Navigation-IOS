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

    private var managers: [String: NavigationManager] = [:]
    private var queuedActions: [String: [(NavigationManager) -> Void]] = [:]

    func register(_ manager: NavigationManager, for key: String) {
        managers[key] = manager

        // Run any queued actions
        if let actions = queuedActions.removeValue(forKey: key) {
            for action in actions {
                action(manager)
            }
        }
    }

    func manager(for key: String) -> NavigationManager? {
        return managers[key]
    }

    func perform(_ key: String, action: @escaping (NavigationManager) -> Void) {
        if let manager = managers[key] {
            action(manager)
        } else {
            queuedActions[key, default: []].append(action)
        }
    }
}


//extension NavigationManagerRegistry {
//    func dismissTo<Content: View>(_ target: Content.Type) {
//        let targetName = String(describing: target)
//
//        for manager in managers.values {
//            if manager.dismissTo(targetName) {
//                print("✅ Global dismissTo \(targetName)")
//                return
//            }
//        }
//
//        print("❌ No manager found containing \(targetName)")
//    }
//}
