import Foundation

enum GarminPushError: Error, LocalizedError {
    case authExpired
    case rejected(String)
    case transient(String)

    var errorDescription: String? {
        switch self {
        case .authExpired: return "Your Garmin connection expired. Reconnect and try again."
        case .rejected(let detail): return "Garmin rejected the workout: \(detail)"
        case .transient(let detail): return "Garmin's server had a problem, try again: \(detail)"
        }
    }
}

/// Pushes a workout to the Training API push endpoint, retrying once after a
/// token refresh on a 401 (per the plan's auth-expired vs payload-rejected
/// vs transient error-handling distinction).
enum GarminPushClient {
    static func push(_ workout: InternalWorkout) async throws {
        let payload = GarminPushMapper.map(workout)
        let body = try JSONSerialization.data(withJSONObject: payload)

        do {
            try await send(body: body, accessToken: try await GarminAuthClient.shared.validAccessToken())
        } catch GarminPushError.authExpired {
            try await GarminAuthClient.shared.refreshIfNeeded()
            try await send(body: body, accessToken: try await GarminAuthClient.shared.validAccessToken())
        }
    }

    private static func send(body: Data, accessToken: String) async throws {
        var request = URLRequest(url: GarminConfig.pushURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GarminPushError.transient("no HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw GarminPushError.authExpired
        case 400..<500:
            throw GarminPushError.rejected(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        default:
            throw GarminPushError.transient("HTTP \(http.statusCode)")
        }
    }
}
