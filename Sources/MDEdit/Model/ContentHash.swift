import Foundation
import CryptoKit

/// A fingerprint of some text: any change to the text changes it.
enum ContentHash {
    /// SHA-256 of the UTF-8 bytes, as lowercase hex.
    static func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}
