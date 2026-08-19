import SwiftUI

/// A swipe pad for navigating TV menus.
///
/// Deliberately translates gestures into arrow keys rather than using Samsung's mouse
/// protocol, which is inconsistently implemented across firmware. Direction keys work on
/// every model, and flicking through a grid is far quicker than tapping arrows — a long
/// swipe emits several steps in proportion to its length.
struct TrackpadView: View {
    @Environment(ConnectionManager.self) private var connections

    /// Distance that constitutes one step of movement.
    private static let stepDistance: CGFloat = 34
    /// Cap per gesture, so a careless flick doesn't run away down a long list.
    private static let maxSteps = 8

    @State private var accumulated: CGSize = .zero
    @State private var emittedSteps = 0
    @State private var ripple: CGPoint?

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Swipe to move\nTap to select")
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .allowsHitTesting(false)

            if let ripple {
                Circle()
                    .fill(Theme.selectTint.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .position(ripple)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(Glass.regular.interactive(), in: .circle)
        .contentShape(.circle)
        .gesture(swipe)
        .onTapGesture { location in
            Haptics.shared.confirm()
            show(ripple: location)
            connections.press(.select)
        }
        .accessibilityElement()
        .accessibilityLabel("Swipe pad")
        .accessibilityHint("Swipe to move, tap to select, swipe with two fingers for back")
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let dx = value.translation.width - accumulated.width
                let dy = value.translation.height - accumulated.height

                // One axis at a time: diagonal drift on a TV grid is disorienting.
                if abs(dx) > abs(dy) {
                    guard abs(dx) >= Self.stepDistance else { return }
                    emit(dx > 0 ? .right : .left)
                    accumulated.width += dx > 0 ? Self.stepDistance : -Self.stepDistance
                } else {
                    guard abs(dy) >= Self.stepDistance else { return }
                    emit(dy > 0 ? .down : .up)
                    accumulated.height += dy > 0 ? Self.stepDistance : -Self.stepDistance
                }
            }
            .onEnded { _ in
                accumulated = .zero
                emittedSteps = 0
            }
    }

    private func emit(_ key: RemoteKey) {
        guard emittedSteps < Self.maxSteps else { return }
        emittedSteps += 1
        Haptics.shared.tick()
        connections.press(key)
    }

    private func show(ripple location: CGPoint) {
        withAnimation(.easeOut(duration: 0.18)) { ripple = location }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.25)) { ripple = nil }
        }
    }
}
