//
//  PushContext.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/6/25.
//
import SwiftUI

struct PushContext: Identifiable, Hashable {
    let id = UUID()
    let makeView: () -> AnyView
    let viewTypeName: String
    let onDismiss: (() -> Void)?
    
    /// Closure that applies environment to a view - generic, doesn't require knowing the type
    let applyEnvironment: ((AnyView) -> AnyView)?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PushContext, rhs: PushContext) -> Bool {
        lhs.id == rhs.id
    }
}
