import SwiftUI

/// The bar across the top of the wand: which TV is being driven, and a one-tap switch.
///
/// Switching is instant because `ConnectionManager` keeps the nearest few TVs connected
/// — the socket for the TV being switched *to* is already open, so the first press after
/// a switch costs the same as any other press.
struct DeviceSwitcherBar: View {
    var onManage: () -> Void
    var onSettings: () -> Void

    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections

    @State private var expanded = false
    @Namespace private var glassNamespace

    var body: some View {
        HStack(spacing: 10) {
            pill
            settingsButton
        }
        .padding(.horizontal, 22)
        .overlay(alignment: .top) {
            if expanded {
                deviceList
                    .padding(.horizontal, 22)
                    .offset(y: 46)
                    .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    // MARK: Pill

    private var pill: some View {
        HStack(spacing: 8) {
            StatusDot(state: connections.activeState)

            Text(store.activeDevice?.name ?? "No TV")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.regular.interactive(), in: .capsule)
        .glassEffectID("switcher", in: glassNamespace)
        .contentShape(.capsule)
        .onTapGesture {
            Haptics.shared.change()
            withAnimation(Theme.morph) { expanded.toggle() }
        }
        // Swiping the pill cycles TVs without opening the list. Deliberately scoped to
        // the pill: a body-wide swipe would fire while sliding a finger on the rockers.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    Haptics.shared.change()
                    store.advanceActive(by: value.translation.width < 0 ? 1 : -1)
                    connections.syncPool()
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current TV: \(store.activeDevice?.name ?? "none")")
        .accessibilityHint("Double tap to switch TVs")
    }

    private var settingsButton: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 38, height: 38)
            .glassEffect(Glass.regular.interactive(), in: .circle)
            .contentShape(.circle)
            .onTapGesture { onSettings() }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Expanded list

    private var deviceList: some View {
        VStack(spacing: 0) {
            ForEach(store.devices) { device in
                row(for: device)
                if device.id != store.devices.last?.id {
                    Divider().opacity(0.25).padding(.horizontal, 14)
                }
            }

            Divider().opacity(0.25).padding(.horizontal, 14)

            Button {
                withAnimation(Theme.morph) { expanded = false }
                onManage()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Add or manage TVs")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 20))
        .glassEffectID("switcher-list", in: glassNamespace)
    }

    private func row(for device: TVDevice) -> some View {
        let isActive = device.id == store.activeDevice?.id
        return HStack(spacing: 10) {
            StatusDot(state: connections.states[device.id] ?? .offline)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Text(device.model)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.selectTint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .onTapGesture {
            Haptics.shared.change()
            store.activeDeviceID = device.id
            connections.syncPool()
            withAnimation(Theme.morph) { expanded = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// The connection indicator. Its own view on purpose: state changes here must not
/// invalidate the thirty keys of the remote around it.
struct StatusDot: View {
    var state: TVConnectionState
    var size: CGFloat = 8

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: size, height: size)
            .overlay {
                if state == .connected {
                    Circle().fill(colour).opacity(0.35).scaleEffect(pulsing ? 2.4 : 1).opacity(pulsing ? 0 : 0.35)
                }
            }
            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }

    private var colour: Color {
        switch state {
        case .connected: .green
        case .connecting, .awaitingApproval: .orange
        case .unauthorized: .red
        case .offline: .gray
        }
    }
}
