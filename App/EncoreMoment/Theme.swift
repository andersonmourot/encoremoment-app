import SwiftUI

extension Color {
    /// App accent. Defined in code so the project works without asset-catalog colors,
    /// and mirrored by the `AccentColor` asset for the app icon tint.
    static let appAccent = Color(red: 0.40, green: 0.22, blue: 0.92)

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(cleaned, radix: 16) ?? 0x6638EA
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
    case encorePurple = "6638EA"
    case oceanBlue = "0A84FF"
    case neonPink = "FF2D8D"
    case sunsetOrange = "FF7A1A"
    case mintGreen = "30D158"
    case gold = "FFD60A"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .encorePurple: "Encore Purple"
        case .oceanBlue: "Ocean Blue"
        case .neonPink: "Neon Pink"
        case .sunsetOrange: "Sunset Orange"
        case .mintGreen: "Mint Green"
        case .gold: "Gold"
        }
    }

    var color: Color { Color(hex: rawValue) }

    static func normalized(_ hex: String?) -> String {
        guard let hex,
              let match = Self(rawValue: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()) else {
            return Self.encorePurple.rawValue
        }
        return match.rawValue
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    static let storageKey = "appTheme"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.storageKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: AppTheme.storageKey)
        self.theme = raw.flatMap(AppTheme.init(rawValue:)) ?? .light
    }
}

extension DateFormatter {
    static let eventDay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

extension Date {
    var eventDayString: String { DateFormatter.eventDay.string(from: self) }
}
