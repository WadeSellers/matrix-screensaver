import SwiftUI
import MatrixCore

// MARK: - Palette

/// The four rain colors of the current `MatrixTheme`, as SwiftUI
/// colors. The keypad and the Set-PIN sheet paint only from these, so
/// they always look like they belong to whichever theme is raining
/// behind them — Amber keypad over amber rain, Cobalt over cobalt.
struct PINPalette: Equatable {
    let head: Color
    let near: Color
    let mid: Color
    let far: Color

    init(theme: MatrixTheme) {
        head = Self.color(theme.headColor)
        near = Self.color(theme.nearTrailColor)
        mid  = Self.color(theme.midTrailColor)
        far  = Self.color(theme.farTrailColor)
    }

    private static func color(_ v: SIMD4<Float>) -> Color {
        Color(red: Double(v.x), green: Double(v.y), blue: Double(v.z))
    }
}

// MARK: - Glyph pools

enum PINGlyphs {
    /// Scramble pool — same character set as the Decode and the rain:
    /// half-width katakana, digits, a few symbols.
    static let scramble: [String] = Array(
        "ｦｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:=*+-<>"
    ).map(String.init)

    /// What a typed digit locks into. Katakana only — never a digit —
    /// so a filled slot can't be misread as (or leak) the real number.
    static let mask: [String] = Array(
        "ｦｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ"
    ).map(String.init)

    /// What an *empty* PIN slot scrambles through. No digits: a "6"
    /// flickering in an unfilled slot reads as a typed (and leaked)
    /// digit. Seen in the stills, 2026-10-22.
    static let slotScramble: [String] = Array(
        "ｦｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ:=*+-<>"
    ).map(String.init)

    static func randomScramble() -> String { scramble.randomElement() ?? "ｦ" }
    static func randomSlotScramble() -> String { slotScramble.randomElement() ?? "ｦ" }
    static func randomMask() -> String { mask.randomElement() ?? "ｦ" }
}

// MARK: - Entry model

/// Drives one row of PIN slots in the Decode visual language: empty
/// slots scramble through glyphs, a typed digit "locks" its slot into
/// a masked katakana with a pulse, a wrong PIN glitches the whole row
/// and shakes it, a right one flares bright.
///
/// Shared by the lock-screen keypad and the Settings sheet so the two
/// can't drift apart visually. Holds the typed digits only until the
/// owner takes them with `takePIN()`.
@MainActor
@Observable
final class PINEntryModel {
    enum Phase: Equatable {
        case entry
        case error
        case success
    }

    /// Fixed slot count (known PIN length). Ignored while `grows`.
    private(set) var length: Int = PINRules.minLength
    /// Create-a-PIN mode: the length isn't known yet, so the row
    /// shows the minimum four slots and grows one at a time up to
    /// eight as digits arrive.
    private(set) var grows: Bool = false

    private(set) var phase: Phase = .entry
    /// Glyph shown in each of the (max 8) slots right now.
    private(set) var glyphs: [String]
    /// Per-slot vertical jitter, nonzero only while glitching.
    private(set) var jitter: [CGFloat]
    /// Per-slot lock-in flash.
    private(set) var pulse: [Bool]
    /// Bumped on every wrong entry; views key their shake off it.
    private(set) var shakeCount: Int = 0
    /// Countdown shown in place of the slots during a cooldown, one
    /// glyph per character ("4:59"). Empty when not cooling down.
    private(set) var countdown: [String] = []

    @ObservationIgnored private var digits: [Character] = []
    @ObservationIgnored private var masks: [String]
    @ObservationIgnored private var countdownTarget: [Character] = []
    @ObservationIgnored private var countdownScrambleUntil: [Date] = []
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var phaseTask: Task<Void, Never>?

    /// Mirrors `digits.count`; stored (not computed) so SwiftUI
    /// observes it.
    private(set) var enteredCount: Int = 0

    init() {
        let maxSlots = PINRules.maxLength
        glyphs = (0..<maxSlots).map { _ in PINGlyphs.randomSlotScramble() }
        jitter = Array(repeating: 0, count: maxSlots)
        pulse = Array(repeating: false, count: maxSlots)
        masks = (0..<maxSlots).map { _ in PINGlyphs.randomMask() }
    }

