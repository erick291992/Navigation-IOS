import SwiftUI

struct ViewB: View {
    @Environment(\.navigationManager) var navigationManager: NavigationManager
    @State private var isShowingSideMenu = false
    @State private var vm = ViewBViewModel()
    
    init() {
        print("🔧 ViewB init with ID: \(UUID())")
    }

    var body: some View {
        let _ = print("🎨 ViewB body rendering - rootPushPath count: \(navigationManager.rootPushPath.count)")
        return ZStack {
            // New Sleek Gradient Background
            LinearGradient(
                colors: [.green.opacity(0.1), Color(uiColor: .systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header Area
                    VStack(spacing: 8) {
                        Text("🅱️ Navigation Master")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.green.opacity(0.8))
                        
                        Text("Original Navigation Testing Ground")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Info Card
                    VStack(spacing: 4) {
                        Text("Root Stack Count")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text("\(navigationManager.rootPushPath.count)")
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(24)
                    .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 10)
                    .padding(.horizontal)

                    // Navigation Actions
                    VStack(spacing: 12) {
                        NavigationButton(title: "Present ViewC", icon: "plus.square.on.square", color: .blue) {
                            navigationManager.presentSheet { ViewC() }
                        }
                        
                        NavigationButton(title: "Full Screen ViewC", icon: "arrow.up.left.and.arrow.down.right", color: .indigo) {
                            navigationManager.presentFullScreen { ViewC() }
                        }
                        
                        NavigationButton(title: "Push ViewC", icon: "arrow.right.square", color: .teal) {
                            navigationManager.push { ViewC() }
                        }
                        
                        Divider().padding(.vertical, 8)
                        
                        NavigationButton(title: "Push ViewB (Recursive)", icon: "arrow.clockwise", color: .green) {
                            navigationManager.push { ViewB() }
                        }
                        
                        NavigationButton(title: "Push ViewD", icon: "square.grid.2x2", color: .orange) {
                            navigationManager.push { ViewD(onDismiss: {}) }
                        }
                        
                        Divider().padding(.vertical, 8)
    
                        HStack(spacing: 12) {
                            QuickAction(title: "Dismiss Sheet", icon: "xmark.circle", color: .red) {
                                navigationManager.dismissSheet()
                            }
                            QuickAction(title: "Dismiss Push", icon: "arrow.left.circle", color: .red) {
                                navigationManager.dismissPush()
                            }
                        }
                        
                        NavigationButton(title: "Dismiss back to ViewB", icon: "arrow.uturn.backward", color: .red) {
                            navigationManager.dismissTo(ViewB.self)
                        }
                        
                        NavigationButton(title: "Show Side Menu", icon: "sidebar.right", color: .primary) {
                            withAnimation(.spring()) {
                                isShowingSideMenu = true
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Overlay side menu (ViewD) when shown
            if isShowingSideMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { isShowingSideMenu = false }
                    }
                
                NavigationCoordinator(
                    rootView: ViewD(onDismiss: { withAnimation { isShowingSideMenu = false } }),
                    customKey: "SideMenuView"
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .onAppear {
            print("👀 ViewB appeared")
        }
    }
}

// MARK: - Subviews
struct NavigationButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct QuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }
            .foregroundColor(color) // Icon and other elements
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
