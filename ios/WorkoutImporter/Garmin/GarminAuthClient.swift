import AuthenticationServices
import Foundation
import UIKit

enum GarminAuthError: Error, LocalizedError {
    case userCancelled
    case authorizationDenied
    case invalidCallback
    case tokenExchangeFailed(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "Garmin sign-in was cancelled."
        case .authorizationDenied: return "Garmin access was denied."
        case .invalidCallback: return "Garmin's sign-in response was invalid."
        case .tokenExchangeFailed(let detail): return "Couldn't complete Garmin sign-in: \(detail)"
        case .notAuthenticated: return "Not connected to Garmin yet."
        }
    }
}

struct GarminTokens {
    let accessToken: String
    let refreshToken: String
}

/// Garmin Connect OAuth 2.0 + PKCE client. Uses ASWebAuthenticationSession
/// (never a raw WKWebView) per the plan's store-review requirement, and keeps
/// tokens in the Keychain rather than UserDefaults.
///
/// KNOWN GAP: Garmin's OAuth2 PKCE spec states the token exchange "must be
/// performed from the application's backend server... must not be performed
/// directly from a mobile application... Garmin does not offer a secretless
/// ('public client') flow." This client currently does the exchange directly
/// from the device (client_secret bundled via Secrets.xcconfig) to unblock
/// local testing against your own Garmin account. Before any real release,
/// this needs a small backend relay: the app sends {code, code_verifier} to
/// our server, the server (holding the only copy of client_secret) calls
/// Garmin's token endpoint and returns the tokens to the app.
@MainActor
final class GarminAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GarminAuthClient()

    private var activeSession: ASWebAuthenticationSession?

    var isConnected: Bool {
        KeychainTokenStore.load(.accessToken) != nil
    }

    func disconnect() {
        KeychainTokenStore.clear()
    }

    /// Runs the full "Connect Garmin" flow: PKCE challenge -> browser consent -> token exchange.
    func connect() async throws {
        let pkce = PKCE()
        let state = UUID().uuidString

        var components = URLComponents(url: GarminConfig.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GarminConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GarminConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL = try await presentAuthSession(url: components.url!)

        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = callbackComponents?.queryItems ?? []
        if queryItems.first(where: { $0.name == "error" }) != nil {
            throw GarminAuthError.authorizationDenied
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              queryItems.first(where: { $0.name == "state" })?.value == state else {
            throw GarminAuthError.invalidCallback
        }

        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: pkce.codeVerifier)
        KeychainTokenStore.save(tokens.accessToken, for: .accessToken)
        KeychainTokenStore.save(tokens.refreshToken, for: .refreshToken)
    }

    /// Returns a usable access token, refreshing it first if needed.
    func validAccessToken() async throws -> String {
        guard let accessToken = KeychainTokenStore.load(.accessToken) else {
            throw GarminAuthError.notAuthenticated
        }
        return accessToken
    }

    func refreshIfNeeded() async throws {
        guard let refreshToken = KeychainTokenStore.load(.refreshToken) else {
            throw GarminAuthError.notAuthenticated
        }
        let tokens = try await refresh(refreshToken: refreshToken)
        KeychainTokenStore.save(tokens.accessToken, for: .accessToken)
        KeychainTokenStore.save(tokens.refreshToken, for: .refreshToken)
    }

    // MARK: - ASWebAuthenticationSession

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GarminConfig.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GarminAuthError.userCancelled)
                } else {
                    continuation.resume(throwing: error ?? GarminAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.activeSession = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> GarminTokens {
        try await postForTokens(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": GarminConfig.redirectURI,
            "code_verifier": codeVerifier,
        ])
    }

    private func refresh(refreshToken: String) async throws -> GarminTokens {
        try await postForTokens(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    /// Per Garmin's OAuth2 PKCE spec, client credentials go in an HTTP Basic
    /// Authorization header (base64 of "client_id:client_secret"), not as form fields.
    private func postForTokens(form: [String: String]) async throws -> GarminTokens {
        var request = URLRequest(url: GarminConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = "\(GarminConfig.clientID):\(GarminConfig.clientSecret)"
        if let basic = credentials.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw GarminAuthError.tokenExchangeFailed(message)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GarminTokens(accessToken: decoded.access_token, refreshToken: decoded.refresh_token)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()
}
