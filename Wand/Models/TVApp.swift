import SwiftUI

/// A launchable TV app.
///
/// Samsung changed app IDs around 2020 and several apps carry more than one, so each
/// entry holds ordered candidates. Newest-first: `SamsungREST.resolveAppID` probes them
/// against the TV and caches whichever one actually reports as installed.
struct TVApp: Identifiable, Hashable, Sendable {
    var id: String { key }
    /// Stable key used in `TVDevice.appSlots` and in persistence — never the numeric ID,
    /// which varies per TV generation.
    var key: String
    var name: String
    var candidateIDs: [String]
    var glyph: Glyph
    var tint: Color

    /// How the button face is drawn.
    ///
    /// `logo` names a vector asset in the catalog. Single-colour marks are stored as
    /// template images and tinted with the brand colour; full-colour wordmarks keep
    /// their own artwork. Anything without a real logo falls back to a symbol.
    enum Glyph: Hashable, Sendable {
        /// A brand vector rendered in `tint`.
        case tintedLogo(String)
        /// A brand vector that carries its own colours.
        case colourLogo(String)
        case symbol(String)
        case letter(String)

        /// Wordmarks are much wider than they are tall and need a wider box to read.
        var isWordmark: Bool {
            switch self {
            case .colourLogo: true
            default: false
            }
        }
    }

    static let defaultSlotKeys = ["youtube", "netflix", "primevideo", "disneyplus"]

    /// Ordered so the default four lead: YouTube, Netflix, Prime Video, Disney+.
    static let catalog: [TVApp] = [
        TVApp(key: "youtube", name: "YouTube",
              candidateIDs: ["111299001912"],
              glyph: .tintedLogo("logo-youtube"),
              tint: Color(red: 1.0, green: 0.0, blue: 0.0)),
        TVApp(key: "netflix", name: "Netflix",
              candidateIDs: ["3201907018807", "11101200001"],
              glyph: .tintedLogo("logo-netflix"),
              tint: Color(red: 0.898, green: 0.043, blue: 0.094)),
        TVApp(key: "primevideo", name: "Prime Video",
              candidateIDs: ["3201910019365", "3201512006785"],
              glyph: .colourLogo("logo-primevideo"),
              tint: Color(red: 0.0, green: 0.66, blue: 0.87)),
        TVApp(key: "disneyplus", name: "Disney+",
              candidateIDs: ["3202204027038", "3202009021709", "3201901017640"],
              glyph: .colourLogo("logo-disneyplus"),
              tint: Color(red: 0.07, green: 0.13, blue: 0.42)),
        TVApp(key: "appletv", name: "Apple TV",
              candidateIDs: ["3201807016597"],
              glyph: .tintedLogo("logo-appletv"),
              tint: Color(white: 0.15)),
        TVApp(key: "max", name: "Max",
              candidateIDs: ["3202301029760"],
              glyph: .tintedLogo("logo-max"),
              tint: Color(red: 0.0, green: 0.13, blue: 0.85)),
        TVApp(key: "hbomax", name: "HBO Max",
              candidateIDs: ["3201601007230"],
              glyph: .tintedLogo("logo-hbomax"),
              tint: Color(red: 0.35, green: 0.0, blue: 0.75)),
        TVApp(key: "hulu", name: "Hulu",
              candidateIDs: ["3201601007625"],
              glyph: .colourLogo("logo-hulu"),
              tint: Color(red: 0.10, green: 0.87, blue: 0.45)),
        TVApp(key: "spotify", name: "Spotify",
              candidateIDs: ["3201606009684"],
              glyph: .tintedLogo("logo-spotify"),
              tint: Color(red: 0.11, green: 0.73, blue: 0.33)),
        TVApp(key: "samsungtvplus", name: "Samsung TV Plus",
              candidateIDs: ["3201601007250"],
              glyph: .tintedLogo("logo-samsungtvplus"),
              tint: Color(red: 0.08, green: 0.35, blue: 0.85)),
        TVApp(key: "plex", name: "Plex",
              candidateIDs: ["3201512006963"],
              glyph: .tintedLogo("logo-plex"),
              tint: Color(red: 0.90, green: 0.62, blue: 0.06)),
        TVApp(key: "browser", name: "Web Browser",
              candidateIDs: ["org.tizen.browser"],
              glyph: .symbol("globe"),
              tint: Color(red: 0.35, green: 0.55, blue: 0.95)),
    ]

    static func app(forKey key: String) -> TVApp? {
        catalog.first { $0.key == key }
    }
}
