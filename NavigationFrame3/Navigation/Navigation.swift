//
//  Navigation.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI
//
//enum Navigation {
//    static var _localOverride: NavigationManager?
//
//    static var current: NavigationManager {
//        _localOverride ?? NavigationManager.shared
//    }
//
//    static func withLocal<R: View>(_ manager: NavigationManager, @ViewBuilder perform: () -> R) -> R {
//        _localOverride = manager
//        let result = perform()
//        _localOverride = nil
//        return result
//    }
//
//    // MARK: - Unified API
//
//    static func push<Content: View>(@ViewBuilder _ view: @escaping () -> Content) {
//        current.push(view: view)
//    }
//
//    static func presentSheet<Content: View>(@ViewBuilder _ view: @escaping () -> Content) {
//        NavigationManager.shared.presentSheet(view: view)
//    }
//
//    static func presentFullscreen<Content: View>(@ViewBuilder _ view: @escaping () -> Content) {
//        NavigationManager.shared.presentFullscreen(view: view)
//    }
//
//    static func dismissTo<Content: View>(_ view: Content.Type) {
//        NavigationManager.shared.dismissTo(view)
//    }
//
//    static func popOrDismiss() {
//        current.popOrDismiss()
//    }
//
//    static func pop() {
//        current.pop()
//    }
//
//    static func dismissTopModal() {
//        NavigationManager.shared.dismissTopModal()
//    }
//}
