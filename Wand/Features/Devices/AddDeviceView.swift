import SwiftUI

/// Finds TVs on the network and pairs with them.
struct AddDeviceView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections
    @Environment(\.dismiss) private var dismiss

    @State private var found: [Discovery.Found] = []
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var manualHost = ""
    @State private var manualError: String?

    var body: some View {
        ZStack {
            Theme.Backdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scanHeader

                    ForEach(found) { device in
                        resultRow(device)
                    }

                    if !scanning && found.isEmpty {
                        Text("No TVs answered. Make sure the TV is on the same Wi-Fi, then scan again — or enter its IP address below.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(Glass.regular, in: .rect(cornerRadius: 18))
                    }

                    manualEntry
                    pairingHelp
                }
                .padding(20)
            }
        }
        .navigationTitle("Add TV")
        .navigationBarTitleDisplayMode(.inline)
        .task { startScan() }
        .onDisappear { scanTask?.cancel() }
    }

    // MARK: Scanning

    private var scanHeader: some View {
        HStack(spacing: 12) {
            if scanning {
                ProgressView()
                Text("Scanning your network…")
                    .font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Theme.selectTint)
                Text(found.isEmpty ? "Scan finished" : "Found \(found.count) TV\(found.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium))
            }

            Spacer()

            Button("Scan Again") { startScan() }
                .font(.system(size: 13, weight: .medium))
                .disabled(scanning)
        }
        .padding(16)
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 18))
    }

    private func startScan() {
        scanTask?.cancel()
        found = []
        scanning = true
        scanTask = Task {
            for await device in Discovery().scan() {
                guard !Task.isCancelled else { break }
                if !found.contains(where: { $0.id == device.id }) {
                    found.append(device)
                    Haptics.shared.change()
                }
            }
            scanning = false
        }
    }

    // MARK: Rows

    private func resultRow(_ device: Discovery.Found) -> some View {
        let alreadySaved = store.devices.contains { $0.deviceIdentifier == device.deviceIdentifier }

        return Button {
            add(device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "tv")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.selectTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(device.model) · \(device.host)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: alreadySaved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(alreadySaved ? .green : Theme.selectTint)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassEffect(Glass.regular.interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func add(_ found: Discovery.Found) {
        let device = TVDevice(
            name: cleanName(found.name),
            tvReportedName: found.name,
            model: found.model,
            deviceIdentifier: found.deviceIdentifier,
            host: found.host,
            macAddress: found.macAddress
        )
        store.add(device)
        connections.syncPool()
        Haptics.shared.success()
        dismiss()
    }

    /// TVs report names like "[TV] Samsung 6 Series (65)". The bracket prefix is noise in
    /// a switcher list.
    private func cleanName(_ raw: String) -> String {
        var name = raw
        if name.hasPrefix("[TV] ") { name.removeFirst(5) }
        return name.isEmpty ? raw : name
    }

    // MARK: Manual entry

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add by IP address")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 10) {
                TextField("192.168.1.50", text: $manualHost)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassEffect(Glass.regular, in: .rect(cornerRadius: 12))

                Button("Add") { addManual() }
                    .buttonStyle(.glassProminent)
                    .disabled(manualHost.isEmpty)
            }

            if let manualError {
                Text(manualError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 18))
    }

    private func addManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        manualError = nil
        Task {
            if let device = await Discovery().probe(host: host) {
                add(device)
            } else {
                manualError = "No Samsung TV answered at \(host)."
                Haptics.shared.failure()
            }
        }
    }

    private var pairingHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("After adding", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))

            Text("""
            The TV shows an "Allow?" prompt the first time Wand connects. Accept it and the pairing is remembered — Wand stores the TV's token in the Keychain and reuses it, so you should never be asked twice.

            Still asked every time? The TV is set to ask every time. On the TV open Settings › General › External Device Manager › Device Connection Manager › Access Notification and choose First Time Only.

            Never asked at all, or the remote stays red? In that same menu open Device List, delete Wand, and connect again.
            """)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 18))
    }
}
