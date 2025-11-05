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

/// Configuration options for sheet presentation, following SwiftUI's presentation API patterns
struct SheetPresentationOptions {
    var detents: Set<PresentationDetent>?
    var dragIndicator: Visibility?
    
    init(
        detents: Set<PresentationDetent>? = nil,
        dragIndicator: Visibility? = nil
    ) {
        self.detents = detents
        self.dragIndicator = dragIndicator
    }
}

struct ModalContext: Identifiable, Equatable {
    let id = UUID()
    let style: ModalPresentationStyle
    let rootView: AnyView
    let onDismiss: (() -> Void)?
    let sheetPresentationOptions: SheetPresentationOptions?

    init<Content: View>(
        style: ModalPresentationStyle,
        sheetPresentationOptions: SheetPresentationOptions? = nil,
        makeView: @escaping () -> Content,
        onDismiss: (() -> Void)? = nil
    ) {
        self.style = style
        self.rootView = AnyView(makeView())
        self.onDismiss = onDismiss
        self.sheetPresentationOptions = sheetPresentationOptions
    }

    static func == (lhs: ModalContext, rhs: ModalContext) -> Bool {
        lhs.id == rhs.id
    }
}
