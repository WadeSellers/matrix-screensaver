import SwiftUI
import StoreKit

/// "Support development" tab in Preferences. Three tip-tier cards (coffee
/// $2.99, lunch $9.99, awesome $19.99) wired to `TipJarManager`. Each tap
/// triggers Apple's native purchase sheet. After a successful purchase the
/// tapped card cross-fades to a "Thank you ❤️" state for ~2 seconds.
///
/// Visual language pulled from `OnboardingSheet.swift`: rounded cards with
/// subtle white strokes, signature near-trail green on accent text, plain
/// button style with focus ring disabled so the cards don't accumulate a
/// macOS keyboard-focus visual.
struct SupportView: View {
    @Bindable var tipJar: TipJarManager

    /// Signature near-trail green from MatrixTheme.classic. Used for tier
    /// names + price text so the tip jar reads as part of the Matrix
    /// visual identity.
    private let accentGreen = Color(red: 0.40, green: 0.95, blue: 0.55)

    var body: some View {
        VStack(spacing: 14) {
            header

            // "Meet the maker" — the merged About surface. Lives above
            // the tip cards so the flow is meet → understand → tip.
            // Bumped here from the old `NSApp.orderFrontStandardAboutPanel`
            // approach which couldn't lead into a purchase.
            MakerCard()

            if tipJar.isLoadingProducts {
                loadingState
            } else if tipJar.products.isEmpty {
                errorState
            } else {
                cardRow
            }

            if let err = tipJar.lastError, !tipJar.isLoadingProducts {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .animation(.easeInOut(duration: 0.2), value: tipJar.purchaseInFlightID)
        .animation(.easeInOut(duration: 0.25), value: tipJar.lastThankYouTier)
        .animation(.easeInOut(duration: 0.2), value: tipJar.lastError)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Support Development")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("If you enjoy Falling Code, consider leaving a tip. It helps keep the app maintained and improving.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - Cards row

    private var cardRow: some View {
        HStack(spacing: 12) {
            ForEach(tipJar.products.indices, id: \.self) { idx in
                tipCard(
                    for: tipJar.products[idx],
                    emoji: emoji(forIndex: idx)
                )
            }
        }
    }

    /// Map ordered product index → emoji. Matches the visual reference:
    /// coffee, slice of pizza, heart.
    private func emoji(forIndex i: Int) -> String {
        switch i {
        case 0: return "☕"
        case 1: return "🍕"
        case 2: return "❤️"
        default: return "🎁"
        }
    }

    private func tipCard(for product: Product, emoji: String) -> some View {
        let isThankYou = tipJar.lastThankYouTier == product.id
        let isInFlight = tipJar.purchaseInFlightID == product.id
        let isDisabled = tipJar.purchaseInFlightID != nil && !isInFlight

        return Button(action: {
            Task { await tipJar.purchase(product) }
        }) {
            ZStack {
                if isThankYou {
                    thankYouContent
                } else {
                    cardContent(emoji: emoji, product: product, isInFlight: isInFlight)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(isDisabled || isInFlight)
    }

    private func cardContent(emoji: String, product: Product, isInFlight: Bool) -> some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 28))
            Text(product.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(product.displayPrice)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(accentGreen)
        }
        .opacity(isInFlight ? 0.0 : 1.0)
        .overlay(
            Group {
                if isInFlight {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        )
    }

    private var thankYouContent: some View {
        VStack(spacing: 6) {
            Text("❤️")
                .font(.system(size: 28))
            Text("Thank you")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentGreen)
        }
    }

    // MARK: - Loading / error states

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 130)
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            Text("Couldn't load tip options.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Try again") {
                tipJar.reloadProducts()
            }
            .controlSize(.small)
        }
        .frame(height: 130)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Tips are one-time, processed by the App Store. No data is sent to anyone except Apple.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Maker card (the merged About surface)

/// A small card with the maker's name, version + copyright meta-row,
/// and a short personal note. Visually a sibling of the three tip
/// cards below (same rounded-rect / stroke / fill recipe) so the
/// section reads as part of the same "support development" composition.
///
/// External links (GitHub / website / email) and a feedback / bug-
/// report entry point are intentionally deferred — they're planned as
/// a follow-up feature.
private struct MakerCard: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Meta row: name · version · copyright. Small, secondary,
            // sets the "credits" beat before the bio.
            HStack(spacing: 6) {
                Text("Wade Sellers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("v\(appVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !copyright.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(copyright)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            // Bio. TODO(Wade): replace this with your own copy whenever
            // you're ready — three sentences is the target length so
            // the card sits comfortably between header and tip cards.
            Text("Hi, I'm Wade. I built Falling Code as a love letter to the 1999 film that first made me think “computers can be art.” If it brings you a moment of nostalgia (or just looks great behind your icons), that's already enough for me — a tip is simply gratitude on top.")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
