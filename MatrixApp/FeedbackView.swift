import SwiftUI

/// The "Send Feedback" form. Two top-level branches driven by the
/// manager's `state`:
///
/// - `.idle / .submitting / .failure` → the form is visible (with
///    an inline error in the failure case, and a spinner overlay
///    in the submitting case).
/// - `.success` → the form is replaced by a success-state takeover
///    showing the GitHub issue number Apple-style.
///
/// Visual language mirrors the existing tip-card / Maker-card recipe
/// in SupportView (`Color.white.opacity(0.06)` fill, `0.15` stroke,
/// rounded 12) so the floating window feels native to the rest of
/// the app.
struct FeedbackView: View {
    @Bindable var manager: FeedbackManager
    let onClose: () -> Void

    /// Signature Matrix near-trail green, used by every other accent
    /// in the app. Submit button, segment selection, success checkmark.
    private let matrixGreen = Color(red: 0.40, green: 0.95, blue: 0.55)

    var body: some View {
        ZStack {
            // Dark background — matches the popover / settings vibe so
            // the window has the same "live in the Matrix" feel.
            Color.black.opacity(0.92).ignoresSafeArea()

            switch manager.state {
            case .success(let issueNumber, let url):
                successView(issueNumber: issueNumber, url: url)
                    .transition(.opacity)
            default:
                formView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stateID(manager.state))
        .frame(minWidth: 460, idealWidth: 480, maxWidth: 540,
               minHeight: 540, idealHeight: 600, maxHeight: 720)
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                kindToggle

                fieldSection(label: "TITLE") {
                    TextField("Brief summary of your feedback", text: $manager.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(fieldBackground)
                }

                fieldSection(
                    label: "DESCRIPTION",
                    trailing: "\(manager.description.count) / \(FeedbackManager.descriptionCharLimit)"
                ) {
                    TextEditor(text: $manager.description)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(6)
                        .background(fieldBackground)
                        .overlay(alignment: .topLeading) {
                            if manager.description.isEmpty {
                                Text("Please describe your feedback in detail…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                fieldSection(label: "EMAIL", trailing: "Optional") {
                    TextField("email@example.com", text: $manager.email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(fieldBackground)
                    Text("So we can reach out for more details")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                deviceInfoNote

                if case .failure(let message) = manager.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                submitButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("🪲")
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(matrixGreen.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(matrixGreen.opacity(0.40), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Send Feedback")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Text(manager.kind == .bug
                     ? "Report an issue you've encountered"
                     : "Share an idea for the next update")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var kindToggle: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackKind.allCases) { k in
                kindButton(k)
            }
        }
    }

    private func kindButton(_ k: FeedbackKind) -> some View {
        let selected = manager.kind == k
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                manager.kind = k
            }
        } label: {
            HStack(spacing: 8) {
                Text(k.emoji).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(k.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                    Text(k.subtitle)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.black.opacity(0.65) : Color.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? matrixGreen : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func fieldSection<Content: View>(
        label: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var deviceInfoNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Device information will be automatically included")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var submitButton: some View {
        Button {
            Task { await manager.submit() }
        } label: {
            HStack(spacing: 8) {
                if case .submitting = manager.state {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.black)
                    Text("Sending…")
                } else {
                    Text("Submit Feedback")
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(manager.canSubmit ? matrixGreen : matrixGreen.opacity(0.35))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!manager.canSubmit)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Success state

    private func successView(issueNumber: Int, url: String) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(matrixGreen.opacity(0.18))
                    .frame(width: 120, height: 120)
                Circle()
                    .stroke(matrixGreen.opacity(0.45), lineWidth: 2)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(matrixGreen)
                    .shadow(color: matrixGreen.opacity(0.7), radius: 8)
            }

            VStack(spacing: 8) {
                Text("Feedback Sent")
                    .font(.system(size: 22, weight: .bold))
                Text("Thank you! Your feedback helps improve the app.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            // Issue number chip — click to open the issue in browser.
            Button {
                if let issueURL = URL(string: url) {
                    NSWorkspace.shared.open(issueURL)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("Issue #\(issueNumber)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Spacer(minLength: 0)

            Button(action: onClose) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(matrixGreen)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 22)
    }

    // MARK: - State identity for animation

    /// `FeedbackSubmissionState` isn't `Equatable` (the associated
    /// values would force the user-facing type to grow), so we use a
    /// stable token for `.animation(value:)`.
    private func stateID(_ s: FeedbackSubmissionState) -> Int {
        switch s {
        case .idle:        return 0
        case .submitting:  return 1
        case .success:     return 2
        case .failure:     return 3
        }
    }
}
