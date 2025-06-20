//
//  ModalContext.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/4/25.
//

import SwiftUI

enum ModalPresentationStyle {
    case sheet
    case fullScreen
}

struct ModalContext: Identifiable, Equatable {
    let id = UUID()
    let style: ModalPresentationStyle
    let rootView: AnyView
    let onDismiss: (() -> Void)?

    init<Content: View>(
        style: ModalPresentationStyle,
        makeView: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        self.style = style
        self.rootView = AnyView(makeView())
        self.onDismiss = onDismiss
    }

    static func == (lhs: ModalContext, rhs: ModalContext) -> Bool {
        lhs.id == rhs.id
    }
}
