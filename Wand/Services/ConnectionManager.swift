import Foundation
import Network
import Observation
import SwiftUI

/// Owns a live `SamsungSession` per saved TV and routes button presses to the active one.
///
/// The reason this holds a *pool* rather than a single session: switching TVs has to feel
/// instantaneous, and a cold WebSocket costs a TLS handshake plus the TV's own accept
/// round trip. Keeping the nearest few TVs connected means the first press after a switch
/// is as fast as the hundredth press before it.
@MainActor
@Observable
final class ConnectionManager {

    /// How many TVs stay connected at once. Beyond a handful the sockets cost more than
    /// the switch latency they save.
    private static let warmPoolLimit = 3

    private(set) var states: [UUID: TVConnectionState] = [:]
    private(set) var latency = LatencySamples()

    /// Set when the TV rejects a stored token, so the UI can offer to re-pair.
    private(set) var needsRepair: Set<UUID> = []

    /// Typed as the protocol, not the Samsung actor — this is what makes the
    /// driver seam load-bearing rather than decorative.
    @ObservationIgnored private var sessions: [UUID: any TVDriver] = [:]
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var backgroundGrace: Task<Void, Never>?
    @ObservationIgnored private weak var store: DeviceStore?

    // MARK: Wiring

    func attach(to store: DeviceStore) {
        self.store = store
        syncPool()
    }

    /// Brings the pool in line with the saved devices: connect the active TV plus the
    /// next few, drop sessions for TVs that are gone.
    func syncPool() {
        guard let store else { return }

        var wanted: [TVDevice] = []
        if let active = store.activeDevice { wanted.append(active) }
        for device in store.devices where !wanted.contains(where: { $0.id == device.id }) {
            guard wanted.count < Self.warmPoolLimit else { break }
            wanted.append(device)
        }

        let wantedIDs = Set(wanted.map(\.id))
        for (id, session) in sessions where !wantedIDs.contains(id) {
            Task { await session.shutdown() }
            sessions[id] = nil
            states[id] = nil
        }

        for device in wanted where sessions[device.id] == nil {
            let session = makeSession(for: device)
            sessions[device.id] = session
            states[device.id] = .offline
            Task { await session.start() }
        }
    }

    private func makeSession(for device: TVDevice) -> any TVDriver {
        let id = device.id
        return SamsungSession(
            device: device,
            token: TokenStore.token(for: id),
            onStateChange: { [weak self] state in
                Task { @MainActor in self?.apply(state, to: id) }
            },
            onToken: { token in
                TokenStore.save(token, for: id)
            },
            onLatency: { [weak self] duration in
                Task { @MainActor in self?.latency.record(duration) }
            },
            onRevocationSuspected: { [weak self] in
                Task { @MainActor in self?.needsRepair.insert(id) }
            }
        )
    }

    private func apply(_ state: TVConnectionState, to id: UUID) {
        states[id] = state
        switch state {
        case .connected:
            needsRepair.remove(id)
            store?.markConnected(id)
        case .unauthorized:
            needsRepair.insert(id)
        default:
            break
        }
    }

    func state(for device: TVDevice?) -> TVConnectionState {
        guard let device else { return .offline }
        return states[device.id] ?? .offline
    }

    var activeState: TVConnectionState { state(for: store?.activeDevice) }

    // MARK: The hot path

    /// Send a key to the active TV. Synchronous by design — see `SamsungSession.send`.
    /// Safe to call directly from a gesture handler; it never awaits and never throws.
    func press(_ key: RemoteKey) {
        session()?.send(.key(key, .click))
    }

    func beginHold(_ key: RemoteKey) {
        session()?.send(.key(key, .press))
    }

    func endHold(_ key: RemoteKey) {
        session()?.send(.key(key, .release))
    }

    func type(_ text: String) {
        guard !text.isEmpty else { return }
        session()?.send(.text(text))
    }

    private func session() -> (any TVDriver)? {
        guard let id = store?.activeDevice?.id else { return nil }
        return sessions[id]
    }

    // MARK: Apps

    /// Launches over REST first — it reports success synchronously and works on firmware
    /// where the WebSocket `ed.apps.launch` emit is silently ignored — then falls back to
    /// the socket.
    func launch(app: TVApp, resolvedID: String?) {
        guard let device = store?.activeDevice else { return }
        let session = sessions[device.id]
        let candidates = resolvedID.map { [$0] } ?? app.candidateIDs

        Task {
            for candidate in candidates {
                if await SamsungREST.launch(host: device.host, appID: candidate) { return }
            }
            if let first = candidates.first {
                session?.send(.launch(appID: first))
            }
        }
    }

    // MARK: Power

    /// Off → on needs Wake-on-LAN, because a sleeping TV refuses WebSocket connections
    /// outright. On → off is a normal key over the live socket.
    func togglePower() {
        guard let device = store?.activeDevice else { return }
        if activeState == .connected {
            press(.power)
        } else {
            wake(device)
        }
    }

    func wake(_ device: TVDevice) {
        guard let mac = device.macAddress else { return }
        Task {
            await WakeOnLAN.wake(mac: mac, host: device.host)
            // The TV needs roughly 20s to boot Tizen far enough to accept a socket;
            // nudge the session periodically instead of waiting out the backoff.
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(2))
                await sessions[device.id]?.wake()
                if states[device.id] == .connected { return }
            }
        }
    }

    // MARK: Pairing

    /// Drops the stored token so the next connection re-triggers the TV's prompt.
    ///
    /// The only path that deletes a token. Nothing does this automatically — a token costs
    /// the user a walk to the TV, so losing one is always a deliberate act.
    func repair(_ device: TVDevice) {
        TokenStore.delete(for: device.id)
        needsRepair.remove(device.id)
        Task {
            await sessions[device.id]?.forgetToken()
            await sessions[device.id]?.wake()
        }
    }

    // MARK: App lifecycle

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            backgroundGrace?.cancel()
            backgroundGrace = nil
            startPathMonitor()
            for session in sessions.values {
                Task { await session.wake() }
            }
        case .background:
            // Deliberately not an immediate teardown: flicking to another app and back is
            // common, and reconnecting on return is exactly the lag this app exists to
            // avoid. Sockets are held for a grace period first.
            backgroundGrace?.cancel()
            backgroundGrace = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.suspendAll()
            }
        default:
            break
        }
    }

    private func suspendAll() async {
        for session in sessions.values {
            await session.stop()
        }
        states = states.mapValues { _ in .offline }
        stopPathMonitor()
    }

    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self else { return }
                for session in self.sessions.values {
                    await session.wake()
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

/// Rolling latency stats for the diagnostics screen — press to socket-send completion.
/// This is what makes "no lag" a number rather than a claim.
struct LatencySamples: Sendable {
    private(set) var samples: [Double] = []
    private static let capacity = 120

    mutating func record(_ duration: Duration) {
        let milliseconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        samples.append(milliseconds)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    var count: Int { samples.count }
    var median: Double? { percentile(0.5) }
    var p95: Double? { percentile(0.95) }

    func percentile(_ fraction: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }
}
