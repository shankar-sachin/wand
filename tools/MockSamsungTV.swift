#!/usr/bin/env swift
import Foundation
import Network

// A stand-in Samsung TV, so the discovery, pairing and app-launch paths can be exercised
// without waiting for real hardware to be awake.
//
//   swift tools/MockSamsungTV.swift
//
// Then add 127.0.0.1 in the app's "Add by IP address" field. Wand talks plain ws:// to
// loopback (see SamsungSession.isLoopback) precisely so this mock needs no certificate.
//
// Flags:
//   --deny        never authorise, to exercise the unauthorised path
//   --silent      accept the socket but never answer, reproducing the padded-base64 bug
//   --delay <s>   wait before authorising, to mimic a user walking to the TV

let arguments = CommandLine.arguments
let denyMode = arguments.contains("--deny")
let silentMode = arguments.contains("--silent")
let approvalDelay: Double = {
    guard let index = arguments.firstIndex(of: "--delay"), index + 1 < arguments.count else { return 0 }
    return Double(arguments[index + 1]) ?? 0
}()

let installedApps: [String: String] = [
    "111299001912": "YouTube",
    "3201907018807": "Netflix",
    "3201910019365": "Prime Video",
    "3202204027038": "Disney+",
    "3201606009684": "Spotify",
]

let deviceInfo = """
{"device":{"FrameTVSupport":"false","OS":"Tizen","TokenAuthSupport":"true",\
"countryCode":"US","id":"uuid:mock-0000-0000-0000-000000000001","ip":"127.0.0.1",\
"model":"17_KANTM_UHD_BASIC","modelName":"UN65MU6070","name":"[TV] Mock Samsung (65)",\
"networkType":"wired","resolution":"3840x2160","type":"Samsung SmartTV",\
"wifiMac":"7c:64:56:c5:3f:e6"},"id":"uuid:mock-0000-0000-0000-000000000001",\
"isSupport":"{\\"remote_available\\":\\"true\\"}","name":"[TV] Mock Samsung (65)",\
"remote":"1.0","type":"Samsung SmartTV","uri":"http://127.0.0.1:8001/api/v2/","version":"2.0.25"}
"""

func log(_ message: String) {
    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
}

// MARK: - REST API on 8001

func startREST() throws {
    let listener = try NWListener(using: .tcp, on: 8001)

    listener.newConnectionHandler = { connection in
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first
            else { connection.cancel(); return }

            let parts = line.split(separator: " ")
            let method = parts.first.map(String.init) ?? "GET"
            let path = parts.count > 1 ? String(parts[1]) : "/"
            log("REST \(method) \(path)")

            let (status, body): (String, String)
            if path == "/api/v2/" || path == "/api/v2" {
                (status, body) = ("200 OK", deviceInfo)
            } else if path.hasPrefix("/api/v2/applications/") {
                let appID = String(path.dropFirst("/api/v2/applications/".count))
                if let name = installedApps[appID] {
                    if method == "POST" {
                        log("  -> launching \(name)")
                        (status, body) = ("200 OK", "{}")
                    } else {
                        (status, body) = ("200 OK",
                            #"{"id":"\#(appID)","name":"\#(name)","running":false,"version":"1.0","visible":false}"#)
                    }
                } else {
                    (status, body) = ("404 Not Found", "{}")
                }
            } else {
                (status, body) = ("404 Not Found", "{}")
            }

            let response = """
            HTTP/1.1 \(status)\r
            Content-Type: application/json\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    listener.start(queue: .global())
    log("REST API listening on http://127.0.0.1:8001/api/v2/")
}

// MARK: - Control channel on 8002

func startWebSocket() throws {
    let parameters = NWParameters.tcp
    let websocket = NWProtocolWebSocket.Options()
    websocket.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

    let listener = try NWListener(using: parameters, on: 8002)

    listener.newConnectionHandler = { connection in
        log("control channel opened")
        connection.start(queue: .global())

        func send(_ text: String) {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
            connection.send(content: Data(text.utf8), contentContext: context,
                            isComplete: true, completion: .contentProcessed { _ in })
        }

        func receiveLoop() {
            connection.receiveMessage { data, _, _, error in
                if error != nil { log("control channel closed"); return }
                if let data, let text = String(data: data, encoding: .utf8) {
                    log("  <- \(text.prefix(160))")
                }
                receiveLoop()
            }
        }
        receiveLoop()

        if silentMode {
            log("  (silent mode: accepting the socket and saying nothing)")
            return
        }
        if denyMode {
            send(#"{"event":"ms.channel.unauthorized"}"#)
            log("  -> ms.channel.unauthorized")
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + approvalDelay) {
            let token = String(format: "%08d", Int.random(in: 0..<100_000_000))
            send("""
            {"data":{"clients":[{"attributes":{"name":"V2FuZA"},"connectTime":\
            \(Int(Date().timeIntervalSince1970 * 1000)),"deviceName":"V2FuZA",\
            "id":"mock-client","isHost":false}],"id":"mock-client","token":"\(token)"},\
            "event":"ms.channel.connect"}
            """)
            log("  -> ms.channel.connect (token \(token))")
        }
    }
    listener.start(queue: .global())
    log("control channel listening on ws://127.0.0.1:8002/api/v2/channels/samsung.remote.control")
}

do {
    try startREST()
    try startWebSocket()
    log("mock TV ready — add 127.0.0.1 in Wand")
    dispatchMain()
} catch {
    log("failed to start: \(error)")
    exit(1)
}
