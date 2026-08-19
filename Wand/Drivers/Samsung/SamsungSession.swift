import Foundation
import os

/// One long-lived control channel to a single Samsung TV.
///
/// Two guarantees shape the entire design:
///
/// 1. **`send(_:)` never blocks and never awaits.** It is `nonisolated` and does nothing
///    but hand a command to an `AsyncStream`, so a button tap costs one queue push on the
///    main thread — no actor hop, no per-press `Task` allocation, no network wait. That
///    also preserves key order, which spawning a task per press would not.
/// 2. **The socket is open before the first press.** `ConnectionManager` starts sessions
///    at launch rather than when a view appears, and this actor keeps the socket alive
///    with pings and reconnects with backoff, so a keypress almost never pays setup cost.
actor SamsungSession: TVDriver {

    // MARK: Stored state

    /// Connection problems are invisible from the UI — a grey dot looks the same whether
    /// the TV is asleep, refusing us, or holding a stale client entry. This is how those
    /// get told apart.
    private static let log = Logger(subsystem: "com.sachi.wand", category: "session")

    private let device: TVDevice
    private let urlSession: URLSession
    private let trustDelegate: TVTrustDelegate

    private let stream: AsyncStream<RemoteCommand>
    /// `nonisolated` so `send(_:)` can reach it without hopping onto the actor.
    private nonisolated let outbox: AsyncStream<RemoteCommand>.Continuation

    private let onStateChange: @Sendable (TVConnectionState) -> Void
    private let onToken: @Sendable (String) -> Void
    private let onLatency: @Sendable (Duration) -> Void
    /// Fired when the TV is awake but keeps dropping a tokened connection — the
    /// only honest signal that a pairing was revoked at the TV.
    private let onRevocationSuspected: @Sendable () -> Void

    private var socket: URLSessionWebSocketTask?
    private var token: String?
    private var state: TVConnectionState = .offline
    private var attemptStartedAt: ContinuousClock.Instant?
    /// Tells a revoked pairing apart from an absent TV — see `RevocationHeuristic`.
    private var revocation = RevocationHeuristic()
    private var attempt = 0

    private var pumpTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var stopped = true
    /// True while a connection attempt is actually in flight. `wake()` must not interrupt
    /// one — see the comment there.
    private var isAttempting = false

    // MARK: Init

    init(
        device: TVDevice,
        token: String?,
        onStateChange: @escaping @Sendable (TVConnectionState) -> Void,
        onToken: @escaping @Sendable (String) -> Void,
        onLatency: @escaping @Sendable (Duration) -> Void = { _ in },
        onRevocationSuspected: @escaping @Sendable () -> Void = {}
    ) {
        self.device = device
        self.token = token
        self.onStateChange = onStateChange
        self.onToken = onToken
        self.onLatency = onLatency
        self.onRevocationSuspected = onRevocationSuspected

        self.trustDelegate = TVTrustDelegate(host: device.host)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        config.allowsCellularAccess = false
        // One session reused across reconnects; creating one per attempt leaks until
        // invalidated, and URLSession holds its delegate strongly.
        self.urlSession = URLSession(configuration: config, delegate: trustDelegate, delegateQueue: nil)

        // `bufferingNewest` means keys pressed during a blip queue in order and flush the
        // moment the socket returns, instead of being dropped or blocking the UI.
        var continuation: AsyncStream<RemoteCommand>.Continuation!
        self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation = $0 }
        self.outbox = continuation
    }

    // MARK: The hot path

    /// Queue a command. Synchronous, non-isolated, allocation-free — safe to call
    /// straight from a SwiftUI gesture handler on the main thread.
    nonisolated func send(_ command: RemoteCommand) {
        outbox.yield(command)
    }

    // MARK: Lifecycle

    func start() {
        guard stopped else { return }
        stopped = false
        attempt = 0
        revocation.recordSuccess()
        if pumpTask == nil {
            pumpTask = Task { [weak self] in await self?.pump() }
        }
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in await self?.maintainConnection() }
    }

    /// Drops the socket but keeps the command pump alive.
    ///
    /// The pump is deliberately *not* cancelled here: an `AsyncStream` supports a single
    /// consumer, and re-entering `for await` after the first iteration was cancelled
    /// yields nothing — key presses would silently stop working after the app had been
    /// backgrounded once. Use `shutdown()` when the session is genuinely going away.
    func stop() {
        stopped = true
        lifecycleTask?.cancel(); lifecycleTask = nil
        pingTask?.cancel(); pingTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        transition(to: .offline)
    }

    /// Permanent teardown, for a TV being removed from the pool.
    func shutdown() {
        stop()
        pumpTask?.cancel()
        pumpTask = nil
        outbox.finish()
        urlSession.invalidateAndCancel()
    }

    /// Nudges a reconnect immediately — used on foreground and on network path changes,
    /// where sitting out the remaining backoff would be felt as lag on the first press.
    /// A live connection is left alone.
    func wake() {
        guard !stopped else { return start() }
        guard state != .connected else { return }

        // Never interrupt an attempt that is already running.
        //
        // Tearing down an in-flight connection to start another one is not just wasted
        // work: on a TV we have no token for, every fresh attempt puts another "Allow?"
        // prompt on the screen. Scene activation, a network path change and a manual
        // retry can all land within the same second, so without this guard a single
        // foreground could queue up several prompts for the user to dismiss.
        //
        // It also protects `awaitingApproval`, where the user may be walking to the TV —
        // cancelling there would retract the prompt they were about to accept.
        guard !isAttempting else { return }

        attempt = 0
        lifecycleTask?.cancel()
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        lifecycleTask = Task { [weak self] in await self?.maintainConnection() }
    }

    func currentState() -> TVConnectionState { state }

    /// Forget the stored token so the next connection re-triggers the TV's prompt.
    func forgetToken() {
        token = nil
    }

    // MARK: Command pump

    private func pump() async {
        for await command in stream {
            guard await waitUntilReady() else { continue }
            deliver(command)
        }
    }

    /// Returns as soon as the socket is usable. When already connected — the normal
    /// case — this returns on the first check without ever suspending on a sleep.
    private func waitUntilReady(timeout: Duration = .milliseconds(1500)) async -> Bool {
        if state == .connected { return true }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if state == .connected { return true }
            if state == .unauthorized { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return state == .connected
    }

    private func deliver(_ command: RemoteCommand) {
        guard let socket, let payload = payload(for: command) else { return }
        let started = ContinuousClock.now
        let onLatency = self.onLatency
        socket.send(.string(payload)) { error in
            guard error == nil else { return }
            onLatency(started.duration(to: .now))
        }
    }

    /// Builds the wire payload.
    ///
    /// Written as string interpolation rather than `JSONEncoder` because the shape is
    /// fixed and this sits on the hot path. It is safe from injection: every interpolated
    /// value is either an enum raw value or base64.
    nonisolated func payload(for command: RemoteCommand) -> String? {
        switch command {
        case .key(let key, let action):
            return #"{"method":"ms.remote.control","params":{"Cmd":"\#(action.rawValue)","DataOfCmd":"\#(key.rawValue)","Option":"false","TypeOfRemote":"SendRemoteKey"}}"#
        case .text(let value):
            let encoded = Data(value.utf8).base64EncodedString()
            return #"{"method":"ms.remote.control","params":{"Cmd":"\#(encoded)","DataOfCmd":"base64","TypeOfRemote":"SendInputString"}}"#
        case .launch(let appID):
            let encoded = appID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? appID
            return #"{"method":"ms.channel.emit","params":{"event":"ed.apps.launch","to":"host","data":{"appId":"\#(encoded)","action_type":"DEEP_LINK"}}}"#
        }
    }

    // MARK: Connection maintenance

    private func maintainConnection() async {
        while !stopped, !Task.isCancelled {
            await openSocket()
            guard !stopped, !Task.isCancelled else { break }

            // The TV has explicitly refused this pairing. Retrying would put another
            // prompt on its screen every few seconds; wait for the user to ask instead.
            if state == .unauthorized { break }

            // Backoff: 0.25 → 0.5 → 1 → 2 → 4 → 8s, then hold.
            attempt = min(attempt + 1, 6)
            let delay = Duration.milliseconds(Int(250 * pow(2.0, Double(attempt - 1))))
            try? await Task.sleep(for: delay)
        }
    }

    /// Loopback means the bundled mock TV (`tools/MockSamsungTV.swift`), which speaks
    /// plain `ws://` so it doesn't need a certificate. Real TVs are always `wss://`.
    private var isLoopback: Bool {
        device.host == "127.0.0.1" || device.host == "localhost" || device.host == "::1"
    }

    private func openSocket() async {
        guard let url = device.controlURL(token: token, secure: !isLoopback) else {
            transition(to: .offline)
            return
        }

        // With no token the TV puts an "Allow?" prompt on screen and stays silent until
        // it is answered, so that state is surfaced distinctly rather than as "connecting".
        transition(to: token == nil ? .awaitingApproval : .connecting)

        Self.log.info("connecting to \(self.device.host, privacy: .public) token=\(self.token != nil, privacy: .public)")

        isAttempting = true
        defer { isAttempting = false }

        let task = urlSession.webSocketTask(with: url)
        socket = task
        attemptStartedAt = .now
        task.resume()
        startPinging(task)

        await receiveLoop(task)

        pingTask?.cancel()
        pingTask = nil
        socket = nil
        handleDisconnect()
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if case .string(let text) = message {
                    handle(text)
                }
            } catch {
                Self.log.info("receive ended: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    private func handle(_ text: String) {
        Self.log.debug("event: \(text.prefix(200), privacy: .public)")
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = root["event"] as? String
        else { return }

        switch event {
        case "ms.channel.connect":
            attempt = 0
            revocation.recordSuccess()
            if let payload = root["data"] as? [String: Any],
               let issued = payload["token"] as? String, !issued.isEmpty, issued != token {
                token = issued
                onToken(issued)
            }
            transition(to: .connected)

        case "ms.channel.unauthorized":
            // The only condition that justifies dropping a token: the TV said so outright.
            // The reconnect loop stops here so we don't put a new prompt on screen every
            // few seconds; the user resumes it with Pair Again.
            token = nil
            transition(to: .unauthorized)

        case "ms.channel.timeOut":
            transition(to: .offline)

        default:
            break
        }
    }

    private func handleDisconnect() {
        // The TV already said no; don't downgrade that to a plain disconnect.
        guard state != .unauthorized else { return }

        // A token is never discarded because a connection failed.
        //
        // From here a sleeping TV, a Wi-Fi handoff, a TV still booting, and a genuinely
        // revoked pairing all look identical: the socket opens and dies quickly. Treating
        // that as "the token is bad" means every nap the TV takes costs the user another
        // trip to press Allow. Only an explicit `ms.channel.unauthorized` clears a token.
        //
        // Repeated fast closures *while the TV is demonstrably awake* are the one real
        // signal of a revoked pairing, and even then the token is kept and the user is
        // offered a deliberate re-pair rather than being surprised by a prompt.
        let elapsed = attemptStartedAt.map { $0.duration(to: .now) } ?? .seconds(99)
        let diedFast = elapsed < .seconds(2)
        Self.log.info("disconnected after \(elapsed.description, privacy: .public) (fast=\(diedFast, privacy: .public), token=\(self.token != nil, privacy: .public))")
        if revocation.recordFailure(diedFast: diedFast, holdingToken: token != nil) {
            let host = device.host
            let notify = onRevocationSuspected
            Task {
                // Only meaningful if the TV is actually reachable — otherwise this is just
                // an asleep TV, which is not a pairing problem.
                if await SamsungREST.deviceInfo(host: host, timeout: 1.5) != nil {
                    notify()
                }
            }
        }

        transition(to: .offline)
    }

    private func startPinging(_ task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await self?.ping(task)
            }
        }
    }

    private func ping(_ task: URLSessionWebSocketTask) {
        task.sendPing { _ in }
    }

    private func transition(to newState: TVConnectionState) {
        guard newState != state else { return }
        Self.log.info("\(self.device.host, privacy: .public): \(String(describing: self.state), privacy: .public) -> \(String(describing: newState), privacy: .public)")
        state = newState
        onStateChange(newState)
    }
}
