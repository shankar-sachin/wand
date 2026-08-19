import UIKit

/// Touch feedback for the remote.
///
/// Generators are warmed up front and re-warmed on foreground. A cold
/// `UIFeedbackGenerator` pays a Taptic Engine spin-up on its first fire — tens of
/// milliseconds, felt as exactly the lag this app is trying to eliminate.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notice = UINotificationFeedbackGenerator()

    /// Off disables every call site at once.
    var enabled = true

    private init() { warm() }

    func warm() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
        selection.prepare()
    }

    /// A standard key press.
    func key() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.7)
        rigid.prepare()
    }

    /// The nav ring's centre and other confirming actions.
    func confirm() {
        guard enabled else { return }
        medium.impactOccurred()
        medium.prepare()
    }

    /// Used for repeat ticks while a key is held — thinned out by the caller, since a
    /// tap on every repeat becomes a buzz.
    func tick() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.45)
        light.prepare()
    }

    /// Moving between TVs or list rows.
    func change() {
        guard enabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    func success() {
        guard enabled else { return }
        notice.notificationOccurred(.success)
    }

    func failure() {
        guard enabled else { return }
        notice.notificationOccurred(.error)
    }
}
