import Foundation
import Network
import os

/// Wakes a TV that has powered down.
///
/// A sleeping Samsung answers `/api/v2/` from its standby chip but refuses WebSocket
/// connections entirely, so the power button can't reach it over the control channel.
/// A magic packet is the only way back on.
///
/// Verified against a UN65MU6070: the set takes roughly 20 seconds to boot Tizen far
/// enough to accept a socket, which is why `PowerController` polls rather than assuming
/// failure after a couple of seconds. The TV must have
/// *Settings → General → Network → Expert Settings → Power On with Mobile* enabled.
enum WakeOnLAN {

    /// Builds the 102-byte magic packet: six `0xFF` bytes then the MAC repeated 16 times.
    static func magicPacket(mac: String) -> Data? {
        let hex = mac.filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }

        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    /// Sends the packet to the subnet broadcast, the global broadcast, and the TV's own
    /// address. Routers vary in which they forward, and the packet is 102 bytes, so
    /// covering all three costs nothing and meaningfully improves the hit rate.
    static func wake(mac: String, host: String?) async {
        guard let packet = magicPacket(mac: mac) else { return }

        var targets: [String] = ["255.255.255.255"]
        if let interface = NetworkInterface.current(),
           let broadcast = NetworkInterface.broadcastAddress(
                address: interface.address, netmask: interface.netmask
           ) {
            targets.insert(broadcast, at: 0)
        }
        if let host { targets.append(host) }

        // Ports 9 and 7 are both conventional for WoL.
        for target in targets {
            for port in [UInt16(9), UInt16(7)] {
                await send(packet, to: target, port: port)
            }
        }
    }

    private static func send(_ packet: Data, to host: String, port: UInt16) async {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any,
            using: parameters
        )

        // A broadcast to an address nothing answers can leave the connection pending
        // forever, and several paths can finish first, so resumption is gated.
        let gate = ResumeGate()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { _ in
                        connection.cancel()
                        gate.resume(continuation)
                    })
                case .failed, .cancelled:
                    connection.cancel()
                    gate.resume(continuation)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            Task {
                try? await Task.sleep(for: .milliseconds(600))
                connection.cancel()
                gate.resume(continuation)
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever of several racing callbacks gets there
/// first. Resuming twice is a crash, not a warning.
private final class ResumeGate: Sendable {
    private let finished = OSAllocatedUnfairLock(initialState: false)

    func resume(_ continuation: CheckedContinuation<Void, Never>) {
        let shouldResume = finished.withLock { done -> Bool in
            guard !done else { return false }
            done = true
            return true
        }
        if shouldResume { continuation.resume() }
    }
}
