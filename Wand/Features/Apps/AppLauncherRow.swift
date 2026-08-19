import SwiftUI

/// The four app shortcut keys along the bottom of the wand, plus the way into everything
/// else. Order and contents come from `TVDevice.appSlots`, defaulting to
/// YouTube, Netflix, Prime Video, Disney+.
struct AppLauncherRow: View {
    var onShowAll: () -> Void

    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections
    @Environment(AppResolver.self) private var resolver

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(slots, id: \.key) { app in
                    AppSlotButton(app: app) {
                        connections.launch(app: app, resolvedID: resolver.resolvedID(for: app))
                    }
                }
            }

            Button {
                Haptics.shared.change()
                onShowAll()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("All Apps")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .glassEffect(Glass.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
    }

    private var slots: [TVApp] {
        let keys = store.activeDevice?.appSlots ?? TVApp.defaultSlotKeys
        return keys.compactMap { TVApp.app(forKey: $0) }
    }
}

/// One app key. Brand logos aren't bundled — each app gets a mark built from a symbol or
/// letterform in its brand colour, which stays legible on glass in both schemes.
struct AppSlotButton: View {
    var app: TVApp
    var action: () -> Void

    @State private var isPressed = false

    var body: some View {
        // Logo only, as on the physical remote — the wordmarks already say the name, and
        // a caption underneath just crowds the key.
        AppGlyph(app: app, size: 20)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.appButtonHeight)
            .glassEffect(glass, in: .rect(cornerRadius: 16))
            .scaleEffect(isPressed ? Theme.pressedScale : 1)
            .animation(isPressed ? Theme.press : Theme.release, value: isPressed)
            .keyPress(isPressed: $isPressed) {
                Haptics.shared.confirm()
                action()
            }
                .accessibilityElement()
            .accessibilityLabel("Open \(app.name)")
            .accessibilityAddTraits(.isButton)
    }

    /// Full-colour wordmarks carry their own contrast and only need a faint plate; the
    /// tinted single-colour marks read better against a stronger wash of their brand hue.
    private var glass: Glass {
        let strength = app.glyph.isWordmark ? 0.30 : 0.22
        return Glass.regular.tint(app.tint.opacity(strength)).interactive()
    }
}

struct AppGlyph: View {
    var app: TVApp
    var size: CGFloat

    var body: some View {
        switch app.glyph {
        case .tintedLogo(let asset):
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(app.tint)
        case .colourLogo(let asset):
            // Wordmarks are wide; give them the room to stay legible rather than
            // squeezing them into a square the size of an icon.
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size * 3.2, maxHeight: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(app.tint)
        case .letter(let text):
            Text(text)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(app.tint)
        }
    }
}
