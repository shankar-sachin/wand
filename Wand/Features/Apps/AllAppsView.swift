import SwiftUI

/// Every app this TV actually has, and the editor for which four sit on the wand.
struct AllAppsView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections
    @Environment(AppResolver.self) private var resolver
    @Environment(\.dismiss) private var dismiss

    @State private var editingSlots = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Backdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if editingSlots {
                            SlotEditor()
                        }

                        if resolver.isProbing && resolver.installedApps.isEmpty {
                            probingNotice
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(displayedApps) { app in
                                tile(for: app)
                            }
                        }

                        if !resolver.isProbing && resolver.installedApps.isEmpty {
                            emptyNotice
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editingSlots ? "Done" : "Edit Row") {
                        withAnimation(Theme.morph) { editingSlots.toggle() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            guard let host = store.activeDevice?.host else { return }
            await resolver.probe(host: host)
        }
    }

    /// Falls back to the whole catalog while probing hasn't produced anything, so the
    /// grid is never blank.
    private var displayedApps: [TVApp] {
        let installed = resolver.installedApps
        return installed.isEmpty ? TVApp.catalog : installed
    }

    private var probingNotice: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Checking which apps are installed…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 16))
    }

    private var emptyNotice: some View {
        Text("The TV didn't answer the app check — it may be in standby. These are the apps Wand knows about; launching one will still work if it's installed.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(14)
            .glassEffect(Glass.regular, in: .rect(cornerRadius: 16))
    }

    private func tile(for app: TVApp) -> some View {
        Button {
            Haptics.shared.confirm()
            connections.launch(app: app, resolvedID: resolver.resolvedID(for: app))
            dismiss()
        } label: {
            VStack(spacing: 8) {
                AppGlyph(app: app, size: 28)
                Text(app.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .glassEffect(
                Glass.regular.tint(app.tint.opacity(0.2)).interactive(),
                in: .rect(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(app.name)")
    }
}

/// Picks and orders the four apps on the wand. Order is the tap order, so the row can be
/// rebuilt exactly as the user wants it.
struct SlotEditor: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remote row")
                .font(.system(size: 13, weight: .semibold))

            Text("Tap to add or remove. The first four, in tap order, appear on the remote.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            FlowRow {
                ForEach(TVApp.catalog) { app in
                    chip(for: app)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 20))
    }

    private func chip(for app: TVApp) -> some View {
        let slots = store.activeDevice?.appSlots ?? []
        let index = slots.firstIndex(of: app.key)
        let selected = index != nil

        return HStack(spacing: 6) {
            AppGlyph(app: app, size: 13)
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
            if let index {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(app.tint))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(
            selected ? Glass.regular.tint(app.tint.opacity(0.3)) : Glass.regular,
            in: .capsule
        )
        .contentShape(.capsule)
        .onTapGesture { toggle(app) }
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ app: TVApp) {
        guard var device = store.activeDevice else { return }
        if let index = device.appSlots.firstIndex(of: app.key) {
            device.appSlots.remove(at: index)
        } else {
            device.appSlots.append(app.key)
            // Four is what fits on the wand; adding a fifth drops the oldest.
            if device.appSlots.count > 4 { device.appSlots.removeFirst() }
        }
        Haptics.shared.change()
        store.update(device)
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
