import SwiftUI

/// Dumb album-picker menu. No ViewModel dependency.
///
/// Takes the album list as a `let` parameter and writes the user's choice
/// back through `currentAlbum: Binding<PhotoLibraryService.AlbumInfo?>` —
/// the same shape Apple's `Picker(selection:)` uses. Parent owns the source
/// of truth; this component just renders + writes through the binding.
///
/// When `albums.isEmpty`, the component renders a loading affordance:
/// "Recents" label + small spinner, faded + tap-disabled. As soon as
/// `albums` populates (via the `@Observable` cascade from `PhotoKitService`),
/// the spinner is replaced by a chevron and the menu becomes interactive.
struct AlbumDropdownMenu: View {
    let albums: [PhotoLibraryService.AlbumInfo]
    @Binding var currentAlbum: PhotoLibraryService.AlbumInfo?

    private var isLoading: Bool { albums.isEmpty }

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

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.6))
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .opacity(isLoading ? 0.5 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isLoading)
        }
        .disabled(isLoading)
    }
}
