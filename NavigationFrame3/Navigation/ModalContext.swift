//
//  ModalContext.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/4/25.
//

import SwiftUI

struct ModalContext: Identifiable, Equatable {
    let id = UUID()
    let rootView: AnyView

    static func == (lhs: ModalContext, rhs: ModalContext) -> Bool {
        lhs.id == rhs.id
    }
}
