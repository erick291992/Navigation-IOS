import Foundation
import SwiftUI
import Observation

/// A persistent manager to track media assets picked during the current app session.
/// Enables the "Recents/History" feature in the Unified Creator.
@MainActor
@Observable
public final class MediaHistoryManager {
    public static let shared = MediaHistoryManager()
    
    public var history: [MediaItem] = []
    
    private init() {}
    
    /// Adds a unique item to the beginning of the history.
    public func addToHistory(_ items: [MediaItem]) {
        for item in items {
            // Content-based de-dup via MediaItem's custom Equatable (data +
            // contentType + originalURL). Same picture re-processed in
            // separate calls compares equal even though `id` differs.
            if !history.contains(item) {
                history.insert(item, at: 0)
            }
        }

        if history.count > 50 {
            history = Array(history.prefix(50))
        }
    }
    
    public func clear() {
        history = []
    }
}
