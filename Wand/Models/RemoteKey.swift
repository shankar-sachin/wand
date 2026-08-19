import Foundation

/// A Samsung Tizen remote key code.
///
/// Raw values are the literal `DataOfCmd` strings the TV expects in a
/// `SendRemoteKey` payload — see `SamsungSession.encode(_:)`.
enum RemoteKey: String, Sendable, CaseIterable {
    // Power
    case power = "KEY_POWER"
    case powerOff = "KEY_POWEROFF"
    case powerOn = "KEY_POWERON"

    // Navigation
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case select = "KEY_ENTER"
    case back = "KEY_RETURN"
    case exit = "KEY_EXIT"
    case home = "KEY_HOME"
    case menu = "KEY_MENU"
    case source = "KEY_SOURCE"
    case guide = "KEY_GUIDE"
    case tools = "KEY_TOOLS"
    case info = "KEY_INFO"

    // Volume
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"

    // Channel
    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case channelList = "KEY_CH_LIST"
    case previousChannel = "KEY_PRECH"

    // Digits
    case digit0 = "KEY_0"
    case digit1 = "KEY_1"
    case digit2 = "KEY_2"
    case digit3 = "KEY_3"
    case digit4 = "KEY_4"
    case digit5 = "KEY_5"
    case digit6 = "KEY_6"
    case digit7 = "KEY_7"
    case digit8 = "KEY_8"
    case digit9 = "KEY_9"

    // Transport
    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case playPause = "KEY_PLAY_BACK"
    case stop = "KEY_STOP"
    case rewind = "KEY_REWIND"
    case fastForward = "KEY_FF"

    // Colour keys
    case red = "KEY_RED"
    case green = "KEY_GREEN"
    case yellow = "KEY_YELLOW"
    case blue = "KEY_BLUE"

    /// The digit key for `0...9`, used by the number pad.
    static func digit(_ value: Int) -> RemoteKey? {
        RemoteKey(rawValue: "KEY_\(value)")
    }
}
