import Foundation
import os.log

private let log = OSLog(subsystem: "com.wadesellers.cipherfall", category: "feedback")

/// Per-submission category. Maps to GitHub Issue labels on the Worker
/// side: `bug` for `.bug`, `enhancement` for `.feature`.
enum FeedbackKind: String, CaseIterable, Identifiable, Sendable {
    case bug
    case feature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug:     return "Bug"
        case .feature: return "Feature"
        }
    }

    var subtitle: String {
        switch self {
        case .bug:     return "Something isn't working"
        case .feature: return "Idea or improvement"
        }
    }

    var emoji: String {
        switch self {
        case .bug:     return "🪲"
        case .feature: return "✨"
        }
    }
}

/// State of the current feedback submission. Drives the FeedbackView's
/// branching: form is visible in `.idle` / `.submitting` / `.failure`,
/// success-state takeover replaces it in `.success`.
enum FeedbackSubmissionState: Sendable {
    case idle
    case submitting
    case success(issueNumber: Int, url: String)
    case failure(String)
}

/// Owns the form state and the submit flow. Hosted by
/// `FeedbackController` and bound to by `FeedbackView`. One instance per
/// presentation — reset each time the user opens the window.
@MainActor
@Observable
final class FeedbackManager {
    // MARK: - Configuration

    /// The Cloudflare Worker endpoint that receives feedback and
    /// creates a GitHub Issue on our behalf. `/submit` is the only
    /// route the Worker accepts.
    static let workerURL: String = "https://falling-code-feedback.wadesellers.workers.dev/submit"

    /// Shared secret the Worker checks via `X-App-Secret` header.
    /// Visible in this public repo by design — same secret would be
    /// extractable from the compiled app binary, so the repo doesn't
    /// leak anything that determined inspection wouldn't already
    /// surface. Real spam defense lives on the Worker side (payload
    /// validation, length caps, Cloudflare rate limiting + bot
    /// detection). If this ever gets abused, rotate it via
    /// `wrangler secret put APP_SECRET` and update the constant here.
    static let appSecret: String = "61bd8ddacc6cf5571b5102e2990cea1b0cee34101b146aadd89534a0fff27258"

    // MARK: - Form state (bindable by SwiftUI)

    var kind: FeedbackKind = .bug
    var title: String = ""
    var description: String = ""
    var email: String = ""

    /// Where the submission currently stands. View reads this to
    /// decide what to render.
    var state: FeedbackSubmissionState = .idle

    // MARK: - Constants

    static let titleCharLimit = 200
    static let descriptionCharLimit = 1000  // UI limit; Worker accepts up to 5000

    // MARK: - Computed

    var canSubmit: Bool {
        guard case .idle = state else {
            if case .failure = state { return validateLocally() }
            return false
        }
        return validateLocally()
    }

    private func validateLocally() -> Bool {
        let titleOK = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= Self.titleCharLimit
        let descOK = !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && description.count <= Self.descriptionCharLimit
        return titleOK && descOK
    }

    // MARK: - Submission

    func submit() async {
        guard canSubmit else { return }
        state = .submitting

        // Bail early if the Worker URL hasn't been configured yet
        // (i.e. before first deploy). Surfaces a clear message in dev
        // instead of a network error from a bogus URL.
        guard let url = URL(string: Self.workerURL),
              !Self.workerURL.isEmpty else {
            os_log("Worker URL not configured — submission stubbed",
                   log: log, type: .error)
            state = .failure("Feedback isn't wired up yet. The Worker URL is missing.")
            return
        }

        let payload = SubmissionPayload(
            kind: kind.rawValue,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : email.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceInfo: Self.collectDeviceInfo()
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.appSecret, forHTTPHeaderField: "X-App-Secret")
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            os_log("payload encode failed: %{public}@",
                   log: log, type: .error, String(describing: error))
            state = .failure("Couldn't encode the form. Try again.")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failure("Unexpected server response.")
                return
            }

            if http.statusCode == 200 {
                let decoded = try JSONDecoder().decode(SuccessResponse.self, from: data)
                os_log("submission OK: issue #%{public}d",
                       log: log, type: .info, decoded.issueNumber)
                state = .success(issueNumber: decoded.issueNumber, url: decoded.url)
            } else {
                let err = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                    ?? "Server returned status \(http.statusCode)."
                os_log("submission failed: %{public}@",
                       log: log, type: .error, err)
                state = .failure(err)
            }
        } catch {
            os_log("submission threw: %{public}@",
                   log: log, type: .error, String(describing: error))
            state = .failure("Couldn't reach the server. Check your network and try again.")
        }
    }

    // MARK: - Device info

    /// Builds a minimal device-info payload included with every
    /// submission. App version + build, macOS version, locale. No
    /// hardware model, no user identifiers — keeps the privacy story
    /// clean (everything here is non-identifying).
    private static func collectDeviceInfo() -> DeviceInfo {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier
        return DeviceInfo(
            appVersion: appVersion,
            appBuild: appBuild,
            osVersion: osVersion,
            locale: locale
        )
    }
}

// MARK: - Wire types

private struct SubmissionPayload: Encodable {
    let kind: String
    let title: String
    let description: String
    let email: String?
    let deviceInfo: DeviceInfo
}

private struct DeviceInfo: Encodable {
    let appVersion: String?
    let appBuild: String?
    let osVersion: String?
    let locale: String?
}

private struct SuccessResponse: Decodable {
    let issueNumber: Int
    let url: String
}

private struct ErrorResponse: Decodable {
    let error: String
}
