import Foundation
import CryptoKit

/// RFC 7636 PKCE verifier/challenge pair (S256).
struct PKCE {
    let codeVerifier: String
    let codeChallenge: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        codeVerifier = Data(bytes).base64URLEncodedString()

        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        codeChallenge = Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    /// Base64url, no padding -- required by RFC 7636 (plain base64 with "+/="
    /// is rejected by strict PKCE servers, a pitfall Garmin's own forums call out).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
