//
//  TestNativeNavigation.swift
//  NavigationFrame3
//
//  Test file to verify native NavigationStack behavior
//

import SwiftUI

struct TestNativeNavigation: View {
    @State private var path: [String] = []
    
    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Text("Root View")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.green.opacity(0.8))
                
                Button("Push View") {
                    path.append("pushed")
                }
            }
            .navigationDestination(for: String.self) { value in
                HStack {
                    // Transparent left side
                    Color.primary.opacity(0.001)
                        .contentShape(Rectangle())
                    
                    VStack {
                        Text("Pushed View")
                            .font(.title)
                        
                        Button("Pop") {
                            path.removeLast()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.purple.opacity(0.5))
                }
                .background(.clear)
            }
        }
    }
}

#Preview {
    TestNativeNavigation()
}

