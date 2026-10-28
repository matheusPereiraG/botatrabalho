package com.matheusgoncalves.workoutimporter.garmin

import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom

/** RFC 7636 PKCE verifier/challenge pair (S256). */
class Pkce {
    val codeVerifier: String
    val codeChallenge: String

    init {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        codeVerifier = bytes.base64UrlNoPad()

        val digest = MessageDigest.getInstance("SHA-256").digest(codeVerifier.toByteArray(Charsets.US_ASCII))
        codeChallenge = digest.base64UrlNoPad()
    }
}

private fun ByteArray.base64UrlNoPad(): String =
    Base64.encodeToString(this, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
