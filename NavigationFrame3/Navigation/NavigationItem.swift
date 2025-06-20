//
//  NavigationItem.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

enum NavigationLocation: Hashable {
    case root
    case rootPush(index: Int)
    case modalStack(index: Int)
    case modalPush(modalID: UUID, index: Int)
}

struct NavigationItem: Identifiable, Hashable {
    let id: UUID
    let viewTypeName: String
    let type: NavigationType
    let location: NavigationLocation

    enum NavigationType: String {
        case push, sheet, fullscreen
    }

    var typeName: String {
        viewTypeName
    }
}
