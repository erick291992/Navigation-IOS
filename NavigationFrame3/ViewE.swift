//
//  ViewD.swift
//  NavigationFrame2
//
//  Created by Erick Manrique on 5/16/25.
//

import SwiftUI

struct ViewE: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🅴 ViewE (SheetE)")

            Button("Dismiss To ViewB") {
                Navigation.dismissTo(ViewB.self)
            }
            
            Button("Push ViewF Inside SheetF") {
                Navigation.push { ViewF() }
            }
        }
        .padding()
    }
}

struct ViewF: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🅴 ViewF (SheetF)")

            Button("Dismiss To ViewC") {
                Navigation.dismissTo(ViewC.self)
            }
        }
        .padding()
    }
}
