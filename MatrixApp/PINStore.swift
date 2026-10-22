import Foundation
import Security
import CommonCrypto

// MARK: - PIN record (pure, testable)

/// What we persist for the dismiss PIN: a salted, stretched hash plus
/// the PIN's length. Never the PIN itself.
///
/// Why PBKDF2 and not a single salted SHA-256: a 4–8 digit PIN has at
/// most 10^8 possibilities, so a plain hash falls to brute force in
/// seconds if the Keychain item ever leaks. 200k rounds of
/// HMAC-SHA256 makes each guess cost ~50ms on Apple Silicon — still
/// not *strong* (the keyspace is tiny), but it moves an offline
/// attack from "instant" to "an afternoon," which is the right
/// posture for what is explicitly a privacy curtain, not a lock.
///
/// The length is stored in the clear because the keypad has to draw
/// one slot per digit and auto-submit when the row fills. That leaks
/// at most one of five possible lengths — acceptable.
struct PINRecord: Codable, Equatable, Sendable {
    /// Bumped if the derivation ever changes, so old records can be
    /// recognized (and, if needed, migrated) instead of silently
    /// failing every verify.
    var version: Int
    var iterations: Int
    var length: Int
    var salt: Data
    var hash: Data

    static let currentVersion = 1
    static let defaultIterations = 200_000
    static let saltByteCount = 16
    static let hashByteCount = 32

    /// Build a fresh record for `pin` with a new random salt.
    /// Returns nil if `pin` isn't a valid 4–8 digit PIN or the system
    /// RNG fails (which in practice it doesn't).
    static func make(pin: String, iterations: Int = defaultIterations) -> PINRecord? {
        guard PINRules.isValid(pin), let salt = randomBytes(saltByteCount),
              let hash = PINHasher.derive(pin: pin, salt: salt, iterations: iterations) else {
            return nil
        }
        return PINRecord(
            version: currentVersion,
            iterations: iterations,
            length: pin.count,
            salt: salt,
            hash: hash
        )
    }

    /// Constant-time check of a candidate PIN against this record. A
    /// wrong-length candidate is rejected after doing the same amount
    /// of derivation work, so timing doesn't reveal the length either
    /// (belt-and-braces — the length is already visible on screen).
    func matches(_ candidate: String) -> Bool {
        guard version == Self.currentVersion,
              let derived = PINHasher.derive(pin: candidate, salt: salt, iterations: iterations) else {
            return false
        }
        return PINHasher.constantTimeEqual(derived, hash) && candidate.count == length
    }

    private static func randomBytes(_ count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return status == errSecSuccess ? Data(bytes) : nil
    }
}

/// Shape rules for a PIN. One place so the Settings sheet and the
/// lock screen can't disagree.
enum PINRules {
    static let minLength = 4
    static let maxLength = 8

    static func isValid(_ pin: String) -> Bool {
        (minLength...maxLength).contains(pin.count) && pin.allSatisfy(isDigit)
    }

    /// ASCII 0–9 only. `Character.isNumber` would also accept "٣" or
    /// "½", which a keypad can't produce and we don't want to hash.
    static func isDigit(_ c: Character) -> Bool {
        guard let ascii = c.asciiValue else { return false }
        return ascii >= 48 && ascii <= 57
    }
}

/// PBKDF2-HMAC-SHA256 via CommonCrypto (available in the sandbox,
/// no entitlement needed).
enum PINHasher {
    static func derive(pin: String, salt: Data, iterations: Int) -> Data? {
        let password = Array(pin.utf8)
        var derived = [UInt8](repeating: 0, count: PINRecord.hashByteCount)
        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            password.withUnsafeBufferPointer { passwordBuffer -> Int32 in
                passwordBuffer.baseAddress!.withMemoryRebound(to: Int8.self, capacity: password.count) { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr, password.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(clamping: iterations),
                        &derived, derived.count
                    )
                }
            }
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    /// Compare without short-circuiting, so the time taken doesn't
    /// depend on how many leading bytes match.
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}

