import Foundation

/// Endpoints and client identity for the Garmin Connect Developer "Training API".
///
/// Client ID/secret come from Info.plist, which xcodegen fills in from
/// `ios/Secrets.xcconfig` (gitignored, real values) at build time -- see
/// `Secrets.xcconfig.example` for the template. This keeps real credentials
/// out of source control even though the repo is public.
///
/// Endpoints per Garmin's official "OAuth2.0 PKCE Specification" doc (the
/// fuller version with sections on deregistration/permission notifications,
/// which also states the token exchange must happen from the app's backend,
/// not the device -- see GarminAuthClient's doc comment).
enum GarminConfig {
    static let baseURL = URL(string: "https://connect.garmin.com")!
    static let authBaseURL = URL(string: "https://diauth.garmin.com")!
    static let apiBaseURL = URL(string: "https://apis.garmin.com")!

    static let clientID: String = Bundle.main.object(forInfoDictionaryKey: "GarminClientID") as? String ?? ""
    static let clientSecret: String = Bundle.main.object(forInfoDictionaryKey: "GarminClientSecret") as? String ?? ""

    /// Garmin's developer portal requires an http(s) redirect URL, so this points
    /// at a small bridge page on GitHub Pages (docs/oauth-callback.html) that
    /// JS-redirects into the app via `redirectScheme`. ASWebAuthenticationSession
    /// still watches for `redirectScheme`, not this URL, so it ignores the bridge
    /// page's own https navigation and only resolves once the bridge redirects.
    static let redirectURI = "https://matheuspereirag.github.io/botatrabalho/oauth-callback.html"
    static let redirectScheme = "workoutimporter"

    static var authorizationURL: URL { baseURL.appendingPathComponent("oauth2Confirm") }
    static var tokenURL: URL { authBaseURL.appendingPathComponent("di-oauth2-service/oauth/token") }
    static var pushURL: URL { apiBaseURL.appendingPathComponent("training-api/workout") }
}
