import Cocoa
import SwiftUI
import StoreKit

/// Hosts the post-tip "Decode" full-screen Easter egg — pure-black
/// takeover, eight letters scrambling through Matrix-style glyphs and
/// locking into "THANK YOU" in a random order. ~9 seconds end to end,
/// then auto-dismiss.
///
/// Triggered by `TipJarManager.onPurchaseSucceeded` after Apple's
/// purchase sheet confirms a tip. Pure SwiftUI; no Metal needed — the
/// theatrics are all in animated text on a black background.
@MainActor
final class ThankYouController: NSObject {
    private var window: NSPanel?
    private var safetyTimer: Timer?

    /// Show the Decode animation for a successfully-tipped product.
    /// Idempotent: a second call while the first sequence is still on
    /// screen tears down the previous and starts fresh.
    func present(for product: Product) {
        dismiss()  // tear down any in-flight sequence

        guard let screen = NSScreen.main else { return }

        // Borderless fullscreen panel at the shielding-window level —
        // sits above Stage Manager, fullscreen apps, and Mission
        // Control. Panel is transparent; the SwiftUI scene paints the
        // black background itself with an animated opacity so the
        // fade-in shows the user's desktop briefly behind the glyphs
        // before everything dims to black.
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false  // swallow mouse so clicks don't fall through
        panel.isReleasedWhenClosed = false

        let scene = ThankYouScene(
            tier: TierInfo(for: product),
            onComplete: { [weak self] in
                self?.dismiss()
            }
        )
        let host = NSHostingView(rootView: scene)
        host.frame = screen.frame
        // Sizing options empty: don't let SwiftUI's intrinsic size push
        // the panel around. The panel is fullscreen-fixed.
        host.sizingOptions = []
        panel.contentView = host

        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        self.window = panel

        // Safety net: if the SwiftUI Task ever fails to call onComplete
        // (suspended app, OS hiccup, etc.), force-dismiss at 12s so we
        // never leave a black screen stuck on the user's display.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

// MARK: - Tier copy

/// Per-tier signature line shown below the locked "THANK YOU."
/// Differentiates a $19 tipper from a $3 tipper at the moment of
/// celebration — the same effort earns a different signoff.
private struct TierInfo {
    let signature: String

    init(for product: Product) {
        switch product.id {
        case "com.wadesellers.cipherfall.tip.coffee":
            signature = "— for the coffee ☕"
        case "com.wadesellers.cipherfall.tip.lunch":
            signature = "— for the lunch 🍕"
        case "com.wadesellers.cipherfall.tip.awesome":
            signature = "— you're a legend ❤️"
        default:
            signature = "— thank you"
        }
    }
}

// MARK: - Decode state machine

/// Drives the full-screen scramble-and-collapse animation. Phases:
///
/// 1. **Fade-in (0–2.5s):** the desktop dims to black while a full-
///    screen-wide row of scrambling glyphs fades up over it.
/// 2. **Decoy collapse (2.5–4.5s):** the outermost glyphs in the row
///    fade out, working inward, leaving only nine center slots
///    (T H A N K _ Y O U; the middle slot is a space placeholder).
/// 3. **Anchor lock (3.0–6.0s, overlapping the collapse):** the
///    eight letter slots and the middle space slot decelerate and
///    snap into their final characters in a random order.
/// 4. **Finale (6.4–11.4s):** subtitle fades in, hold for ~3s, fade
///    everything out, dismiss.
///
/// Lock order across the nine center slots is randomized every
/// presentation, so no two purchases feel identical.
@MainActor
@Observable
private final class DecodeViewModel {
    /// Nine slots: T H A N K [space] Y O U. The space slot scrambles
    /// like all the others and "locks" to " " — which renders as
    /// nothing — producing the visual gap between THANK and YOU
    /// without special-case layout.
    static let target: [String] = ["T", "H", "A", "N", "K", " ", "Y", "O", "U"]
    /// Number of letter-glyphs occupying the iconic THANK_YOU center.
    static let anchorCount: Int = target.count

    /// Total number of slots in the full-screen row, computed from
    /// screen width at init.
    let glyphCount: Int
    /// Indices in `currentGlyphs` that will eventually lock into the
    /// target letters. Ordered left to right.
    let anchorIndices: [Int]

    /// Glyphs currently displayed in each slot. Mutated by the
    /// scramble loop. Initialized with a random fill.
    var currentGlyphs: [String]
    /// Per-slot opacity. All start at 1.0. Decoy slots animate to 0.0
    /// during the collapse phase; anchor slots stay at 1.0 throughout.
    var slotOpacities: [Double]
    /// `true` once an anchor slot has snapped into its target letter.
    /// Non-anchor entries stay false forever (no-op for them).
    var lockedFlags: [Bool]
    /// Brief per-anchor scale+glow flash on lock-in.
    var pulseFlags: [Bool]
    /// Drives the global fade-in (black background + glyph row
    /// opacity together) over the first ~2.5s.
    var globalFadeIn: Double = 0.0
    /// All anchors have settled into their target letters.
    var allLocked: Bool = false
    /// Subtitle fade in (after a beat once all letters lock).
    var subtitleVisible: Bool = false
    /// Whole composition fading out toward the dismiss.
    var isExiting: Bool = false

    private let letterTargets: [Int: String]   // anchor slot → letter
    private let lockTimes: [Int: Double]       // anchor slot → lock time
    private let decoyFadeTimes: [Int: Double]  // decoy slot → fade-start time
    private var lastSwapTimes: [Double]
    private var decoyFadeStarted: Set<Int> = []
    private let onComplete: () -> Void

    /// Glyph pool for the scramble. Half-width katakana (the iconic
    /// Matrix character set), digits, and a few symbols. Picks one at
    /// random per swap. Final lock letters (T/H/A/N/K/Y/O/U) are
    /// intentionally allowed in the pool — they'll occasionally flash
    /// during scramble, which feels organic, not a spoiler.
    private static let glyphPool: [String] = Array(
        "ｦｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ" +
            "0123456789" +
            ":·=*+-<>?#"
    ).map { String($0) }

    init(screenWidth: Double, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        // Compute glyph count from screen width. Target slot width
        // ~110pt logical → on a 1920pt-wide display we get ~17 slots,
        // on a 1440pt MacBook display we get ~13. Clamp so we always
        // have at least 3 decoys on each side for the collapse to
        // feel meaningful, and no more than 25 (visual noise ceiling).
        let targetSlotWidth: Double = 110
        let raw = Int((screenWidth / targetSlotWidth).rounded())
        let count = max(Self.anchorCount + 6, min(25, raw))
        self.glyphCount = count

        // Anchors live in the exact center of the row.
        let anchorStart = (count - Self.anchorCount) / 2
        let anchors = Array(anchorStart..<(anchorStart + Self.anchorCount))
        self.anchorIndices = anchors

        // Map anchor slot → target letter.
        var letterMap: [Int: String] = [:]
        for (offset, slot) in anchors.enumerated() {
            letterMap[slot] = Self.target[offset]
        }
        self.letterTargets = letterMap

        // Initial state.
        self.currentGlyphs = (0..<count).map { _ in Self.glyphPool.randomElement() ?? "?" }
        self.slotOpacities = Array(repeating: 1.0, count: count)
        self.lockedFlags = Array(repeating: false, count: count)
        self.pulseFlags = Array(repeating: false, count: count)
        self.lastSwapTimes = Array(repeating: 0.0, count: count)

        // Anchor lock times: random permutation, distributed 3.0s →
        // 6.0s. The first anchor in the shuffled order locks at ~3s
        // (while the outermost decoys are still fading); the last
        // anchor locks at ~6s.
        let permutation = Array(0..<Self.anchorCount).shuffled()
        var lockMap: [Int: Double] = [:]
        for (rank, perm) in permutation.enumerated() {
            let base = 3.0 + (Double(rank) / Double(Self.anchorCount - 1)) * 3.0
            let jitter = Double.random(in: -0.15...0.15)
            lockMap[anchors[perm]] = base + jitter
        }
        self.lockTimes = lockMap

        // Decoy fade-out times: outermost first, working inward.
        // Distributed across 2.5s → 4.5s.
        let anchorSet = Set(anchors)
        var decoys: [Int] = (0..<count).filter { !anchorSet.contains($0) }
        let centerPoint = Double(count - 1) / 2.0
        decoys.sort { abs(Double($0) - centerPoint) > abs(Double($1) - centerPoint) }
        var fadeMap: [Int: Double] = [:]
        let decoyDuration: Double = 2.0
        for (rank, slot) in decoys.enumerated() {
            let progress = decoys.count == 1 ? 0.5 : Double(rank) / Double(decoys.count - 1)
            fadeMap[slot] = 2.5 + progress * decoyDuration
        }
        self.decoyFadeTimes = fadeMap
    }

    /// Main animation loop. Runs ~60Hz; each tick advances every
    /// unlocked letter, kicks off decoy fades when their time comes,
    /// locks anchors whose time has come, and orchestrates the
    /// post-lock subtitle / hold / fade / dismiss timeline.
    func run() async {
        let start = Date()

        // Phase 1: global fade-in. Black background + glyph row
        // opacity climb from 0 to 1 over 2.5s. Eye-easing curve.
        withAnimation(.easeInOut(duration: 2.5)) {
            globalFadeIn = 1.0
        }

        while !isExiting {
            let elapsed = Date().timeIntervalSince(start)

            // Scramble every slot that hasn't locked and hasn't faded
            // to invisible. Decoy slots keep scrambling even as they
            // fade — the fade is opacity-only, the content underneath
            // is alive until it vanishes. Looks more organic.
            for i in 0..<glyphCount {
                if lockedFlags[i] { continue }

                // Decelerate near lock time (anchors only). Decoys
                // scramble at the fast rate throughout their life.
                let swapInterval: Double
                if let lockAt = lockTimes[i] {
                    swapInterval = Self.swapInterval(timeUntilLock: lockAt - elapsed)
                } else {
                    swapInterval = 0.08
                }

                if elapsed - lastSwapTimes[i] >= swapInterval {
                    currentGlyphs[i] = Self.glyphPool.randomElement() ?? "?"
                    lastSwapTimes[i] = elapsed
                }
            }

            // Lock anchors whose time has come.
            for (slot, lockAt) in lockTimes {
                if !lockedFlags[slot] && elapsed >= lockAt {
                    currentGlyphs[slot] = letterTargets[slot] ?? "?"
                    lockedFlags[slot] = true
                    triggerPulse(at: slot)
                }
            }

            // Kick off decoy fade-outs whose time has come (one-shot
            // per slot, animated to 0 over 0.7s).
            for (slot, fadeAt) in decoyFadeTimes {
                if !decoyFadeStarted.contains(slot) && elapsed >= fadeAt {
                    decoyFadeStarted.insert(slot)
                    withAnimation(.easeOut(duration: 0.7)) {
                        slotOpacities[slot] = 0.0
                    }
                }
            }

            // All anchors locked? Begin finale.
            let everyAnchorLocked = anchorIndices.allSatisfy { lockedFlags[$0] }
            if !allLocked && everyAnchorLocked {
                allLocked = true
                Task { @MainActor in await runFinale() }
                return
            }

            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    /// Brief scale+glow flash on a freshly-locked letter.
    private func triggerPulse(at slot: Int) {
        withAnimation(.easeOut(duration: 0.12)) {
            pulseFlags[slot] = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeIn(duration: 0.25)) {
                pulseFlags[slot] = false
            }
        }
    }

    /// After all letters lock: short beat, subtitle in, hold, fade,
    /// signal dismiss. Total tail: ~5 seconds.
    private func runFinale() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(.easeIn(duration: 0.55)) {
            subtitleVisible = true
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation(.easeInOut(duration: 1.5)) {
            isExiting = true
        }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        onComplete()
    }

    /// Decelerating swap-interval curve. Fast (80ms) while far from
    /// lock; slows quadratically over the last 700ms to 400ms between
    /// swaps. The deceleration is what sells the "machine resolving a
    /// cipher" effect.
    private static func swapInterval(timeUntilLock: Double) -> Double {
        let decelWindow: Double = 0.7
        if timeUntilLock > decelWindow {
            return 0.08
        }
        let normalized = max(0.0, timeUntilLock / decelWindow)
        let eased = 1.0 - (normalized * normalized)
        return 0.08 + eased * (0.40 - 0.08)
    }
}

// MARK: - SwiftUI scene

/// The on-screen composition. A full-width row of scrambling glyphs in
/// Matrix green that fades in over the user's desktop, narrows to nine
/// center slots as the decoys fade out, locks into "THANK YOU," holds,
/// and fades to black.
private struct ThankYouScene: View {
    let tier: TierInfo
    let onComplete: () -> Void

    @State private var model: DecodeViewModel

    init(tier: TierInfo, onComplete: @escaping () -> Void) {
        self.tier = tier
        self.onComplete = onComplete
        // Pull the main screen's width at init so the model can size
        // its row to fill it. GeometryReader does the per-slot layout
        // math at render time too, but slot COUNT has to be decided
        // here, before the view tree exists.
        let screenWidth = Double(NSScreen.main?.frame.width ?? 1920)
        _model = State(wrappedValue: DecodeViewModel(
            screenWidth: screenWidth,
            onComplete: onComplete
        ))
    }

    /// Signature Matrix near-trail green.
    private let matrixGreen = Color(red: 0.40, green: 0.95, blue: 0.55)
    private let matrixGreenBright = Color(red: 0.72, green: 1.00, blue: 0.80)

    var body: some View {
        GeometryReader { proxy in
            // Slot width fills the row evenly; letter glyph fills most
            // of the slot. Height scales modestly with screen size.
            let slotWidth = proxy.size.width / CGFloat(model.glyphCount)
            let letterSize = min(slotWidth * 0.82, proxy.size.height / 4.5)
            let subtitleSize = max(22.0, letterSize * 0.30)

            ZStack {
                // Black background that fades in along with the row —
                // panel itself is transparent so during the fade-in
                // the user's desktop dims toward black underneath.
                Color.black
                    .opacity(model.globalFadeIn)
                    .ignoresSafeArea()

                VStack(spacing: letterSize * 0.50) {
                    glyphRow(slotWidth: slotWidth, letterSize: letterSize)
                    creditsBlock(subtitleSize: subtitleSize, letterSize: letterSize)
                }
                .opacity(model.globalFadeIn)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(model.isExiting ? 0.0 : 1.0)
        }
        .task {
            await model.run()
        }
    }

    private func glyphRow(slotWidth: CGFloat, letterSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<model.glyphCount, id: \.self) { i in
                glyphCell(slot: i, slotWidth: slotWidth, letterSize: letterSize)
            }
        }
    }

    /// The text block below the locked "THANK YOU." A three-line
    /// credit: tier signoff (full brightness), name (slightly dimmer
    /// and smaller — the signature), and role (smaller still, dimmer
    /// — the credit). Everything fades in together once all anchors
    /// lock.
    private func creditsBlock(subtitleSize: CGFloat, letterSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(tier.signature)
                .font(.system(size: subtitleSize, weight: .medium, design: .monospaced))
                .foregroundStyle(matrixGreen)
                .shadow(color: matrixGreen.opacity(0.70), radius: 6)
                .shadow(color: matrixGreen.opacity(0.35), radius: 18)

            // Pause between the signoff and the signature so the eye
            // reads them as separate beats — one is "for you," the
            // other is "from me."
            Spacer().frame(height: letterSize * 0.35)

            Text("Wade Sellers")
                .font(.system(size: subtitleSize * 0.82, weight: .medium, design: .monospaced))
                .foregroundStyle(matrixGreen.opacity(0.88))
                .shadow(color: matrixGreen.opacity(0.55), radius: 4)
                .shadow(color: matrixGreen.opacity(0.25), radius: 14)

            Spacer().frame(height: letterSize * 0.08)

            Text("developer")
                .font(.system(size: subtitleSize * 0.55, weight: .regular, design: .monospaced))
                .foregroundStyle(matrixGreen.opacity(0.62))
                .shadow(color: matrixGreen.opacity(0.45), radius: 3)
                .shadow(color: matrixGreen.opacity(0.20), radius: 10)
        }
        .opacity(model.subtitleVisible ? 1.0 : 0.0)
    }

    private func glyphCell(slot i: Int, slotWidth: CGFloat, letterSize: CGFloat) -> some View {
        let glyph = model.currentGlyphs[i]
        let isPulsing = model.pulseFlags[i]
        let isLocked = model.lockedFlags[i]
        let cellOpacity = model.slotOpacities[i]

        // Pulse goes a touch beyond 1.0 (the "punch"); resting locked
        // state is 1.0. Scrambling state sits a hair smaller so the
        // lock-in pulse reads as a clear arrival.
        let scale: CGFloat = isPulsing ? 1.22 : (isLocked ? 1.0 : 0.97)
        let primaryGlow: CGFloat = isPulsing ? 14 : 6
        let secondaryGlow: CGFloat = isPulsing ? 36 : 18
        let outerGlow: CGFloat = isPulsing ? 64 : 32

        return Text(glyph)
            .font(.system(size: letterSize, weight: .bold, design: .monospaced))
            .foregroundStyle(isPulsing ? matrixGreenBright : matrixGreen)
            .frame(width: slotWidth, height: letterSize * 1.20)
            .scaleEffect(scale)
            .opacity(cellOpacity)
            .shadow(color: matrixGreen.opacity(0.95), radius: primaryGlow)
            .shadow(color: matrixGreen.opacity(0.55), radius: secondaryGlow)
            .shadow(color: matrixGreen.opacity(0.25), radius: outerGlow)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPulsing)
    }
}
