import Foundation
import SwiftUI
import Observation

/// A persistent manager to track media assets picked during the current app session.
/// Enables the "Recents/History" feature in the Unified Creator.
@MainActor
@Observable
public class MediaHistoryManager {
    public static let shared = MediaHistoryManager()
    
    public var history: [MediaItem] = []
    
    private init() {}
    
    /// Adds a unique item to the beginning of the history.
    public func addToHistory(_ items: [MediaItem]) {
        for item in items {
            // Check for duplicates based on thumbnail (simple approximation for session-only)
            if !history.contains(where: { $0.thumbnail == item.thumbnail }) {
                history.insert(item, at: 0)
            }
        }
        
        // Cap history at 50 items
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
    }
    
    public func clear() {
        history = []
    }
}
