import Foundation
import Observation

/// The user's saved TVs and which one the remote is currently driving.
///
/// Small enough to keep in `UserDefaults` as JSON. Pairing tokens are deliberately not
/// part of this — they live in `TokenStore`.
@MainActor
@Observable
final class DeviceStore {

    private enum Key {
        static let devices = "wand.devices"
        static let active = "wand.activeDeviceID"
    }

    private(set) var devices: [TVDevice] = []
    var activeDeviceID: UUID? {
        didSet {
            guard activeDeviceID != oldValue else { return }
            defaults.set(activeDeviceID?.uuidString, forKey: Key.active)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var activeDevice: TVDevice? {
        guard let activeDeviceID else { return devices.first }
        return devices.first { $0.id == activeDeviceID } ?? devices.first
    }

    var hasDevices: Bool { !devices.isEmpty }

    // MARK: Mutation

    func add(_ device: TVDevice) {
        // Re-adding a TV that's already saved updates it in place rather than
        // duplicating — `deviceIdentifier` is stable across IP changes.
        if let index = devices.firstIndex(where: { $0.deviceIdentifier == device.deviceIdentifier }) {
            var existing = devices[index]
            existing.host = device.host
            existing.macAddress = device.macAddress ?? existing.macAddress
            existing.tvReportedName = device.tvReportedName
            existing.model = device.model
            devices[index] = existing
            activeDeviceID = existing.id
        } else {
            devices.append(device)
            activeDeviceID = device.id
        }
        persist()
    }

    func update(_ device: TVDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
        persist()
    }

    func remove(_ device: TVDevice) {
        devices.removeAll { $0.id == device.id }
        TokenStore.delete(for: device.id)
        if activeDeviceID == device.id { activeDeviceID = devices.first?.id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        devices.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func markConnected(_ id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].lastConnected = .now
        persist()
    }

    /// Cycles to the next saved TV — backs the swipe gesture on the remote body.
    func advanceActive(by offset: Int) {
        guard devices.count > 1 else { return }
        let current = devices.firstIndex { $0.id == activeDevice?.id } ?? 0
        let next = (current + offset + devices.count) % devices.count
        activeDeviceID = devices[next].id
    }

    // MARK: Persistence

    private func load() {
        if let data = defaults.data(forKey: Key.devices),
           let decoded = try? JSONDecoder().decode([TVDevice].self, from: data) {
            devices = decoded
        }
        if let raw = defaults.string(forKey: Key.active) {
            activeDeviceID = UUID(uuidString: raw)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: Key.devices)
    }
}
