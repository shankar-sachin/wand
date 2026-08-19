import Testing
import Foundation
@testable import Wand

/// These cover the wire details that were wrong on the first attempt against a real
/// UN65MU6070 — each one is a bug that shipped silently rather than erroring.
struct SamsungProtocolTests {

    private func device(host: String = "10.0.0.108") -> TVDevice {
        TVDevice(
            name: "Living Room",
            tvReportedName: "[TV] Samsung 6 Series (65)",
            model: "UN65MU6070",
            deviceIdentifier: "uuid:test",
            host: host,
            macAddress: "7c:64:56:c5:3f:e6"
        )
    }

    /// The one that cost the most to find: a raw `==` in the query makes the TV accept
    /// the socket and then never send `ms.channel.connect`. It must be stripped.
    @Test func clientNameBase64IsUnpadded() throws {
        let url = try #require(device().controlURL(token: nil, clientName: "Wand"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let name = try #require(components.queryItems?.first { $0.name == "name" }?.value)

        // Base64 of "Wand" is "V2FuZA==" — the padding has to go.
        #expect(name == "V2FuZA")
        #expect(!name.contains("="), "padding must not reach the TV")

        // And it must not survive percent-encoded either.
        #expect(url.absoluteString.contains("%3D") == false)
    }

    /// Plain `ws://` on 8001 opens and is dropped immediately on this generation.
    @Test func controlURLUsesSecureWebSocketOn8002() throws {
        let url = try #require(device().controlURL(token: nil))
        #expect(url.scheme == "wss")
        #expect(url.port == 8002)
        #expect(url.path == "/api/v2/channels/samsung.remote.control")
    }

    @Test func tokenIsAppendedWhenPresent() throws {
        let withToken = try #require(device().controlURL(token: "11051039"))
        #expect(withToken.query?.contains("token=11051039") == true)

        let withoutToken = try #require(device().controlURL(token: nil))
        #expect(withoutToken.query?.contains("token") == false)

        // An empty token is not a token — sending `&token=` re-triggers the prompt path
        // in a way the TV handles worse than omitting it.
        let empty = try #require(device().controlURL(token: ""))
        #expect(empty.query?.contains("token") == false)
    }

    @Test func nameIsBase64OfTheClientNameNotThePlainString() throws {
        // The TV echoes this value back in its client list; plain text is rejected.
        let url = try #require(device().controlURL(token: nil, clientName: "Wand"))
        #expect(url.query?.contains("name=Wand") == false)
    }

    // MARK: Payloads

    private func makeSession() -> SamsungSession {
        SamsungSession(device: device(), token: nil, onStateChange: { _ in }, onToken: { _ in })
    }

    @Test func keyPayloadMatchesTheRemoteControlSchema() throws {
        let payload = try #require(makeSession().payload(for: .key(.volumeUp, .click)))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )

        #expect(json["method"] as? String == "ms.remote.control")
        let params = try #require(json["params"] as? [String: Any])
        #expect(params["Cmd"] as? String == "Click")
        #expect(params["DataOfCmd"] as? String == "KEY_VOLUP")
        #expect(params["TypeOfRemote"] as? String == "SendRemoteKey")
        // The TV wants the string "false", not a JSON boolean.
        #expect(params["Option"] as? String == "false")
    }

    @Test func holdUsesPressAndRelease() throws {
        let session = makeSession()
        let press = try #require(session.payload(for: .key(.volumeUp, .press)))
        let release = try #require(session.payload(for: .key(.volumeUp, .release)))
        #expect(press.contains("\"Cmd\":\"Press\""))
        #expect(release.contains("\"Cmd\":\"Release\""))
    }

    @Test func textPayloadIsBase64Encoded() throws {
        let payload = try #require(makeSession().payload(for: .text("hello world")))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        let params = try #require(json["params"] as? [String: Any])

        #expect(params["TypeOfRemote"] as? String == "SendInputString")
        #expect(params["DataOfCmd"] as? String == "base64")
        let encoded = try #require(params["Cmd"] as? String)
        #expect(String(data: try #require(Data(base64Encoded: encoded)), encoding: .utf8) == "hello world")
    }

    /// Text arrives from a keyboard, so quotes and backslashes must not be able to break
    /// out of the JSON. Base64 is what guarantees that.
    @Test func textWithJSONMetacharactersStaysValid() throws {
        let hostile = #"" ,"method":"evil" \"#
        let payload = try #require(makeSession().payload(for: .text(hostile)))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        #expect(json["method"] as? String == "ms.remote.control")
    }

    @Test func everyKeyCodeUsesTheKeyPrefix() {
        for key in RemoteKey.allCases {
            #expect(key.rawValue.hasPrefix("KEY_"), "\(key) has an unexpected code")
        }
    }

    @Test func digitLookupCoversZeroThroughNine() throws {
        for value in 0...9 {
            #expect(RemoteKey.digit(value)?.rawValue == "KEY_\(value)")
        }
        #expect(RemoteKey.digit(10) == nil)
    }
}

/// Guards the behaviour that decides whether the user has to walk to the TV again.
struct RevocationHeuristicTests {

    /// The regression that mattered: a TV that naps must never cost the user its pairing.
    /// One fast failure — the shape of every sleeping TV, Wi-Fi handoff, and cold boot —
    /// must not be read as a revoked token.
    @Test func aSingleFastFailureIsNotRevocation() {
        var heuristic = RevocationHeuristic()
        #expect(heuristic.recordFailure(diedFast: true, holdingToken: true) == false)
        #expect(heuristic.consecutiveFastFailures == 1)
    }

    @Test func revocationNeedsRepeatedFastFailures() {
        var heuristic = RevocationHeuristic()
        #expect(heuristic.recordFailure(diedFast: true, holdingToken: true) == false)
        #expect(heuristic.recordFailure(diedFast: true, holdingToken: true) == false)
        #expect(heuristic.recordFailure(diedFast: true, holdingToken: true) == true)
    }

    /// A slow failure is an ordinary drop — a TV that answered for a while and then went
    /// away says nothing about the credential.
    @Test func slowFailuresNeverCount() {
        var heuristic = RevocationHeuristic()
        for _ in 0..<10 {
            #expect(heuristic.recordFailure(diedFast: false, holdingToken: true) == false)
        }
        #expect(heuristic.consecutiveFastFailures == 0)
    }

    /// With no token there is no pairing to revoke.
    @Test func failuresWithoutATokenNeverCount() {
        var heuristic = RevocationHeuristic()
        for _ in 0..<10 {
            #expect(heuristic.recordFailure(diedFast: true, holdingToken: false) == false)
        }
    }

    /// Intermittency must not accumulate into a false positive.
    @Test func anySuccessResetsSuspicion() {
        var heuristic = RevocationHeuristic()
        _ = heuristic.recordFailure(diedFast: true, holdingToken: true)
        _ = heuristic.recordFailure(diedFast: true, holdingToken: true)
        heuristic.recordSuccess()
        #expect(heuristic.consecutiveFastFailures == 0)
        #expect(heuristic.recordFailure(diedFast: true, holdingToken: true) == false)
    }

    /// A good connection between failures also resets, via the mixed path.
    @Test func aGoodConnectionBetweenFailuresResets() {
        var heuristic = RevocationHeuristic()
        _ = heuristic.recordFailure(diedFast: true, holdingToken: true)
        _ = heuristic.recordFailure(diedFast: false, holdingToken: true)
        #expect(heuristic.consecutiveFastFailures == 0)
    }
}
