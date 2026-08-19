import SwiftUI

/// Colours, metrics and motion for the remote.
///
/// The palette is deliberately restrained: Liquid Glass takes its character from what it
/// refracts, so the backdrop carries the colour and the keys stay near-neutral. Only the
/// keys that are colour-coded on the physical remote (power, the colour keys, the app
/// buttons) get a tint.
enum Theme {

    // MARK: Accents

    /// Samsung's power key is red on the physical wand.
    static let powerTint = Color(red: 0.96, green: 0.26, blue: 0.24)
    static let micTint = Color(red: 0.42, green: 0.62, blue: 1.0)
    static let selectTint = Color(red: 0.38, green: 0.56, blue: 1.0)

    static let colourKeyRed = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let colourKeyGreen = Color(red: 0.30, green: 0.80, blue: 0.44)
    static let colourKeyYellow = Color(red: 0.98, green: 0.78, blue: 0.24)
    static let colourKeyBlue = Color(red: 0.31, green: 0.55, blue: 0.96)

    // MARK: Metrics
    //
    // Proportions follow the physical Smart Remote: a tall narrow wand with a dominant
    // navigation ring roughly a third of the body width, and rockers noticeably taller
    // than they are wide.

    /// The layout is authored at this width and uniformly scaled to fit the screen, so
    /// every iPhone gets identical proportions rather than a reflowed layout.
    static let designWidth: CGFloat = 320
    static let designHeight: CGFloat = 640

    static let keyDiameter: CGFloat = 62
    static let navRingDiameter: CGFloat = 212
    static let navHubDiameter: CGFloat = 92
    static let rockerWidth: CGFloat = 76
    static let rockerHeight: CGFloat = 170
    static let appButtonHeight: CGFloat = 50

    // MARK: Motion
    //
    // Fast and slightly springy. Anything slower than ~0.16s starts to read as lag even
    // when the command has already gone out.

    static let press = Animation.spring(response: 0.16, dampingFraction: 0.62)
    static let release = Animation.spring(response: 0.28, dampingFraction: 0.75)
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.82)

    static let pressedScale: CGFloat = 0.93

    // MARK: Backdrop

    /// The ambient wash behind the remote.
    ///
    /// Glass needs something to refract — on a flat background the material reads as grey
    /// plastic. This stays subtle enough not to compete with the keys, and is defined for
    /// both schemes so light mode isn't just dark mode inverted.
    struct Backdrop: View {
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            ZStack {
                (scheme == .dark ? Color(white: 0.05) : Color(white: 0.94))
                    .ignoresSafeArea()

                // Two offset radial pools give the glass a gradient to bend, and read as
                // depth rather than as a visible gradient.
                RadialGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.16, green: 0.22, blue: 0.42).opacity(0.85), .clear]
                        : [Color(red: 0.58, green: 0.72, blue: 1.0).opacity(0.55), .clear],
                    center: .init(x: 0.14, y: 0.10),
                    startRadius: 0,
                    endRadius: 460
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.30, green: 0.14, blue: 0.36).opacity(0.7), .clear]
                        : [Color(red: 0.98, green: 0.80, blue: 0.86).opacity(0.6), .clear],
                    center: .init(x: 0.92, y: 0.86),
                    startRadius: 0,
                    endRadius: 520
                )
                .ignoresSafeArea()
            }
        }
    }
}

/// User-selectable appearance, persisted in `AppStorage`.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
