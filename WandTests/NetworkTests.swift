import Testing
import Foundation
@testable import Wand

struct NetworkInterfaceTests {

    @Test func packedAndDottedRoundTrip() throws {
        let packed = try #require(NetworkInterface.packed("10.0.0.108"))
        #expect(packed == 0x0A_00_00_6C)
        #expect(NetworkInterface.dotted(packed) == "10.0.0.108")
    }

    @Test func rejectsMalformedAddresses() {
        #expect(NetworkInterface.packed("10.0.0") == nil)
        #expect(NetworkInterface.packed("10.0.0.256") == nil)
        #expect(NetworkInterface.packed("not.an.ip.here") == nil)
    }

    /// A /24 sweep must cover .1–.254, skip the network and broadcast addresses, and
    /// skip the phone itself.
    @Test func slash24EnumeratesEveryUsableHost() {
        let hosts = NetworkInterface.hostAddresses(address: "10.0.0.246", netmask: "255.255.255.0")

        #expect(hosts.count == 253, "254 usable hosts minus this device")
        #expect(hosts.contains("10.0.0.1"))
        #expect(hosts.contains("10.0.0.108"), "the TV's address must be probed")
        #expect(hosts.contains("10.0.0.254"))
        #expect(!hosts.contains("10.0.0.0"), "network address")
        #expect(!hosts.contains("10.0.0.255"), "broadcast address")
        #expect(!hosts.contains("10.0.0.246"), "no point probing ourselves")
    }

    @Test func smallerSubnetsEnumerateCorrectly() {
        let hosts = NetworkInterface.hostAddresses(address: "192.168.1.10", netmask: "255.255.255.248")
        #expect(hosts.count == 5)
        #expect(hosts.allSatisfy { $0.hasPrefix("192.168.1.") })
    }

    /// A misconfigured mask shouldn't turn a scan into a multi-minute sweep of 65k hosts.
    @Test func oversizedSubnetsAreCapped() {
        let hosts = NetworkInterface.hostAddresses(address: "10.0.0.5", netmask: "255.255.0.0", limit: 1024)
        #expect(hosts.count == 1024)
    }

    @Test func broadcastAddressIsDerivedFromTheMask() {
        #expect(NetworkInterface.broadcastAddress(address: "10.0.0.246", netmask: "255.255.255.0") == "10.0.0.255")
        #expect(NetworkInterface.broadcastAddress(address: "192.168.1.10", netmask: "255.255.0.0") == "192.168.255.255")
    }
}

struct WakeOnLANTests {

    /// 6 sync bytes plus the MAC sixteen times.
    @Test func magicPacketIsCorrectlyFormed() throws {
        let packet = try #require(WakeOnLAN.magicPacket(mac: "7c:64:56:c5:3f:e6"))

        #expect(packet.count == 102)
        #expect(packet.prefix(6).allSatisfy { $0 == 0xFF })

        let mac: [UInt8] = [0x7c, 0x64, 0x56, 0xc5, 0x3f, 0xe6]
        for repetition in 0..<16 {
            let start = 6 + repetition * 6
            #expect(Array(packet[start..<(start + 6)]) == mac, "repetition \(repetition)")
        }
    }

    /// MAC addresses get typed and pasted in every format there is.
    @Test func separatorsAndCaseAreAccepted() throws {
        let expected = try #require(WakeOnLAN.magicPacket(mac: "7c:64:56:c5:3f:e6"))
        for variant in ["7C:64:56:C5:3F:E6", "7c-64-56-c5-3f-e6", "7c6456c53fe6", "7c 64 56 c5 3f e6"] {
            #expect(WakeOnLAN.magicPacket(mac: variant) == expected, "failed for \(variant)")
        }
    }

    @Test func rejectsMalformedMACs() {
        #expect(WakeOnLAN.magicPacket(mac: "7c:64:56:c5:3f") == nil)
        #expect(WakeOnLAN.magicPacket(mac: "") == nil)
        #expect(WakeOnLAN.magicPacket(mac: "zz:zz:zz:zz:zz:zz") == nil)
    }
}

struct AppCatalogTests {

    @Test func defaultSlotsAreInTheRequestedOrder() {
        #expect(TVApp.defaultSlotKeys == ["youtube", "netflix", "primevideo", "disneyplus"])
        let names = TVApp.defaultSlotKeys.compactMap { TVApp.app(forKey: $0)?.name }
        #expect(names == ["YouTube", "Netflix", "Prime Video", "Disney+"])
    }

    /// IDs changed around 2020, so the newest must be probed first.
    @Test func candidateIDsAreNewestFirst() throws {
        let netflix = try #require(TVApp.app(forKey: "netflix"))
        #expect(netflix.candidateIDs.first == "3201907018807")

        let disney = try #require(TVApp.app(forKey: "disneyplus"))
        #expect(disney.candidateIDs == ["3202204027038", "3202009021709", "3201901017640"])
    }

    @Test func catalogKeysAreUnique() {
        let keys = TVApp.catalog.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test func everyAppHasAtLeastOneCandidateID() {
        for app in TVApp.catalog {
            #expect(!app.candidateIDs.isEmpty, "\(app.name) has no IDs")
        }
    }

    @Test func restEndpointsAreWellFormed() throws {
        let base = try #require(SamsungREST.baseURL(host: "10.0.0.108"))
        #expect(base.absoluteString == "http://10.0.0.108:8001/api/v2/")

        let app = try #require(SamsungREST.appURL(host: "10.0.0.108", appID: "111299001912"))
        #expect(app.absoluteString == "http://10.0.0.108:8001/api/v2/applications/111299001912")
    }
}

struct LatencySamplesTests {

    @Test func percentilesReflectTheSamples() {
        var samples = LatencySamples()
        for value in 1...100 {
            samples.record(.milliseconds(value))
        }
        #expect(samples.count == 100)
        #expect(samples.median.map { abs($0 - 50) < 2 } == true)
        #expect(samples.p95.map { abs($0 - 95) < 2 } == true)
    }

    @Test func emptyStatsAreNilRatherThanZero() {
        let samples = LatencySamples()
        #expect(samples.median == nil)
        #expect(samples.p95 == nil)
    }

    /// Bounded so a long session can't grow the buffer without limit.
    @Test func bufferIsCapped() {
        var samples = LatencySamples()
        for _ in 0..<500 { samples.record(.milliseconds(1)) }
        #expect(samples.count == 120)
    }
}
