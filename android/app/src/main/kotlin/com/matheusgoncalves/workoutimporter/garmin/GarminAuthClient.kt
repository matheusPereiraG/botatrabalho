package com.matheusgoncalves.workoutimporter.garmin

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import kotlinx.coroutines.CompletableDeferred
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import org.json.JSONObject

sealed class GarminAuthException(message: String) : Exception(message) {
    object UserCancelled : GarminAuthException("Garmin sign-in was cancelled.")
    object AuthorizationDenied : GarminAuthException("Garmin access was denied.")
    object InvalidCallback : GarminAuthException("Garmin's sign-in response was invalid.")
    object NotAuthenticated : GarminAuthException("Not connected to Garmin yet.")
    data class TokenExchangeFailed(val detail: String) : GarminAuthException("Couldn't complete Garmin sign-in: $detail")
}

private data class GarminTokens(val accessToken: String, val refreshToken: String)

/**
 * Garmin Connect OAuth 2.0 + PKCE client. Uses Chrome Custom Tabs (never a
 * raw WebView) per the plan's store-review requirement, and keeps tokens in
 * Android Keystore-backed EncryptedSharedPreferences rather than plain
 * SharedPreferences. Mirrors ios/WorkoutImporter/Garmin/GarminAuthClient.swift.
 *
 * The OAuth redirect comes back into MainActivity (singleTask, intent-filter
 * on workoutimporter://oauth-callback); MainActivity.onNewIntent forwards it
 * here via [handleRedirect].
 *
 * Known gap: if the user closes the Custom Tab without completing consent,
 * [connect] never resolves (no "user closed the tab" signal is wired up
 * yet) -- detecting that needs an ActivityResult/lifecycle observer, left
 * for a follow-up pass.
 */
object GarminAuthClient {
    private var pendingState: String? = null
    private var pendingCallback: CompletableDeferred<Uri>? = null

    fun isConnected(context: Context): Boolean = EncryptedTokenStore(context).accessToken != null

    fun disconnect(context: Context) = EncryptedTokenStore(context).clear()

    /** Runs the full "Connect Garmin" flow: PKCE challenge -> browser consent -> token exchange. */
    suspend fun connect(context: Context) {
        val pkce = Pkce()
        val state = java.util.UUID.randomUUID().toString()
        pendingState = state

        val authUrl = Uri.parse(GarminConfig.authorizationUrl).buildUpon()
            .appendQueryParameter("client_id", GarminConfig.CLIENT_ID)
            .appendQueryParameter("redirect_uri", GarminConfig.REDIRECT_URI)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("state", state)
            .appendQueryParameter("code_challenge", pkce.codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()

        val callbackUri = awaitRedirect(context, authUrl)

        if (callbackUri.getQueryParameter("error") != null) {
            throw GarminAuthException.AuthorizationDenied
        }
        val code = callbackUri.getQueryParameter("code")
        val returnedState = callbackUri.getQueryParameter("state")
        if (code == null || returnedState != state) {
            throw GarminAuthException.InvalidCallback
        }

        val tokens = exchangeCodeForTokens(code, pkce.codeVerifier)
        val store = EncryptedTokenStore(context)
        store.accessToken = tokens.accessToken
        store.refreshToken = tokens.refreshToken
    }

    fun validAccessToken(context: Context): String =
        EncryptedTokenStore(context).accessToken ?: throw GarminAuthException.NotAuthenticated

    suspend fun refreshIfNeeded(context: Context) {
        val store = EncryptedTokenStore(context)
        val refreshToken = store.refreshToken ?: throw GarminAuthException.NotAuthenticated
        val tokens = refresh(refreshToken)
        store.accessToken = tokens.accessToken
        store.refreshToken = tokens.refreshToken
    }

    /** Called from MainActivity.onNewIntent when the OAuth redirect comes back in. */
    fun handleRedirect(uri: Uri) {
        pendingCallback?.complete(uri)
    }

    private suspend fun awaitRedirect(context: Context, authUrl: Uri): Uri {
        val deferred = CompletableDeferred<Uri>()
        pendingCallback = deferred
        CustomTabsIntent.Builder().build().launchUrl(context, authUrl)
        try {
            return deferred.await()
        } finally {
            pendingCallback = null
        }
    }

    private fun exchangeCodeForTokens(code: String, codeVerifier: String): GarminTokens = postForTokens(
        mapOf(
            "grant_type" to "authorization_code",
            "code" to code,
            "redirect_uri" to GarminConfig.REDIRECT_URI,
            "client_id" to GarminConfig.CLIENT_ID,
            "code_verifier" to codeVerifier,
        )
    )

    private fun refresh(refreshToken: String): GarminTokens = postForTokens(
        mapOf(
            "grant_type" to "refresh_token",
            "refresh_token" to refreshToken,
            "client_id" to GarminConfig.CLIENT_ID,
        )
    )

    private fun postForTokens(form: Map<String, String>): GarminTokens {
        val body = form.entries.joinToString("&") { (key, value) ->
            "$key=${URLEncoder.encode(value, "UTF-8")}"
        }
        val connection = (URL(GarminConfig.tokenUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        }
        try {
            connection.outputStream.use { it.write(body.toByteArray()) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val responseText = stream.bufferedReader().use { it.readText() }
            if (status !in 200..299) {
                throw GarminAuthException.TokenExchangeFailed(responseText)
            }
            val json = JSONObject(responseText)
            return GarminTokens(json.getString("access_token"), json.getString("refresh_token"))
        } catch (e: IOException) {
            throw GarminAuthException.TokenExchangeFailed(e.message ?: "network error")
        } finally {
            connection.disconnect()
        }
    }
}
