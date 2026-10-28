package com.matheusgoncalves.workoutimporter.garmin

/**
 * Endpoints and client identity for the Garmin Connect Developer "Training API".
 *
 * Points at the local mock server (mock-server/garmin_mock_server.py) by
 * default, mirroring the iOS app's GarminConfig.swift -- see that file's doc
 * comment for why. 10.0.2.2 is the Android emulator's alias for the host
 * machine's loopback address; on a physical device this must be the host's
 * LAN IP instead.
 */
object GarminConfig {
    const val BASE_URL = "http://10.0.2.2:8899"
    const val CLIENT_ID = "mock-client-id"
    /** Garmin requires an http(s) redirect URL; see GarminConfig.swift's doc comment
     *  for why this points at a GitHub Pages bridge page instead of the app scheme. */
    const val REDIRECT_URI = "https://matheuspereirag.github.io/botatrabalho/oauth-callback.html"

    val authorizationUrl get() = "$BASE_URL/oauth2Confirm"
    val tokenUrl get() = "$BASE_URL/di-oauth2-service/oauth/token"
    val pushUrl get() = "$BASE_URL/workout"
}
