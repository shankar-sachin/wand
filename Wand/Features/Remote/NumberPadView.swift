import SwiftUI

/// The number pad behind the `123` key, plus the transport and utility keys that don't
/// have a face on the wand itself.
struct NumberPadView: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            Theme.Backdrop()

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...9, id: \.self) { digit in
                            digitKey(digit)
                        }
                        KeyButton(face: .symbol("arrow.uturn.backward"), diameter: 60,
                                  accessibilityLabel: "Previous channel") {
                            connections.press(.previousChannel)
                        }
                        digitKey(0)
                        KeyButton(face: .symbol("checkmark"), tint: Theme.selectTint, diameter: 60,
                                  accessibilityLabel: "Enter") {
                            connections.press(.select)
                        }
                    }

                    HStack(spacing: 14) {
                        utility(symbol: "backward.fill", label: "Rewind", key: .rewind)
                        utility(symbol: "play.fill", label: "Play", key: .play)
                        utility(symbol: "pause.fill", label: "Pause", key: .pause)
                        utility(symbol: "forward.fill", label: "Fast forward", key: .fastForward)
                    }

                    HStack(spacing: 14) {
                        utility(symbol: "rectangle.on.rectangle", label: "Source", key: .source)
                        utility(symbol: "info.circle", label: "Info", key: .info)
                        utility(symbol: "list.bullet", label: "Channel list", key: .channelList)
                        utility(symbol: "xmark", label: "Exit", key: .exit)
                    }
                }
                .padding(24)
            }
        }
        .presentationBackground(.clear)
    }

    private func digitKey(_ digit: Int) -> some View {
        KeyButton(face: .text("\(digit)"), diameter: 60, accessibilityLabel: "\(digit)") {
            guard let key = RemoteKey.digit(digit) else { return }
            connections.press(key)
        }
    }

    private func utility(symbol: String, label: String, key: RemoteKey) -> some View {
        KeyButton(face: .symbol(symbol), diameter: 52, accessibilityLabel: label) {
            connections.press(key)
        }
    }
}
