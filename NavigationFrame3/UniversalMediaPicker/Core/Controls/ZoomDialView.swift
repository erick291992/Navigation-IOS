import SwiftUI

/// Camera zoom dial with collapsed (single factor) and expanded (all factors)
/// states. Internal `isExpanded` state lives in the view (UI-ephemeral, not
/// VM-worthy). Parent passes the available factors + current zoom + a
/// callback to fire when a factor is selected.
struct ZoomDialView: View {
    let accentColor: Color
    let availableZoomFactors: [CGFloat]
    let currentZoom: CGFloat
    let onSelectZoom: (CGFloat) -> Void

    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 6) {
            if isExpanded {
                ForEach(availableZoomFactors, id: \.self) { factor in
                    Button(action: {
                        onSelectZoom(factor)
                        isExpanded = false
                    }) {
                        Text(String(format: "%.1fx", factor))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(currentZoom == factor ? accentColor : .white)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle().fill(currentZoom == factor ? .white.opacity(0.2) : .clear)
                            )
                    }
                }
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = true
                    }
                }) {
                    Text(String(format: "%.1f", currentZoom))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(isExpanded ? 4 : 0)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        // Zoom value changes are inherently a "selection" event — natural
        // alignment with .selection feedback. Fires when the chosen factor
        // changes (collapse-to-expand doesn't fire on its own — separate
        // trigger for that on `isExpanded` below).
        .sensoryFeedback(.selection, trigger: currentZoom)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }
}
