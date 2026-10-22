import SwiftUI

/// What the Set-PIN sheet is being asked to do. Changing or removing
/// a PIN always starts by proving you know the current one.
enum SetPINMode: String, Identifiable {
    case create
    case change
    case disable

    var id: String { rawValue }
}

/// Themed sheet for creating, changing or removing the dismiss PIN.
/// Same slot row and digit pad as the lock-screen keypad, painted in
/// the current theme, so setting the PIN previews exactly what you'll
/// see when you come back to the rain.
///
/// Writes the Keychain itself (save on create/change, delete on
/// disable) and reports back only whether it finished; the caller
/// flips the settings switch to match.
struct SetPINSheet: View {
    let mode: SetPINMode
    let palette: PINPalette
    /// true = the PIN was set / changed / removed; false = cancelled.
    let onFinish: (Bool) -> Void

    private enum Step {
        case current
        case new
        case confirm
    }

    @State private var step: Step = .new
    @State private var entry = PINEntryModel()
    @State private var firstPIN = ""
    @State private var caption = ""
    @State private var isBusy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(palette.mid)
                .padding(.bottom, 18)

            Text(caption)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.near)
                .shadow(color: palette.near.opacity(0.5), radius: 4)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: caption)
                .frame(height: 18)
                .padding(.bottom, 22)

            PINSlotRow(model: entry, palette: palette, glyphSize: 32)
                .frame(height: 52)
                .padding(.bottom, 26)

            PINDigitPad(
                palette: palette,
                enabled: entry.acceptsInput && !isBusy,
                keySize: 42,
                onDigit: { type($0) },
                onDelete: { entry.deleteLast() }
            )
            .padding(.bottom, 26)

            HStack(spacing: 28) {
                sheetButton("Cancel") { onFinish(false) }
                    .keyboardShortcut(.cancelAction)
                if step == .new {
                    sheetButton("Continue", prominent: true) { continueFromNew() }
                        .disabled(entry.enteredCount < PINRules.minLength)
                        .opacity(entry.enteredCount < PINRules.minLength ? 0.4 : 1)
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 30)
        .frame(width: 400)
        .background(
            RadialGradient(
                colors: [palette.far.opacity(0.55), .black],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        )
        .environment(\.colorScheme, .dark)
        // Typing goes straight to the slots — no text field to click.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in handle(press) }
        .onAppear {
            begin()
            entry.startAnimating()
            focused = true
        }
        .onDisappear { entry.stopAnimating() }
    }

    // MARK: - Copy

    private var title: String {
        switch mode {
        case .create: "SET A PIN"
        case .change: "CHANGE PIN"
        case .disable: "TURN OFF PIN"
        }
    }

    // MARK: - Flow

    private func begin() {
        if mode == .create {
            startNew()
        } else if let record = PINStore.loadRecord() {
            step = .current
            entry.configure(length: record.length)
            caption = "Enter your current PIN"
        } else {
            // Switch said on but the Keychain item is gone — nothing to
            // prove. Removing is already done; changing becomes setting.
            if mode == .disable { onFinish(true) } else { startNew() }
        }
    }

    private func startNew(caption newCaption: String = "Choose 4 to 8 digits") {
        step = .new
        firstPIN = ""
        entry.configure(length: PINRules.minLength, grows: true)
        caption = newCaption
    }

    private func type(_ digit: Character) {
        guard !isBusy, entry.append(digit) else { return }
        if entry.isFull { submitFullRow() }
    }

    private func continueFromNew() {
        guard step == .new, entry.enteredCount >= PINRules.minLength, !isBusy else {
            entry.nudge()
            return
        }
        firstPIN = entry.takePIN()
        step = .confirm
        entry.configure(length: firstPIN.count)
        caption = "Enter it again"
    }

    /// A fixed-length row just filled: check the current PIN, or the
    /// confirmation.
    private func submitFullRow() {
        let typed = entry.takePIN()
        switch step {
        case .current:
            isBusy = true
            Task { @MainActor in
                let ok = await Task.detached(priority: .userInitiated) {
                    PINStore.verify(typed)
                }.value
                isBusy = false
                guard ok else {
                    caption = "That's not it"
                    entry.fail()
                    return
                }
                if mode == .disable {
                    PINStore.delete()
                    entry.succeed()
                    finishAfterBeat()
                } else {
                    startNew(caption: "Choose a new PIN, 4 to 8 digits")
                }
            }
        case .confirm:
            guard typed == firstPIN else {
                entry.fail { startNew(caption: "Didn't match. Start again") }
                caption = "Didn't match"
                return
            }
            do {
                try PINStore.save(pin: typed)
                entry.succeed()
                caption = mode == .create ? "PIN set" : "PIN changed"
                finishAfterBeat()
            } catch {
                caption = "Couldn't save to the Keychain"
                entry.fail()
            }
        case .new:
            break  // grows; never "full"
        }
    }

    private func finishAfterBeat() {
        isBusy = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            onFinish(true)
        }
    }

    // MARK: - Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            onFinish(false)
        case .delete, .deleteForward:
            entry.deleteLast()
        case .return:
            if step == .new { continueFromNew() } else if entry.enteredCount > 0 { entry.nudge() }
        default:
            guard press.modifiers.isDisjoint(with: [.command, .control]),
                  let c = press.characters.first, PINRules.isDigit(c) else {
                return .ignored
            }
            type(c)
        }
        return .handled
    }

    // MARK: - Buttons

    private func sheetButton(_ label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: prominent ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(prominent ? Color.black : palette.near)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(prominent ? palette.near : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(prominent ? Color.clear : palette.mid.opacity(0.6), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
