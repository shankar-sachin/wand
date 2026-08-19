import Foundation
import Observation

/// Works out which apps a given TV actually has, and which numeric ID it answers to.
///
/// Samsung removed the `ed.installedApp.get` WebSocket call on 2020+ firmware, so an app
/// grid built on it silently comes back empty. Probing the REST endpoint per candidate ID
/// is slower but truthful, and the answers are cached per TV so it happens once.
@MainActor
@Observable
final class AppResolver {

    enum Availability: Equatable {
        case unknown
        case installed(id: String)
        case absent
    }

    private(set) var availability: [String: Availability] = [:]
    private(set) var isProbing = false

    @ObservationIgnored private var probedHost: String?

    /// Probes the whole catalog for one TV. Cheap to call repeatedly — it only re-runs
    /// when the TV changes.
    func probe(host: String, force: Bool = false) async {
        guard force || probedHost != host else { return }
        probedHost = host
        isProbing = true
        availability = [:]
        defer { isProbing = false }

        let session = SamsungREST.session(timeout: 2.5)
        defer { session.invalidateAndCancel() }

        await withTaskGroup(of: (String, Availability).self) { group in
            for app in TVApp.catalog {
                group.addTask {
                    if let id = await SamsungREST.resolveAppID(host: host, app: app, session: session) {
                        return (app.key, .installed(id: id))
                    }
                    return (app.key, .absent)
                }
            }
            for await (key, result) in group {
                availability[key] = result
            }
        }
    }

    func resolvedID(for app: TVApp) -> String? {
        if case .installed(let id) = availability[app.key] { return id }
        return nil
    }

    func isInstalled(_ app: TVApp) -> Bool {
        if case .installed = availability[app.key] { return true }
        return false
    }

    /// Everything the TV reports as installed, in catalog order.
    var installedApps: [TVApp] {
        TVApp.catalog.filter { isInstalled($0) }
    }
}
