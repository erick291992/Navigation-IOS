import SwiftUI

/// Dumb album-picker menu. No ViewModel dependency.
///
/// Takes the album list as a `let` parameter and writes the user's choice
/// back through `currentAlbum: Binding<PhotoLibraryService.AlbumInfo?>` —
/// the same shape Apple's `Picker(selection:)` uses. Parent owns the source
/// of truth; this component just renders + writes through the binding.
struct AlbumDropdownMenu: View {
    let albums: [PhotoLibraryService.AlbumInfo]
    @Binding var currentAlbum: PhotoLibraryService.AlbumInfo?

    var body: some View {
        Menu {
            ForEach(albums, id: \.id) { album in
                Button(action: { currentAlbum = album }) {
                    HStack {
                        Text(album.title)
                        Spacer()
                        if currentAlbum?.id == album.id {
                            Image(systemName: "checkmark")
                        }
                        Image(systemName: album.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentAlbum?.title ?? "Recents")
                    .font(.system(size: 16, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
        }
    }
}
