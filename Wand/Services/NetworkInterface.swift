import Foundation

/// Reads the device's own IPv4 address and netmask so a scan knows which subnet to walk.
enum NetworkInterface {

    struct IPv4: Equatable, Sendable {
        var address: String
        var netmask: String
    }

    /// The active Wi-Fi (`en0`) IPv4 address, falling back to any non-loopback interface.
    static func current() -> IPv4? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var fallback: IPv4?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            guard let rawAddress = current.pointee.ifa_addr,
                  rawAddress.pointee.sa_family == UInt8(AF_INET),
                  let rawMask = current.pointee.ifa_netmask
            else { continue }

            guard let address = presentation(rawAddress), let netmask = presentation(rawMask) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            let found = IPv4(address: address, netmask: netmask)

            if name == "en0" { return found }
            if fallback == nil { fallback = found }
        }
        return fallback
    }

    private static func presentation(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address, socklen_t(address.pointee.sa_len),
            &buffer, socklen_t(buffer.count),
            nil, 0, NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Every usable host address on the interface's subnet, excluding the network and
    /// broadcast addresses.
    ///
    /// Capped at `limit` hosts: anything wider than a /22 is almost certainly a
    /// misconfigured mask, and walking 65k addresses would take minutes for no benefit.
    static func hostAddresses(address: String, netmask: String, limit: Int = 1024) -> [String] {
        guard let host = packed(address), let mask = packed(netmask) else { return [] }
        let network = host & mask
        let broadcast = network | ~mask
        guard broadcast > network else { return [] }

        let total = Int(broadcast - network) - 1
        guard total > 0 else { return [] }

        var results: [String] = []
        results.reserveCapacity(min(total, limit))
        var candidate = network + 1
        while candidate < broadcast, results.count < limit {
            if candidate != host { results.append(dotted(candidate)) }
            candidate += 1
        }
        return results
    }

    static func packed(_ value: String) -> UInt32? {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    static func dotted(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// The subnet's broadcast address — where Wake-on-LAN packets go.
    static func broadcastAddress(address: String, netmask: String) -> String? {
        guard let host = packed(address), let mask = packed(netmask) else { return nil }
        return dotted(host | ~mask)
    }
}
