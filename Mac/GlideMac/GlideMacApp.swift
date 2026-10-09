import SwiftUI
import GlideNet

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show a Dock icon and a real window too: menu-bar icons can be hidden by the notch.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.start()
    }
}

@main
struct GlideMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Glide", id: "main") {
            MenuView(model: AppModel.shared)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Glide", systemImage: "hand.point.up.left.fill") {
            MenuView(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glide").font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text("Enter this PIN on your iPhone").font(.caption).foregroundStyle(.secondary)
                Text(model.pin)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }

            Label(statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)

            if !model.accessibilityTrusted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Accessibility access needed to move the cursor", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button("Grant Access…") { model.requestAccessibility() }
                }
            }

            if !model.log.isEmpty {
                Text(model.log.suffix(5).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Button("New PIN") { model.newPIN() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var statusText: String {
        switch model.status {
        case .stopped: return "Stopped"
        case .listening: return "Waiting for iPhone…"
        case .connected: return "iPhone connected"
        case let .failed(message): return "Error: \(message)"
        }
    }

    private var statusIcon: String {
        if case .connected = model.status { return "iphone.radiowaves.left.and.right" }
        return "dot.radiowaves.left.and.right"
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
