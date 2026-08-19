import SwiftUI

/// Types into whatever field the TV currently has focused.
///
/// Uses Samsung's `SendInputString`, which this TV advertises via `ImeSyncedSupport`.
/// Where firmware ignores it, the D-pad still drives the on-screen keyboard — so the
/// sheet says what happened rather than failing silently.
struct KeyboardEntryView: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.Backdrop()

            VStack(spacing: 16) {
                Text("Type on TV")
                    .font(.system(size: 17, weight: .semibold))

                Text("Open a search field on the TV first, then type here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Search…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(Glass.regular, in: .rect(cornerRadius: 14))
                    .onSubmit(send)
                    // Streaming as you type keeps the TV's field in sync, which is what
                    // makes this feel like a keyboard rather than a form.
                    .onChange(of: text) { _, newValue in
                        connections.type(newValue)
                    }

                HStack(spacing: 12) {
                    Button("Clear") {
                        text = ""
                        connections.type("")
                    }
                    .buttonStyle(.glass)

                    Button("Send") { send() }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(24)
        }
        .presentationBackground(.clear)
        .onAppear { focused = true }
    }

    private func send() {
        connections.type(text)
        connections.press(.select)
        Haptics.shared.success()
        dismiss()
    }
}
