import Cocoa
import MatrixCore

/// Programmatic settings sheet shown by the screensaver "Screen Saver
/// Options…" button in System Settings. Built with NSStackView rather than
/// an XIB so the source is reviewable in plain text.
@MainActor
final class ConfigSheet: NSObject {
    let window: NSWindow

    private let speedSlider: NSSlider
    private let speedValueLabel: NSTextField
    private let bloomCheckbox: NSButton
    private let crtCheckbox: NSButton

    private weak var saverView: MatrixSaverView?
    private let defaults: UserDefaults?

    init(
        saverView: MatrixSaverView,
        current: MatrixSettings,
        defaults: UserDefaults?
    ) {
        self.saverView = saverView
        self.defaults = defaults

        let speedSlider = NSSlider(value: Double(current.speedMultiplier),
                                   minValue: 0.5,
                                   maxValue: 2.0,
                                   target: nil,
                                   action: nil)
        speedSlider.numberOfTickMarks = 16
        speedSlider.allowsTickMarkValuesOnly = false
        speedSlider.controlSize = .regular
        self.speedSlider = speedSlider

        self.speedValueLabel = ConfigSheet.makeValueLabel(current.speedMultiplier)

        self.bloomCheckbox = NSButton(
            checkboxWithTitle: "Bloom glow on heads",
            target: nil,
            action: nil
        )
        bloomCheckbox.state = current.bloomEnabled ? .on : .off

        self.crtCheckbox = NSButton(
            checkboxWithTitle: "CRT mode (scanlines + vignette)",
            target: nil,
            action: nil
        )
        crtCheckbox.state = current.crtEnabled ? .on : .off

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix Screensaver"
        self.window = window

        super.init()

        speedSlider.target = self
        speedSlider.action = #selector(speedChanged(_:))
        bloomCheckbox.target = self
        bloomCheckbox.action = #selector(bloomToggled(_:))
        crtCheckbox.target = self
        crtCheckbox.action = #selector(crtToggled(_:))

        layoutContents()
    }

    private func layoutContents() {
        let title = NSTextField(labelWithString: "Matrix Screensaver Settings")
        title.font = NSFont.boldSystemFont(ofSize: 14)

        let speedRow = NSStackView()
        speedRow.orientation = .horizontal
        speedRow.alignment = .centerY
        speedRow.spacing = 12
        let speedLabel = NSTextField(labelWithString: "Speed:")
        speedLabel.alignment = .right
        speedLabel.preferredMaxLayoutWidth = 60
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        speedRow.addArrangedSubview(speedLabel)
        speedRow.addArrangedSubview(speedSlider)
        speedRow.addArrangedSubview(speedValueLabel)

        let info = NSTextField(wrappingLabelWithString:
            "Closes automatically; settings are saved to your screensaver defaults."
        )
        info.font = NSFont.systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .gravityAreas
        buttonRow.addView(NSView(), in: .leading)  // spacer
        buttonRow.addView(doneButton, in: .trailing)

        let stack = NSStackView(views: [
            title,
            speedRow,
            bloomCheckbox,
            crtCheckbox,
            info,
            buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 16, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])

        window.contentView = content
    }

    private static func makeValueLabel(_ value: Float) -> NSTextField {
        let l = NSTextField(labelWithString: ConfigSheet.formatSpeed(value))
        l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        l.alignment = .right
        l.preferredMaxLayoutWidth = 50
        return l
    }

    private static func formatSpeed(_ v: Float) -> String {
        String(format: "%.2fx", v)
    }

    @objc private func speedChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        speedValueLabel.stringValue = Self.formatSpeed(value)
        saverView?.applyLiveSettings { $0.speedMultiplier = value }
    }

    @objc private func bloomToggled(_ sender: NSButton) {
        saverView?.applyLiveSettings { $0.bloomEnabled = sender.state == .on }
    }

    @objc private func crtToggled(_ sender: NSButton) {
        saverView?.applyLiveSettings { $0.crtEnabled = sender.state == .on }
    }

    @objc private func done(_ sender: NSButton) {
        saverView?.persistSettings(defaults)
        // Cooperate with whatever sheet host the system created. If we were
        // shown via beginSheet, endSheet does the right thing; otherwise just
        // close.
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: .OK)
        } else {
            window.close()
        }
    }
}
