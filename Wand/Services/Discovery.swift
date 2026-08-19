import Foundation

/// Finds Samsung TVs by walking the local subnet.
///
/// SSDP would be the obvious route, but multicast on iOS needs the
/// `com.apple.developer.networking.multicast` entitlement, which Apple grants only by
/// application. Probing `http://<host>:8001/api/v2/` needs no entitlement, and that one
/// response carries everything needed to save a TV: display name, model, stable id, and
/// the MAC for Wake-on-LAN. It also answers while the TV is in standby, which the
/// app-level endpoints do not.
struct Discovery: Sendable {

    struct Found: Identifiable, Hashable, Sendable {
        var id: String { deviceIdentifier.isEmpty ? host : deviceIdentifier }
        var host: String
        var name: String
        var model: String
        var deviceIdentifier: String
        var macAddress: String?
        var supportsToken: Bool
    }

    /// How many probes are in flight at once. High enough to sweep a /24 in a couple of
    /// seconds, low enough not to exhaust the socket table on a phone.
    var concurrency: Int = 48
    var perHostTimeout: TimeInterval = 1.2

    /// Streams TVs as they answer, so the UI can show the first hit immediately instead
    /// of waiting for the whole sweep.
    func scan() -> AsyncStream<Found> {
        AsyncStream { continuation in
            let task = Task {
                guard let interface = NetworkInterface.current() else {
                    continuation.finish()
                    return
                }
                let hosts = NetworkInterface.hostAddresses(
                    address: interface.address,
                    netmask: interface.netmask
                )
                let session = SamsungREST.session(timeout: perHostTimeout)
                defer { session.invalidateAndCancel() }

                await withTaskGroup(of: Found?.self) { group in
                    var index = 0
                    var running = 0

                    func addNext() {
                        guard index < hosts.count else { return }
                        let host = hosts[index]
                        index += 1
                        running += 1
                        group.addTask {
                            await probe(host: host, session: session)
                        }
                    }

                    while running < concurrency, index < hosts.count { addNext() }

                    while running > 0 {
                        guard let result = await group.next() else { break }
                        running -= 1
                        if let result { continuation.yield(result) }
                        if Task.isCancelled { break }
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Identifies a single host, used both by the sweep and by manual IP entry.
    func probe(host: String, session: URLSession? = nil) async -> Found? {
        guard let info = await SamsungREST.deviceInfo(
            host: host, timeout: perHostTimeout, session: session
        ) else { return nil }

        let device = info.device
        // Every Samsung set reports a model name; anything else on :8001 isn't a TV.
        guard let model = device.modelName, !model.isEmpty else { return nil }

        return Found(
            host: host,
            name: device.name ?? model,
            model: model,
            deviceIdentifier: device.id ?? info.id ?? host,
            macAddress: device.wifiMac,
            supportsToken: (device.tokenAuthSupport ?? "true").lowercased() == "true"
        )
    }
}
