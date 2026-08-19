import SwiftUI

// MARK: - Press behaviour

/// Drives a key from raw touch events rather than `Button`.
///
/// `Button` fires on touch-*up*, which on a remote reads as a lag of however long the
/// finger rests on the key — easily 100ms+ and the single biggest source of perceived
/// latency in remote apps. A real remote actuates on the way down, and so does this.
///
/// Holding repeats after a short delay, matching the auto-repeat of a physical remote.
struct KeyPressBehaviour: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void = {}
    var repeating: Bool = false
    @Binding var isPressed: Bool

    /// Long enough that a deliberate single press never repeats.
    private static let repeatDelay = Duration.milliseconds(400)
    /// Roughly the auto-repeat rate of the physical remote.
    private static let repeatInterval = Duration.milliseconds(90)

    @State private var repeatTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPress()
                        guard repeating else { return }
                        repeatTask = Task { @MainActor in
                            try? await Task.sleep(for: Self.repeatDelay)
                            var tick = 0
                            while !Task.isCancelled {
                                onPress()
                                tick += 1
                                // Every repeat buzzing is unpleasant; thin it out.
                                if tick.isMultiple(of: 3) { Haptics.shared.tick() }
                                try? await Task.sleep(for: Self.repeatInterval)
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                        onRelease()
                    }
            )
    }
}

extension View {
    func keyPress(
        isPressed: Binding<Bool>,
        repeating: Bool = false,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void = {}
    ) -> some View {
        modifier(KeyPressBehaviour(
            onPress: onPress, onRelease: onRelease,
            repeating: repeating, isPressed: isPressed
        ))
    }
}

// MARK: - Key face

/// What a key shows: an SF Symbol, a short label, or both stacked.
enum KeyFace: Hashable {
    case symbol(String)
    case text(String)
    case symbolWithCaption(String, String)
}

/// A single round key on the wand.
struct KeyButton: View {
    var face: KeyFace
    var tint: Color?
    var diameter: CGFloat = Theme.keyDiameter
    var repeating: Bool = false
    var accessibilityLabel: String
    var action: () -> Void

    @State private var isPressed = false

    var body: some View {
        content
            .frame(width: diameter, height: diameter)
            .glassEffect(glass, in: .circle)
            .scaleEffect(isPressed ? Theme.pressedScale : 1)
            .animation(isPressed ? Theme.press : Theme.release, value: isPressed)
            .keyPress(isPressed: $isPressed, repeating: repeating) {
                Haptics.shared.key()
                action()
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var glass: Glass {
        guard let tint else { return Glass.regular.interactive() }
        return Glass.regular.tint(tint.opacity(0.32)).interactive()
    }

    @ViewBuilder
    private var content: some View {
        switch face {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: diameter * 0.36, weight: .medium))
                .foregroundStyle(tint ?? .primary)
        case .text(let label):
            Text(label)
                .font(.system(size: diameter * 0.30, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? .primary)
        case .symbolWithCaption(let name, let caption):
            VStack(spacing: 2) {
                Image(systemName: name)
                    .font(.system(size: diameter * 0.30, weight: .medium))
                Text(caption)
                    .font(.system(size: diameter * 0.16, weight: .semibold))
            }
            .foregroundStyle(tint ?? .primary)
        }
    }
}

// MARK: - Navigation ring

/// The signature element of the Samsung wand: a wide circular ring of four directional
/// zones around a raised centre hub.
///
/// Built as one ring with four hit zones rather than four separate buttons, so it reads
/// as a single moulded piece of glass — and so a finger anywhere in a quadrant works,
/// which is how the physical ring behaves.
struct NavRing: View {
    var onDirection: (RemoteKey) -> Void
    var onSelect: () -> Void
    var onSelectLongPress: () -> Void = {}

    @State private var activeDirection: RemoteKey?
    @State private var hubPressed = false

    private let diameter = Theme.navRingDiameter
    private let hub = Theme.navHubDiameter

    var body: some View {
        ZStack {
            ring
            hubView
        }
        .frame(width: diameter, height: diameter)
    }

