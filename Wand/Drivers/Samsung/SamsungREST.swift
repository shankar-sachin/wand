import Foundation

/// The TV's plain-HTTP API on port 8001.
///
/// Used for three things the WebSocket can't do well: identifying a TV during a network
/// scan, telling whether an app is actually installed, and launching apps.
enum SamsungREST {
    /// `/api/v2/` — answers even in standby, which is what makes a subnet scan viable.
    struct DeviceInfo: Decodable, Sendable {
        struct Device: Decodable, Sendable {
            var name: String?
            var modelName: String?
            var wifiMac: String?
            var id: String?
            var networkType: String?
            var tokenAuthSupport: String?
            var powerState: String?

            private enum CodingKeys: String, CodingKey {
                case name, modelName, wifiMac, id, networkType
                case tokenAuthSupport = "TokenAuthSupport"
                case powerState = "PowerState"
            }
        }
        var device: Device
        var id: String?
    }

    struct AppStatus: Decodable, Sendable {
        var id: String
        var name: String
        var running: Bool
        var visible: Bool
    }

    /// A short-lived session; scans fire hundreds of these in parallel.
    static func session(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.allowsCellularAccess = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    static func baseURL(host: String) -> URL? {
        URL(string: "http://\(host):8001/api/v2/")
    }

    /// Identifies whatever is listening on `host:8001`. Returns nil for anything that
    /// isn't a Samsung TV, which is most of the subnet.
    static func deviceInfo(host: String, timeout: TimeInterval = 1.2,
                           session: URLSession? = nil) async -> DeviceInfo? {
        guard let url = baseURL(host: host) else { return nil }
        let session = session ?? Self.session(timeout: timeout)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(DeviceInfo.self, from: data)
        } catch {
            return nil
        }
    }

    static func appURL(host: String, appID: String) -> URL? {
        URL(string: "http://\(host):8001/api/v2/applications/\(appID)")
    }

    /// 200 means installed. Note this endpoint hangs while the TV is in standby — only
    /// the `/api/v2/` root answers then — so treat a timeout as "unknown", not "absent".
    static func appStatus(host: String, appID: String, timeout: TimeInterval = 2.5,
                          session: URLSession? = nil) async -> AppStatus? {
        guard let url = appURL(host: host, appID: appID) else { return nil }
        let session = session ?? Self.session(timeout: timeout)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(AppStatus.self, from: data)
        } catch {
            return nil
        }
    }

    /// Walks an app's candidate IDs newest-first and returns the one the TV recognises.
    static func resolveAppID(host: String, app: TVApp, session: URLSession? = nil) async -> String? {
        for candidate in app.candidateIDs {
            if await appStatus(host: host, appID: candidate, session: session) != nil {
                return candidate
            }
        }
        return nil
    }

    /// `POST /applications/<id>` launches. Preferred over the WebSocket `ed.apps.launch`
    /// emit because it reports success synchronously.
    @discardableResult
    static func launch(host: String, appID: String, timeout: TimeInterval = 4,
                       session: URLSession? = nil) async -> Bool {
        guard let url = appURL(host: host, appID: appID) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let session = session ?? Self.session(timeout: timeout)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
