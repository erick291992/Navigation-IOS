import SwiftUI

public struct PermissionNeededView: View {
    public enum PermissionType { case library, camera }
    public let type: PermissionType
    public var accentColor: Color

    public init(type: PermissionType, accentColor: Color = .blue) {
        self.type = type
        self.accentColor = accentColor
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: type == .library ? "photo.on.rectangle.angled" : "camera.shutter.button")
                .font(.system(size: 80))
                .foregroundStyle(accentColor)

            VStack(spacing: 8) {
                Text(type == .library ? "Allow Access to Photos" : "Allow Access to Camera")
                    .font(.title2.bold())
                Text(type == .library ? "This lets you share photos from your library." : "This lets you take photos and record videos.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.headline.bold())
            .foregroundColor(accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundColor(.white)
    }
}
