import SwiftUI

struct RootView: View {
    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections
    @State private var resolver = AppResolver()

    var body: some View {
        ZStack {
            Theme.Backdrop()

            if store.hasDevices {
                // The banner is a sibling rather than an overlay: it takes layout space,
                // and because the wand scales to whatever height it's given, the remote
                // simply shrinks instead of having its app keys covered.
                VStack(spacing: 0) {
                    RemoteView()
                        .environment(resolver)
                    RepairBanner()
                }
            } else {
                WelcomeView()
            }
        }
        .task(id: store.activeDevice?.host) {
            guard let host = store.activeDevice?.host else { return }
            await resolver.probe(host: host)
        }
    }
}

/// First run: nothing saved yet.
struct WelcomeView: View {
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Inside the stack, not behind it: NavigationStack paints its own opaque
                // background, which would cover a backdrop applied by the parent.
                Theme.Backdrop()

                content
            }
            .navigationDestination(isPresented: $showAdd) {
                AddDeviceView()
            }
        }
    }

    private var content: some View {
            VStack(spacing: 22) {
                Spacer()

                Image(systemName: "wand.and.rays")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.selectTint)

                VStack(spacing: 8) {
                    Text("Wand")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("A remote for your Samsung TVs.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Text("Make sure your TV is on and connected to this Wi-Fi, then find it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)

                Button {
                    showAdd = true
                } label: {
                    Label("Find my TV", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)

                Spacer()
            }
    }
}

/// Surfaces the one failure the user has to act on: the TV refused our pairing, which
/// can only be cleared at the TV. Silent failure here is the difference between "the app
/// is broken" and "press Allow".
struct RepairBanner: View {
    @Environment(DeviceStore.self) private var store
    @Environment(ConnectionManager.self) private var connections

    var body: some View {
        if let device = store.activeDevice, connections.needsRepair.contains(device.id) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(device.name) hasn't allowed Wand")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Accept the prompt on the TV, or tap to try again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .glassEffect(Glass.regular.tint(.orange.opacity(0.2)).interactive(), in: .rect(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .contentShape(.rect)
            .onTapGesture {
                Haptics.shared.change()
                connections.repair(device)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
