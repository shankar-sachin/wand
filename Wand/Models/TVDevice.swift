import Foundation

/// A TV the user has saved. Persisted as JSON; the pairing token lives in the
/// Keychain instead (see `TokenStore`), keyed by `id`.
struct TVDevice: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()

    /// What the user calls it. Seeded from `tvReportedName` at pairing, then editable.
    var name: String
    /// The name the TV reports, e.g. "[TV] Samsung 6 Series (65)". Kept for re-identification.
    var tvReportedName: String
    var model: String
    /// Stable per-TV identifier from `/api/v2/` (`device.id`). Survives IP changes.
    var deviceIdentifier: String

    var host: String
    /// MAC used for Wake-on-LAN. From `device.wifiMac`, which on wired sets still
    /// reports the active interface, but the user can override it.
    var macAddress: String?

    /// Catalog keys for the four face buttons, in display order.
    var appSlots: [String] = TVApp.defaultSlotKeys
    var dateAdded: Date = .now
    var lastConnected: Date?

    /// `wss://host:8002/...` — the only transport that works on Tizen 2016+.
    /// Note the base64 name must be **unpadded**: a raw `==` in the query makes the
    /// TV accept the socket and then never send `ms.channel.connect`.
    /// `secure` exists so tests and the bundled mock TV can speak plain `ws://`; real
    /// TVs are always `wss://`.
    func controlURL(token: String?, clientName: String = "Wand", secure: Bool = true) -> URL? {
        let encoded = Data(clientName.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = secure ? "wss" : "ws"
        components.host = host
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var items = [URLQueryItem(name: "name", value: encoded)]
        if let token, !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        components.queryItems = items
        return components.url
    }
}

/// Live connection state for one TV, surfaced by the status dots in the switcher.
enum TVConnectionState: Equatable, Sendable {
    case offline
    case connecting
    /// Socket is open; the TV is showing its "Allow?" prompt and hasn't answered yet.
    case awaitingApproval
    case connected
    /// The TV refused the token, or the user denied the prompt.
    case unauthorized
}
