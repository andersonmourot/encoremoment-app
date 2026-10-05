import SwiftUI
import EncoreMomentCore

/// A creator's avatar: their uploaded photo, or a initials monogram when they
/// haven't set one. The monogram's color is derived from the creator id so the
/// same account always renders the same color.
struct AvatarView: View {
    let creator: Creator
    var size: CGFloat = 44

    var body: some View {
        if creator.avatarURL == nil {
            InitialsAvatarView(name: creator.displayName, seed: creator.id, size: size)
        } else {
            RemoteImage(url: creator.avatarURL)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }
}

/// Letter monogram on a hash-colored gradient disc.
struct InitialsAvatarView: View {
    let name: String
    let seed: UUID
    var size: CGFloat = 44

    private static let palettes: [(Color, Color)] = [
        (Color(hex: "6638EA"), Color(hex: "3D1F9E")),
        (Color(hex: "0A84FF"), Color(hex: "0648A8")),
        (Color(hex: "FF2D8D"), Color(hex: "B3125E")),
        (Color(hex: "FF7A1A"), Color(hex: "B34800")),
        (Color(hex: "30D158"), Color(hex: "1B7A35")),
    ]

    private var palette: (Color, Color) {
        Self.palettes[abs(seed.uuidString.hashValue) % Self.palettes.count]
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first).map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [palette.0, palette.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("\(name) avatar")
    }
}
