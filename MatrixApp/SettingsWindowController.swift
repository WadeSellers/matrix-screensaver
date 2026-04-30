import Cocoa
import SwiftUI
import MatrixCore

/// Hosts the Settings SwiftUI view in an NSWindow. Singleton-style: one
/// shared window, brought to front on each show().
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    /// Bound to AppSettings via a Combine-style observable. Created once
    /// per controller; the SwiftUI view reads/writes through it.
    private let model: SettingsModel

    init(initial: AppSettings, onChange: @escaping (AppSettings) -> Void) {
        self.model = SettingsModel(initial: initial, onChange: onChange)
    }

    func show() {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(model: model)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "Matrix Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 400, height: 360))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Observable model bridging SwiftUI bindings to AppSettings + a callback.
/// Deliberately small — we don't pull in Combine; just @Observable.
@MainActor
@Observable
final class SettingsModel {
    var settings: AppSettings {
        didSet {
            if settings != oldValue {
                onChange(settings)
            }
        }
    }
    private let onChange: (AppSettings) -> Void

    init(initial: AppSettings, onChange: @escaping (AppSettings) -> Void) {
        self.settings = initial
        self.onChange = onChange
    }
}

private struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section("Rendering") {
                HStack {
                    Text("Speed")
                        .frame(width: 80, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.matrix.speedMultiplier) },
                            set: { model.settings.matrix.speedMultiplier = Float($0) }
                        ),
                        in: 0.25...3.0
                    )
                    Text(String(format: "%.2f×", model.settings.matrix.speedMultiplier))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }

                Toggle(
                    "Bloom glow on heads",
                    isOn: Binding(
                        get: { model.settings.matrix.bloomEnabled },
                        set: { model.settings.matrix.bloomEnabled = $0 }
                    )
                )

                Toggle(
                    "CRT mode (scanlines + vignette)",
                    isOn: Binding(
                        get: { model.settings.matrix.crtEnabled },
                        set: { model.settings.matrix.crtEnabled = $0 }
                    )
                )
            }

            Section("Auto-activate") {
                Toggle(
                    "Activate when idle",
                    isOn: Binding(
                        get: { model.settings.autoActivateOnIdle },
                        set: { model.settings.autoActivateOnIdle = $0 }
                    )
                )

                HStack {
                    Text("Idle threshold")
                        .frame(width: 110, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { model.settings.idleThresholdMinutes },
                            set: { model.settings.idleThresholdMinutes = $0 }
                        ),
                        in: 1...30,
                        step: 1
                    )
                    .disabled(!model.settings.autoActivateOnIdle)
                    Text("\(Int(model.settings.idleThresholdMinutes)) min")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Section {
                Text("Changes apply immediately and are remembered between launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
