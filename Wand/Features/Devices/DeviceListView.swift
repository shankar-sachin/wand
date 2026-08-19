import SwiftUI

/// Manage saved TVs: reorder, rename, re-pair, remove.
struct DeviceListView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Backdrop()

                List {
                    Section {
                        ForEach(store.devices) { device in
                            NavigationLink {
                                DeviceDetailView(deviceID: device.id)
                            } label: {
                                row(for: device)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { store.remove(store.devices[index]) }
                            connections.syncPool()
                        }
                        .onMove { source, destination in
                            store.move(from: source, to: destination)
                        }
                    } header: {
                        Text("Your TVs")
                    } footer: {
                        Text("The first few TVs stay connected in the background, so switching between them is instant.")
                    }

                    Section {
                        NavigationLink {
                            AddDeviceView()
                        } label: {
                            Label("Add a TV", systemImage: "plus.circle.fill")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("TVs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for device: TVDevice) -> some View {
        HStack(spacing: 12) {
            StatusDot(state: connections.states[device.id] ?? .offline, size: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 15, weight: .medium))
                Text("\(device.model) · \(device.host)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if connections.needsRepair.contains(device.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs pairing")
            }
        }
    }
}

/// One TV's settings.
struct DeviceDetailView: View {
    let deviceID: UUID

    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections

    @State private var name = ""
    @State private var host = ""
    @State private var mac = ""
    @State private var loaded = false

    private var device: TVDevice? {
        store.devices.first { $0.id == deviceID }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Living Room", text: $name)
                    .onSubmit(save)
            }

            Section {
                LabeledContent("Model", value: device?.model ?? "—")
                TextField("IP address", text: $host)
                    .keyboardType(.decimalPad)
                    .onSubmit(save)
                TextField("MAC address", text: $mac)
                    .autocorrectionDisabled()
                    .onSubmit(save)
            } header: {
                Text("Connection")
            } footer: {
                Text("The MAC address is used to wake the TV from standby. Wake-on-LAN needs Power On with Mobile enabled on the TV, under General › Network › Expert Settings.")
            }

            Section {
                LabeledContent("Status", value: statusText)
                Button("Pair Again") {
                    guard let device else { return }
                    connections.repair(device)
                    Haptics.shared.change()
                }
                Button("Wake TV") {
                    guard let device else { return }
                    connections.wake(device)
                    Haptics.shared.change()
                }
                .disabled(device?.macAddress == nil)
            } header: {
                Text("Pairing")
            } footer: {
                Text("""
                Wand keeps this TV's pairing token in the Keychain and reuses it, so the TV should only ask once. If it asks every time, set Access Notification to First Time Only on the TV, under General › External Device Manager › Device Connection Manager.

                Pair Again deliberately forgets the token so the TV prompts on the next connection. Nothing else ever discards it.
                """)
            }
        }
        .navigationTitle(device?.name ?? "TV")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let device else { return }
            name = device.name
            host = device.host
            mac = device.macAddress ?? ""
            loaded = true
        }
        .onDisappear(perform: save)
    }

    private var statusText: String {
        switch connections.states[deviceID] ?? .offline {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .awaitingApproval: "Waiting for the TV's Allow prompt"
        case .unauthorized: "Not authorised — pair again"
        case .offline: "Offline"
        }
    }

    private func save() {
        guard var device else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedHost.isEmpty else { return }

        let hostChanged = trimmedHost != device.host
        device.name = trimmedName
        device.host = trimmedHost
        device.macAddress = mac.isEmpty ? nil : mac
        store.update(device)

        // A new address means the existing socket points at nothing.
        if hostChanged { connections.syncPool() }
    }
}
