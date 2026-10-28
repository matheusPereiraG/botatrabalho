import Foundation

/// Endpoints and client identity for the Garmin Connect Developer "Training API".
///
/// Points at the local mock server (mock-server/garmin_mock_server.py) by default,
/// since the real Training API's exact payload schema is gated behind Garmin's
/// developer-program approval (see the plan's Phase 0/2 notes). Once a real
/// client ID and API access are granted, swap `baseURL` and `clientID` for the
/// production values -- the OAuth PKCE flow and push client are written against
/// the publicly documented shape and shouldn't need structural changes.
enum GarminConfig {
    /// The mock server's address as seen from the iOS Simulator (shares the host's
    /// network namespace). On a physical device this must be the host machine's
    /// LAN IP instead of 127.0.0.1.
    static let baseURL = URL(string: "http://127.0.0.1:8899")!

    static let clientID = "mock-client-id"
    /// Garmin's developer portal requires an http(s) redirect URL, so this points
    /// at a small bridge page on GitHub Pages (docs/oauth-callback.html) that
    /// JS-redirects into the app via `redirectScheme`. ASWebAuthenticationSession
    /// still watches for `redirectScheme`, not this URL, so it ignores the bridge
    /// page's own https navigation and only resolves once the bridge redirects.
    static let redirectURI = "https://matheuspereirag.github.io/botatrabalho/oauth-callback.html"
    static let redirectScheme = "workoutimporter"

    static var authorizationURL: URL { baseURL.appendingPathComponent("oauth2Confirm") }
    static var tokenURL: URL { baseURL.appendingPathComponent("di-oauth2-service/oauth/token") }
    static var pushURL: URL { baseURL.appendingPathComponent("workout") }
}