// MARK: - Attempt policy (pure, testable)

/// Wrong-guess throttling for the lock screen. The first
/// `freeAttempts` misses cost nothing; every miss after that starts a
/// cooldown that doubles from `baseCooldown` up to `maxCooldown`.
///
/// 5 free → 30s → 60s → 120s → 240s → 300s, 300s, …
///
/// Kept in memory only. The counter resets whenever someone proves
/// they're the owner (right PIN, Touch ID/password, or the Mac's own
/// screen lock), and the app can't be quit while locked, so there's no
/// restart loophole worth persisting against.
struct PINAttemptPolicy: Equatable, Sendable {
    static let freeAttempts = 5
    static let baseCooldown: TimeInterval = 30
    static let maxCooldown: TimeInterval = 300

    private(set) var failures: Int = 0
    private(set) var lockedUntil: Date?

    /// Cooldown that applies after the `failureCount`-th consecutive
    /// miss. Zero while still inside the free attempts.
    static func cooldown(afterFailures failureCount: Int) -> TimeInterval {
        guard failureCount >= freeAttempts else { return 0 }
        let doublings = failureCount - freeAttempts
        // Cap the exponent before pow so a long run of misses can't
        // overflow into inf.
        let raw = baseCooldown * pow(2, Double(min(doublings, 16)))
        return min(raw, maxCooldown)
    }

    /// Seconds left before input is accepted again (0 = accepting).
    func remainingCooldown(now: Date = Date()) -> TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSince(now))
    }

    func isCoolingDown(now: Date = Date()) -> Bool {
        remainingCooldown(now: now) > 0
    }

    /// Record a miss. Returns the cooldown it started (0 if none).
    @discardableResult
    mutating func recordFailure(now: Date = Date()) -> TimeInterval {
        failures += 1
        let wait = Self.cooldown(afterFailures: failures)
        lockedUntil = wait > 0 ? now.addingTimeInterval(wait) : nil
        return wait
    }

    mutating func reset() {
        failures = 0
        lockedUntil = nil
    }
}

// MARK: - Keychain storage

/// Reads and writes the `PINRecord` as a generic-password Keychain
/// item. Works inside the App Sandbox with no extra entitlement: a
/// sandboxed app can always create and read its own generic-password
/// items in the login keychain.
///
/// The "PIN enabled" switch lives in UserDefaults (`AppSettings`), but
/// the Keychain item is the source of truth for whether there *is* a
/// PIN — "enabled but no item" is treated as disabled everywhere, so a
/// wiped or migrated Keychain can never lock the user behind a PIN
/// that no longer exists.
enum PINStore {
    private static let service = "com.wadesellers.cipherfall.pin-lock"
    private static let account = "dismiss-pin"

    enum StoreError: Error {
        case invalidPIN
        case keychain(OSStatus)
    }

    /// The stored record, or nil if none / unreadable.
    static func loadRecord() -> PINRecord? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PINRecord.self, from: data)
    }

    static var hasPIN: Bool { loadRecord() != nil }

    /// Hash and store `pin`, replacing any existing PIN.
    static func save(pin: String) throws {
        guard let record = PINRecord.make(pin: pin) else { throw StoreError.invalidPIN }
        let data = try JSONEncoder().encode(record)

        // Update-or-add rather than delete-then-add, so a failure
        // halfway never leaves the user with *no* PIN while the
        // "enabled" switch still says on.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Falling Code PIN"
            add[kSecAttrDescription as String] = "Salted hash of the PIN that dismisses Falling Code"
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    /// Check `pin` against the stored record. ~50ms of PBKDF2 work —
    /// call off the main thread where it matters.
    static func verify(_ pin: String) -> Bool {
        loadRecord()?.matches(pin) ?? false
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
