import Foundation
import CryptoKit

/// CUIDv2 generator — collision-resistant, URL-safe, sorted-friendly unique IDs.
///
/// Produces lowercase IDs like "pfh0haxfpzowht3oi213cqos" that:
/// - Always start with a letter (a-z)
/// - Contain only [a-z0-9]
/// - Default to 24 characters
/// - Use SHA-256 hashing of entropy (timestamp, counter, random, fingerprint)
enum CUID2 {
    /// Monotonic counter to add uniqueness within the same millisecond.
    private static var counter: UInt64 = {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
        } % 2_147_483_647  // Keep counter in reasonable range
    }()

    private static let counterLock = NSLock()

    /// Base-36 alphabet: 0-9a-z
    private static let base36 = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// Generate a CUIDv2 string.
    ///
    /// - Parameter length: Desired length (default 24, minimum 2).
    /// - Returns: A CUIDv2 string starting with a letter, containing only [a-z0-9].
    static func generate(length: Int = 24) -> String {
        let len = max(length, 2)

        // Gather entropy sources
        let time = "\(UInt64(Date().timeIntervalSince1970 * 1000))"

        counterLock.lock()
        counter &+= 1
        let count = "\(counter)"
        counterLock.unlock()

        // 32 bytes of cryptographic randomness
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let salt = randomBytes.map { String(format: "%02x", $0) }.joined()

        // Machine fingerprint (stable per process)
        let fingerprint = ProcessInfo.processInfo.processIdentifier.description
            + ProcessInfo.processInfo.hostName

        // Combine and hash
        let entropy = time + salt + count + fingerprint
        let hash = SHA256.hash(data: Data(entropy.utf8))

        // Convert hash bytes to base-36
        let hashBytes = Array(hash)
        var chars: [Character] = []
        for byte in hashBytes {
            chars.append(base36[Int(byte) % 36])
        }

        // Ensure first character is a letter (a-z)
        let letterIndex = Int(hashBytes[0]) % 26 + 10  // index 10-35 → 'a'-'z'
        chars[0] = base36[letterIndex]

        // Truncate or pad to desired length
        if chars.count >= len {
            return String(chars.prefix(len))
        }

        // Pad with additional random base-36 chars if needed (unlikely with SHA-256)
        while chars.count < len {
            var extra: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &extra)
            chars.append(base36[Int(extra) % 36])
        }

        return String(chars.prefix(len))
    }
}
