import SwiftUI
import Photos

struct AlbumDropdownMenu: View {
    @Bindable var viewModel: AssetGridViewModel
    
    var body: some View {
        Menu {
            ForEach(viewModel.state.albums, id: \.id) { album in
                Button(action: { viewModel.trigger(.selectAlbum(album)) }) {
                    HStack {
                        Text(album.title)
                        Spacer()
                        if viewModel.state.currentAlbum?.id == album.id {
                            Image(systemName: "checkmark")
                        }
                        Image(systemName: album.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.state.currentAlbum?.title ?? "Recents")
                    .font(.system(size: 16, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
        }
    }
}
