import Foundation

/// Decides when repeated connection failures mean "the TV revoked our pairing" rather
/// than "the TV isn't there right now".
///
/// This distinction is the difference between a remote that pairs once and one that makes
/// you walk to the TV and press Allow every time it wakes. From the client's point of
/// view a sleeping TV, a Wi-Fi handoff, a TV still booting Tizen, and a genuinely revoked
/// pairing are indistinguishable — each is a socket that opens and dies within a second
/// or two. Treating any of them as revocation throws away a credential that cost the user
/// a trip across the room.
///
/// So the bar is deliberately high: several fast failures in a row, *and* the TV must be
/// reachable over its REST port (the caller checks that), and even then the token is kept
/// and the user is offered a deliberate re-pair.
struct RevocationHeuristic: Equatable, Sendable {

    /// Failures below this are treated as an absent TV, not a bad credential.
    static let threshold = 3

    private(set) var consecutiveFastFailures = 0

    /// Records a dropped connection. Returns `true` when the pattern is suspicious enough
    /// to be worth checking whether the TV is actually awake.
    ///
    /// - Parameters:
    ///   - diedFast: the socket closed within a couple of seconds of being opened.
    ///   - holdingToken: we presented a stored token on this attempt. Without one there is
    ///     no pairing to have been revoked.
    mutating func recordFailure(diedFast: Bool, holdingToken: Bool) -> Bool {
        guard diedFast, holdingToken else {
            consecutiveFastFailures = 0
            return false
        }
        consecutiveFastFailures += 1
        guard consecutiveFastFailures >= Self.threshold else { return false }
        consecutiveFastFailures = 0
        return true
    }

    /// Any successful connection clears the suspicion.
    mutating func recordSuccess() {
        consecutiveFastFailures = 0
    }
}
