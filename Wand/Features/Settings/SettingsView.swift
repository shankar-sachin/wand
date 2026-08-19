import SwiftUI

struct SettingsView: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(DeviceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wand.appearance") private var appearance = AppearanceMode.system
    @AppStorage("wand.haptics") private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { _, value in
                            Haptics.shared.enabled = value
                            if value { Haptics.shared.warm() }
                        }
                }

                Section {
                    NavigationLink {
                        DeviceListView()
                    } label: {
                        Label("TVs", systemImage: "tv")
                    }
                }

                Section {
                    LabeledContent("Commands sent", value: "\(connections.latency.count)")
                    LabeledContent("Median", value: format(connections.latency.median))
                    LabeledContent("95th percentile", value: format(connections.latency.p95))
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Time from your finger touching a key to the command leaving the phone. Keys fire on touch-down and the connection is held open, so this is the whole cost on this side of the network.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                } footer: {
                    Text("Wand controls Samsung Tizen TVs from 2016 onward over your local network.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f ms", value)
    }
}

extension Bundle {
    /// "1.0.0 (1)" — marketing version with the build number, as shown in Settings.
    var displayVersion: String {
        let marketing = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String
        guard let build, build != marketing else { return marketing }
        return "\(marketing) (\(build))"
    }
}
