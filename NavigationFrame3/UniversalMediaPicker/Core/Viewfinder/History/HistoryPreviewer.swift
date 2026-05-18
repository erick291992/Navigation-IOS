import SwiftUI

struct HistoryPreviewer: View {
    let item: MediaItem?

    var body: some View {
        ZStack {
            if let item = item {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
            }
        }
    }
}
