//
//  NavigationItem.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationItem: Identifiable, Hashable {
    let id = UUID()
    let viewFactory: () -> AnyView
    let type: NavigationType
    let viewTypeName: String // NEW: store the true type name


    enum NavigationType: String {
        case push, sheet, fullscreen
    }

    static func == (lhs: NavigationItem, rhs: NavigationItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var typeName: String {
        viewFactory().typeName
    }
}

extension View {
    var typeName: String {
        String(describing: type(of: self))
    }
}