    /// Slots currently drawn.
    var visibleSlots: Int {
        grows
            ? min(max(enteredCount + 1, PINRules.minLength), PINRules.maxLength)
            : length
    }

    var isFull: Bool { !grows && enteredCount >= length }
    var acceptsInput: Bool { phase == .entry && countdown.isEmpty }

    func configure(length: Int, grows: Bool = false) {
        self.length = min(max(length, PINRules.minLength), PINRules.maxLength)
        self.grows = grows
        clear()
    }

    /// Add a digit. Returns true if it was taken.
    @discardableResult
    func append(_ c: Character) -> Bool {
        guard acceptsInput, PINRules.isDigit(c) else { return false }
        let cap = grows ? PINRules.maxLength : length
        guard digits.count < cap else { return false }
        let slot = digits.count
        digits.append(c)
        enteredCount = digits.count
        masks[slot] = PINGlyphs.randomMask()
        glyphs[slot] = masks[slot]
        flash(slot)
        return true
    }

    func deleteLast() {
        guard acceptsInput, !digits.isEmpty else { return }
        digits.removeLast()
        enteredCount = digits.count
    }

    func clear() {
        phaseTask?.cancel()
        digits.removeAll()
        enteredCount = 0
        phase = .entry
        for i in jitter.indices { jitter[i] = 0; pulse[i] = false }
    }

    /// Hand the typed digits to the caller and forget them here.
    func takePIN() -> String {
        let pin = String(digits)
        return pin
    }

    /// Nudge without penalty — e.g. Return pressed on a partial entry.
    func nudge() {
        shakeCount += 1
    }

    /// Wrong PIN: glitch every slot for a beat, shake, then clear.
    func fail(then completion: (@MainActor () -> Void)? = nil) {
        phaseTask?.cancel()
        phase = .error
        shakeCount += 1
        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            self.digits.removeAll()
            self.enteredCount = 0
            for i in self.jitter.indices { self.jitter[i] = 0 }
            self.phase = .entry
            completion?()
        }
    }

    /// Right PIN: every slot locks bright and flares.
    func succeed() {
        phaseTask?.cancel()
        phase = .success
        for i in 0..<visibleSlots { glyphs[i] = masks[i] }
        withAnimation(.easeOut(duration: 0.14)) {
            for i in 0..<visibleSlots { pulse[i] = true }
        }
    }

    /// Show (or clear, with nil) a cooldown countdown. Call once a
    /// second; changed characters scramble briefly before settling,
    /// like a Decode slot resolving.
    func setCountdown(seconds: Int?) {
        guard let seconds, seconds > 0 else {
            countdown = []
            countdownTarget = []
            countdownScrambleUntil = []
            return
        }
        let text = Array(String(format: "%d:%02d", seconds / 60, seconds % 60))
        let now = Date()
        if text.count != countdownTarget.count {
            countdownTarget = text
            countdownScrambleUntil = Array(repeating: now.addingTimeInterval(0.35), count: text.count)
            countdown = text.map { _ in PINGlyphs.randomScramble() }
        } else {
            for i in text.indices where text[i] != countdownTarget[i] {
                countdownScrambleUntil[i] = now.addingTimeInterval(0.25)
            }
            countdownTarget = text
        }
    }

    // MARK: Animation loop

    func startAnimating() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    func stopAnimating() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        switch phase {
        case .error:
            for i in 0..<visibleSlots {
                glyphs[i] = PINGlyphs.randomSlotScramble()
                jitter[i] = CGFloat.random(in: -5...5)
            }
        case .entry:
            // Unfilled slots scramble, each on its own irregular beat
            // so the row shimmers instead of strobing in unison.
            for i in enteredCount..<PINRules.maxLength where Bool.random() {
                glyphs[i] = PINGlyphs.randomSlotScramble()
            }
        case .success:
            break
        }

        if !countdownTarget.isEmpty {
            let now = Date()
            for i in countdownTarget.indices {
                countdown[i] = now < countdownScrambleUntil[i]
                    ? PINGlyphs.randomScramble()
                    : String(countdownTarget[i])
            }
        }
    }

    private func flash(_ slot: Int) {
        withAnimation(.easeOut(duration: 0.10)) { pulse[slot] = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, self.phase == .entry else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.pulse[slot] = false }
        }
    }
}

