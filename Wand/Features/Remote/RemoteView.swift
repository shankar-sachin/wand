import SwiftUI

/// The wand.
///
/// Laid out at a fixed design size and uniformly scaled to the screen, so every iPhone
/// gets the same proportions rather than a reflowed layout — the remote is a physical
/// object and should not rearrange itself. It never scrolls.
struct RemoteView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections

    @State private var padMode: PadMode = .ring
    @State private var sheet: RemoteSheet?
    /// The wand's natural height, measured at runtime and scaled to fit the screen.
    @State private var contentHeight: CGFloat = Theme.designHeight

    enum PadMode: String, CaseIterable { case ring, trackpad }

    enum RemoteSheet: String, Identifiable {
        case numbers, keyboard, apps, devices, settings
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { proxy in
            // Scale the wand's *measured* height, not a guessed constant — guessing meant
            // the content overflowed and clipped at the notch and the home indicator.
            // The safe-area inset is already excluded from proxy.size.
            let scale = min(
                proxy.size.width / Theme.designWidth,
                contentHeight > 0 ? proxy.size.height / contentHeight : 1
            )

            wand
                .frame(width: Theme.designWidth)
                .fixedSize(horizontal: false, vertical: true)
                // Measured before the scale is applied, so this can't feed back on itself.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .scaleEffect(scale, anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .numbers: NumberPadView().presentationDetents([.medium])
            case .keyboard: KeyboardEntryView().presentationDetents([.height(260)])
            case .apps: AllAppsView()
            case .devices: DeviceListView()
            case .settings: SettingsView()
            }
        }
    }

    // MARK: Body

    private var wand: some View {
        // One container for the whole remote: adjacent keys then refract as a single
        // moulded piece of glass instead of thirty unrelated blobs, which is both the
        // correct look and materially cheaper to composite.
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 0) {
                DeviceSwitcherBar(onManage: { sheet = .devices },
                                  onSettings: { sheet = .settings })
                    .padding(.bottom, 18)

                topKeys
                    .padding(.bottom, 14)

                secondaryKeys
                    .padding(.bottom, 16)

                padArea
                    .padding(.bottom, 16)

                actionKeys
                    .padding(.bottom, 18)

                rockers
                    .padding(.bottom, 18)

                AppLauncherRow(onShowAll: { sheet = .apps })
            }
            .frame(width: Theme.designWidth)
        }
    }

    // MARK: Rows

    /// Power and voice, as on the physical remote.
    private var topKeys: some View {
        HStack {
            KeyButton(
                face: .symbol("power"),
                tint: Theme.powerTint,
                accessibilityLabel: "Power"
            ) {
                connections.togglePower()
            }

            Spacer()

            KeyButton(
                face: .symbol("mic.fill"),
                tint: Theme.micTint,
                accessibilityLabel: "Voice search"
            ) {
                // The TV's own voice service isn't reachable over this protocol, so the
                // mic key opens text entry instead — which is faster than dictating at a
                // TV anyway, and lands in the same search fields.
                sheet = .keyboard
            }
        }
        .padding(.horizontal, 34)
    }

    /// The number key and the colour key, plus the pad-mode toggle.
    private var secondaryKeys: some View {
        HStack {
            KeyButton(
                face: .text("123"),
                tint: nil,
                accessibilityLabel: "Numbers"
            ) {
                sheet = .numbers
            }

            Spacer()

            PadModeToggle(mode: $padMode)

            Spacer()

            ColourKey { key in
                connections.press(key)
            }
        }
        .padding(.horizontal, 34)
    }

    @ViewBuilder
    private var padArea: some View {
        switch padMode {
        case .ring:
            NavRing(
                onDirection: { connections.press($0) },
                onSelect: { connections.press(.select) },
                onSelectLongPress: { connections.press(.source) }
            )
            .transition(.scale.combined(with: .opacity))
        case .trackpad:
            TrackpadView()
                .frame(width: Theme.navRingDiameter, height: Theme.navRingDiameter)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var actionKeys: some View {
        HStack {
            KeyButton(face: .symbol("arrow.uturn.backward"), accessibilityLabel: "Back") {
                connections.press(.back)
            }
            Spacer()
            KeyButton(face: .symbol("house.fill"), accessibilityLabel: "Home") {
                connections.press(.home)
            }
            Spacer()
            KeyButton(face: .symbol("playpause.fill"), accessibilityLabel: "Play or pause") {
                connections.press(.playPause)
            }
        }
        .padding(.horizontal, 30)
    }

    private var rockers: some View {
        HStack {
            Rocker(
                topSymbol: "plus",
                bottomSymbol: "minus",
                centerFace: .symbol("speaker.slash.fill"),
                caption: "Volume",
                topKey: .volumeUp,
                bottomKey: .volumeDown,
                centerAction: { connections.press(.mute) },
                onKey: { connections.press($0) }
            )

            Spacer()

            Rocker(
                topSymbol: "chevron.up",
                bottomSymbol: "chevron.down",
                centerFace: .text("GUIDE"),
                caption: "Channel",
                topKey: .channelUp,
                bottomKey: .channelDown,
                centerAction: { connections.press(.guide) },
                onKey: { connections.press($0) }
            )
        }
        .padding(.horizontal, 42)
    }
}

// MARK: - Pad mode toggle

/// Swaps the navigation ring for the swipe pad. Small and unobtrusive so the authentic
/// face is what reads first.
private struct PadModeToggle: View {
    @Binding var mode: RemoteView.PadMode

    var body: some View {
        HStack(spacing: 2) {
            option(.ring, symbol: "circle.circle")
            option(.trackpad, symbol: "hand.draw")
        }
        .padding(4)
        .glassEffect(Glass.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pad style")
    }

    private func option(_ value: RemoteView.PadMode, symbol: String) -> some View {
        let selected = mode == value
        return Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(width: 34, height: 26)
            .background {
                if selected {
                    Capsule().fill(.primary.opacity(0.12))
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                Haptics.shared.change()
                withAnimation(Theme.morph) { mode = value }
            }
            .accessibilityLabel(value == .ring ? "Directional ring" : "Swipe pad")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Colour key

/// The physical remote's four-dot colour key: one button that opens the four coloured
/// keys, which are used by broadcast and teletext features.
private struct ColourKey: View {
    var onKey: (RemoteKey) -> Void

    @State private var expanded = false
    @State private var isPressed = false

    private let colours: [(RemoteKey, Color)] = [
        (.red, Theme.colourKeyRed),
        (.green, Theme.colourKeyGreen),
        (.yellow, Theme.colourKeyYellow),
        (.blue, Theme.colourKeyBlue),
    ]

    var body: some View {
        dots
            .frame(width: Theme.keyDiameter, height: Theme.keyDiameter)
            .glassEffect(Glass.regular.interactive(), in: .circle)
            .scaleEffect(isPressed ? Theme.pressedScale : 1)
            .animation(isPressed ? Theme.press : Theme.release, value: isPressed)
            .keyPress(isPressed: $isPressed) {
                Haptics.shared.key()
                withAnimation(Theme.morph) { expanded.toggle() }
            }
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                HStack(spacing: 14) {
                    ForEach(colours, id: \.0) { key, colour in
                        Circle()
                            .fill(colour)
                            .frame(width: 34, height: 34)
                            .contentShape(.circle)
                            .onTapGesture {
                                Haptics.shared.key()
                                onKey(key)
                                expanded = false
                            }
                            .accessibilityLabel("\(key.rawValue.dropFirst(4).capitalized) key")
                    }
                }
                .padding(18)
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityElement()
            .accessibilityLabel("Colour keys")
            .accessibilityAddTraits(.isButton)
    }

    private var dots: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                dot(Theme.colourKeyRed)
                dot(Theme.colourKeyGreen)
            }
            HStack(spacing: 4) {
                dot(Theme.colourKeyYellow)
                dot(Theme.colourKeyBlue)
            }
        }
    }

    private func dot(_ colour: Color) -> some View {
        Circle().fill(colour).frame(width: 11, height: 11)
    }
}
