import Foundation

/// A command bound for a TV, independent of how any particular brand encodes it.
enum RemoteCommand: Sendable {
    case key(RemoteKey, KeyAction)
    case text(String)
    case launch(appID: String)

    /// `press`/`release` bracket a hold; `click` is a discrete tap.
    enum KeyAction: String, Sendable {
        case click = "Click"
        case press = "Press"
        case release = "Release"
    }
}

/// One control channel to one TV.
///
/// The seam that keeps brand specifics out of the UI: `ConnectionManager` holds drivers,
/// not Samsung sessions, so adding LG's SSAP or Roku's ECP means writing a conformance
/// rather than touching the remote.
///
/// The requirement that shapes this protocol is `send(_:)` being **nonisolated and
/// synchronous**. A key press has to cost a queue push on the main thread — awaiting an
/// actor before the command is even queued would put a scheduling hop between the finger
/// and the wire, and could reorder keys held down in quick succession.
protocol TVDriver: Actor {
    /// Queue a command. Must not block, await, or throw.
    nonisolated func send(_ command: RemoteCommand)

    func start()

    /// Drop the connection but stay reusable.
    func stop()

    /// Permanent teardown, for a TV being removed.
    func shutdown()

    /// Reconnect now rather than waiting out the backoff — on foreground, or when the
    /// network path changes.
    func wake()

    /// Drop any stored credential so the next connection re-triggers the TV's prompt.
    func forgetToken()

    func currentState() -> TVConnectionState
}