// MARK: - Slot row

/// One row of PIN slots. Empty slots scramble dimly, the next slot to
/// fill scrambles brighter over a caret, filled slots hold their mask
/// glyph at full brightness, and the row shakes on a miss.
struct PINSlotRow: View {
    let model: PINEntryModel
    let palette: PINPalette
    var glyphSize: CGFloat = 44

    var body: some View {
        Group {
            if model.countdown.isEmpty {
                slots
            } else {
                countdown
            }
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: model.shakeCount) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(16, duration: 0.05)
                LinearKeyframe(-14, duration: 0.06)
                LinearKeyframe(10, duration: 0.06)
                LinearKeyframe(-7, duration: 0.06)
                LinearKeyframe(4, duration: 0.05)
                SpringKeyframe(0, duration: 0.2, spring: .snappy)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var slots: some View {
        HStack(spacing: glyphSize * 0.28) {
            ForEach(0..<model.visibleSlots, id: \.self) { i in
                slot(i)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.visibleSlots)
    }

    private func slot(_ i: Int) -> some View {
        let filled = i < model.enteredCount
        let isNext = i == model.enteredCount && model.phase == .entry
        let pulsing = model.pulse[i]

        let color: Color = switch model.phase {
        case .error: palette.head
        case .success: palette.head
        case .entry: pulsing ? palette.head : (filled ? palette.near : palette.mid)
        }
        let opacity: Double = switch model.phase {
        case .error: Double.random(in: 0.45...1.0)   // flicker
        case .success: 1.0
        // Empty slots stay well under the filled ones so progress reads
        // at a glance even on low-contrast themes (Cobalt's mid and near
        // trail colors are close).
        case .entry: filled ? 1.0 : (isNext ? 0.55 : 0.28)
        }
        let glow: Color = model.phase == .entry && !filled ? palette.mid : palette.near

        return VStack(spacing: glyphSize * 0.12) {
            Text(model.glyphs[i])
                .font(.system(size: glyphSize, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .opacity(opacity)
                .frame(width: glyphSize * 0.95, height: glyphSize * 1.2)
                .scaleEffect(pulsing ? 1.18 : (filled || model.phase == .success ? 1.0 : 0.94))
                .offset(y: model.jitter[i])
                .shadow(color: glow.opacity(0.85), radius: pulsing ? 10 : 4)
                .shadow(color: glow.opacity(0.35), radius: pulsing ? 26 : 14)

            // Baseline under each slot; the next slot's is brighter
            // and breathes, standing in for a text caret.
            Capsule()
                .fill(isNext ? palette.near : palette.mid.opacity(filled ? 0.9 : 0.45))
                .frame(width: glyphSize * 0.7, height: 2)
                .shadow(color: palette.near.opacity(isNext ? 0.8 : 0), radius: 4)
                .phaseAnimator([0.45, 1.0], trigger: isNext) { content, value in
                    content.opacity(isNext ? value : 1.0)
                } animation: { _ in .easeInOut(duration: 0.7) }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.55), value: pulsing)
    }

    private var countdown: some View {
        HStack(spacing: glyphSize * 0.12) {
            ForEach(Array(model.countdown.enumerated()), id: \.offset) { _, glyph in
                Text(glyph)
                    .font(.system(size: glyphSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.near)
                    .frame(width: glyphSize * 0.8, height: glyphSize * 1.2)
                    .shadow(color: palette.near.opacity(0.85), radius: 4)
                    .shadow(color: palette.near.opacity(0.35), radius: 14)
            }
        }
        .padding(.bottom, glyphSize * 0.12 + 2)
    }

    private var accessibilityText: String {
        if !model.countdown.isEmpty { return "Too many tries. Wait \(model.countdown.joined())" }
        return "PIN, \(model.enteredCount) of \(model.visibleSlots) digits entered"
    }
}

// MARK: - Digit pad

/// Clickable 0–9 + delete, for mouse-only use. Glyph-only keys with a
/// hairline ring that lights on hover — no card, no fills at rest, so
/// it reads as part of the rain rather than a phone keypad pasted on.
struct PINDigitPad: View {
    let palette: PINPalette
    var enabled: Bool = true
    var keySize: CGFloat = 54
    let onDigit: (Character) -> Void
    let onDelete: () -> Void

    var body: some View {
        Grid(horizontalSpacing: keySize * 0.38, verticalSpacing: keySize * 0.24) {
            GridRow { key("1"); key("2"); key("3") }
            GridRow { key("4"); key("5"); key("6") }
            GridRow { key("7"); key("8"); key("9") }
            GridRow {
                Color.clear.frame(width: keySize, height: keySize)
                key("0")
                PINKey(label: "⌫", palette: palette, size: keySize, enabled: enabled, action: onDelete)
                    .accessibilityLabel("Delete")
            }
        }
    }

    private func key(_ digit: Character) -> some View {
        PINKey(label: String(digit), palette: palette, size: keySize, enabled: enabled) {
            onDigit(digit)
        }
    }
}

private struct PINKey: View {
    let label: String
    let palette: PINPalette
    let size: CGFloat
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: size * 0.40, weight: .medium, design: .monospaced))
                .foregroundStyle(hovering ? palette.head : palette.near)
                .shadow(color: palette.near.opacity(hovering ? 0.8 : 0.5), radius: hovering ? 6 : 3)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PINKeyButtonStyle(palette: palette, hovering: hovering))
        .focusEffectDisabled()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 && enabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PINKeyButtonStyle: ButtonStyle {
    let palette: PINPalette
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle().fill(palette.near.opacity(configuration.isPressed ? 0.28 : (hovering ? 0.10 : 0)))
            )
            .overlay(
                Circle().stroke(
                    hovering ? palette.near.opacity(0.85) : palette.mid.opacity(0.35),
                    lineWidth: 1
                )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - Lock-screen keypad

/// Everything the lock-screen keypad shows besides the slots. Owned
/// by `PINLockController`, which feeds it and listens to its buttons.
@MainActor
@Observable
final class PINKeypadState {
    let entry = PINEntryModel()
    var palette: PINPalette
    /// Small line above the slots ("enter pin", "wrong pin", …).
    var caption: String = "enter pin"
    /// "Use Touch ID or password" vs. "Use your Mac password".
    var systemAuthLabel: String = "Use Touch ID or password"
    var systemAuthEnabled: Bool = true

    @ObservationIgnored var onDigit: ((Character) -> Void)?
    @ObservationIgnored var onDelete: (() -> Void)?
    @ObservationIgnored var onSystemAuth: (() -> Void)?

    init(palette: PINPalette) {
        self.palette = palette
    }
}

/// The overlay composition: a soft dark pool behind the keypad so the
/// glyphs read against the rain (no card, no frame), caption, slots,
/// digit pad, and the forgot-PIN escape hatch.
struct PINKeypadView: View {
    let state: PINKeypadState

    var body: some View {
        let palette = state.palette
        ZStack {
            // Near-opaque across the whole keypad, feathering out only
            // past its edges. A lighter pool let rain columns run
            // through the digit keys (seen in the stills, 2026-10-22).
            RadialGradient(
                stops: [
                    .init(color: .black.opacity(0.95), location: 0.00),
                    .init(color: .black.opacity(0.90), location: 0.58),
                    .init(color: .black.opacity(0.45), location: 0.82),
                    .init(color: .black.opacity(0.00), location: 1.00)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )
            .frame(width: 1040, height: 1040)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Text(state.caption)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(4)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.near.opacity(0.85))
                    .shadow(color: palette.near.opacity(0.5), radius: 4)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: state.caption)
                    .padding(.bottom, 26)

                PINSlotRow(model: state.entry, palette: palette)
                    .frame(height: 70)
                    .padding(.bottom, 40)

                PINDigitPad(
                    palette: palette,
                    enabled: state.entry.acceptsInput,
                    onDigit: { state.onDigit?($0) },
                    onDelete: { state.onDelete?() }
                )
                .padding(.bottom, 34)

                Button {
                    state.onSystemAuth?()
                } label: {
                    Text(state.systemAuthLabel)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.near.opacity(0.75))
                        .underline(true, color: palette.near.opacity(0.4))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(!state.systemAuthEnabled)
            }
        }
        .onAppear { state.entry.startAnimating() }
        .onDisappear { state.entry.stopAnimating() }
    }
}
