//
//  NavigationItem.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 5/28/25.
//
import SwiftUI

struct NavigationItem: Identifiable, Hashable {
    let id: UUID
    let viewTypeName: String
    let type: NavigationType

    enum NavigationType: String {
        case push, sheet, fullscreen
    }

    var typeName: String {
        viewTypeName
    }
}
