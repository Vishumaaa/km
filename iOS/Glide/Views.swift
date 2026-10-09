import SwiftUI
import GlideNet

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.isConnected {
            TrackpadScreen()
        } else {
            DiscoveryView()
        }
    }
}

struct DiscoveryView: View {
    @EnvironmentObject var app: AppState
    @State private var pending: DiscoveredMac?
    @State private var pin = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.macs.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for your Mac…")
                        }
                    }
                    ForEach(app.macs) { mac in
                        Button { choose(mac) } label: {
                            Label(mac.name, systemImage: "laptopcomputer")
                        }
                    }
                } footer: {
                    Text("Open Glide on your Mac (menu bar icon) and keep both devices on the same Wi-Fi.")
                }

                if app.connection == .connecting {
                    Section {
                        HStack(spacing: 10) { ProgressView(); Text("Connecting…") }
                        Button("Cancel", role: .cancel) { app.disconnect() }
                    }
                }
                if let message = app.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if !app.log.isEmpty {
                    Section("Debug log") {
                        Text(app.log.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Glide")
            .alert("Enter PIN", isPresented: Binding(get: { pending != nil },
                                                     set: { if !$0 { pending = nil } })) {
                TextField("PIN shown on your Mac", text: $pin).keyboardType(.numberPad)
                Button("Connect") {
                    if let mac = pending { app.connect(mac, pin: pin) }
                    pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            }
        }
    }

    private func choose(_ mac: DiscoveredMac) {
        // Always ask: a previously saved wrong PIN used to be reused silently.
        pin = app.savedPIN(for: mac) ?? ""
        pending = mac
    }
}

struct TrackpadScreen: View {
    @EnvironmentObject var app: AppState
    @State private var showTuning = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TouchSurface(tuning: app.tuning) { app.send($0) }
                .ignoresSafeArea()

            HStack(spacing: 18) {
                Button { app.disconnect() } label: { Image(systemName: "xmark.circle.fill") }
                Button { showTuning = true } label: { Image(systemName: "slider.horizontal.3") }
            }
            .font(.title2)
            .foregroundStyle(.white.opacity(0.35))
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let gesture = app.lastGesture {
                Text(gesture)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all) // first edge swipe won't trigger Home / Control Center
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Orientation.lock(.landscape)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Orientation.lock(.allButUpsideDown)
        }
        .sheet(isPresented: $showTuning) {
            TuningView().presentationDetents([.medium])
        }
    }
}

struct TuningView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Pointer") {
                    slider("Sensitivity", value: $app.tuning.sensitivity, range: 0.4...2.5)
                    slider("Slow-speed gain", value: $app.tuning.lowGain, range: 0.5...3)
                    slider("Fast-speed gain", value: $app.tuning.highGain, range: 1...10)
                    slider("Acceleration knee", value: $app.tuning.kneeSpeed, range: 150...2000)
                }
                Section("Holding the phone") {
                    slider("Edge rejection (thumbs)", value: $app.tuning.edgeMargin, range: 0...100)
                }
                Section("Scrolling") {
                    Toggle("Natural scrolling", isOn: $app.tuning.naturalScrolling)
                }
                Section("Haptics") {
                    Toggle("Haptic feedback", isOn: $app.tuning.hapticsEnabled)
                    if app.tuning.hapticsEnabled {
                        slider("Strength", value: $app.tuning.hapticStrength, range: 0.2...1)
                    }
                }
                Section {
                    Button("Reset to defaults", role: .destructive) { app.tuning = Tuning() }
                }
            }
            .navigationTitle("Feel")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