    /// The arrows live *inside* the glass view rather than layered over it. A
    /// `GlassEffectContainer` hoists glass into a shared compositing layer that draws
    /// above ordinary siblings, so anything stacked on top of a glass shape disappears.
    private var ring: some View {
        ZStack {
            ForEach(Direction.allCases) { direction in
                DirectionZone(
                    direction: direction,
                    diameter: diameter,
                    hub: hub,
                    isActive: activeDirection == direction.key,
                    onPress: {
                        activeDirection = direction.key
                        Haptics.shared.key()
                        onDirection(direction.key)
                    },
                    onRelease: { activeDirection = nil }
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .glassEffect(Glass.regular.interactive(), in: .circle)
    }

    private var hubView: some View {
        Text("OK")
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: hub, height: hub)
            .glassEffect(
                Glass.regular.tint(Theme.selectTint.opacity(0.28)).interactive(),
                in: .circle
            )
            .scaleEffect(hubPressed ? Theme.pressedScale : 1)
            .animation(hubPressed ? Theme.press : Theme.release, value: hubPressed)
            .keyPress(isPressed: $hubPressed) {
                Haptics.shared.confirm()
                onSelect()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                Haptics.shared.change()
                onSelectLongPress()
            }
            .accessibilityElement()
            .accessibilityLabel("Select")
            .accessibilityAddTraits(.isButton)
    }

    enum Direction: String, CaseIterable, Identifiable {
        case up, down, left, right
        var id: String { rawValue }

        var key: RemoteKey {
            switch self {
            case .up: .up
            case .down: .down
            case .left: .left
            case .right: .right
            }
        }
        var symbol: String {
            switch self {
            case .up: "chevron.up"
            case .down: "chevron.down"
            case .left: "chevron.left"
            case .right: "chevron.right"
            }
        }
        var alignment: Alignment {
            switch self {
            case .up: .top
            case .down: .bottom
            case .left: .leading
            case .right: .trailing
            }
        }
    }

    /// One quadrant of the ring. The hit area is a generous rectangle reaching from the
    /// hub to the outer edge, so pressing "somewhere up" always registers as up.
    private struct DirectionZone: View {
        let direction: Direction
        let diameter: CGFloat
        let hub: CGFloat
        let isActive: Bool
        let onPress: () -> Void
        let onRelease: () -> Void

        @State private var isPressed = false

        var body: some View {
            let armLength = (diameter - hub) / 2
            let isVertical = direction == .up || direction == .down

            Image(systemName: direction.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary.opacity(isActive ? 1 : 0.7))
                .frame(
                    width: isVertical ? diameter * 0.42 : armLength,
                    height: isVertical ? armLength : diameter * 0.42
                )
                .background(
                    Circle()
                        .fill(.white.opacity(isActive ? 0.14 : 0))
                        .frame(width: 54, height: 54)
                )
                .frame(width: diameter, height: diameter, alignment: direction.alignment)
                .scaleEffect(isActive ? 0.94 : 1)
                .animation(isActive ? Theme.press : Theme.release, value: isActive)
                .keyPress(isPressed: $isPressed, repeating: true, onPress: onPress, onRelease: onRelease)
                .accessibilityElement()
                .accessibilityLabel(direction.rawValue.capitalized)
                .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - Rocker

/// The volume and channel rockers: a tall capsule that tips at either end, with the
/// middle acting as its own key — mute on volume, guide on channel, exactly as on the
/// physical remote.
struct Rocker: View {
    var topSymbol: String
    var bottomSymbol: String
    var centerFace: KeyFace
    var caption: String
    var topKey: RemoteKey
    var bottomKey: RemoteKey
    var centerAction: () -> Void
    var onKey: (RemoteKey) -> Void

    @State private var topPressed = false
    @State private var bottomPressed = false
    @State private var centerPressed = false

    var body: some View {
        VStack(spacing: 0) {
            end(symbol: topSymbol, key: topKey, isPressed: $topPressed, label: "\(caption) up")
            center
            end(symbol: bottomSymbol, key: bottomKey, isPressed: $bottomPressed, label: "\(caption) down")
        }
        .frame(width: Theme.rockerWidth, height: Theme.rockerHeight)
        .glassEffect(Glass.regular.interactive(), in: .capsule)
    }

    private func end(symbol: String, key: RemoteKey, isPressed: Binding<Bool>, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .scaleEffect(isPressed.wrappedValue ? 0.88 : 1)
            .animation(isPressed.wrappedValue ? Theme.press : Theme.release, value: isPressed.wrappedValue)
            .keyPress(isPressed: isPressed, repeating: true) {
                Haptics.shared.key()
                onKey(key)
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var center: some View {
        Group {
            switch centerFace {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 17, weight: .semibold))
            case .text(let label):
                Text(label).font(.system(size: 12, weight: .bold, design: .rounded))
            case .symbolWithCaption(let name, _):
                Image(systemName: name).font(.system(size: 17, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .contentShape(.rect)
        .scaleEffect(centerPressed ? 0.9 : 1)
        .animation(centerPressed ? Theme.press : Theme.release, value: centerPressed)
        .keyPress(isPressed: $centerPressed) {
            Haptics.shared.confirm()
            centerAction()
        }
        .accessibilityElement()
        .accessibilityLabel(caption == "Volume" ? "Mute" : "Guide")
        .accessibilityAddTraits(.isButton)
    }
}
