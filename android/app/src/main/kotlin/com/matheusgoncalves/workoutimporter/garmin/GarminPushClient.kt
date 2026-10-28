package com.matheusgoncalves.workoutimporter.garmin

import android.content.Context
import com.matheusgoncalves.workoutimporter.model.InternalWorkout
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

sealed class GarminPushException(message: String) : Exception(message) {
    object AuthExpired : GarminPushException("Your Garmin connection expired. Reconnect and try again.")
    data class Rejected(val detail: String) : GarminPushException("Garmin rejected the workout: $detail")
    data class Transient(val detail: String) : GarminPushException("Garmin's server had a problem, try again: $detail")
}

/**
 * Pushes a workout to the Training API push endpoint, retrying once after a
 * token refresh on a 401. Mirrors GarminPushClient.swift.
 */
object GarminPushClient {
    suspend fun push(context: Context, workout: InternalWorkout) {
        val body = GarminPushMapper.map(workout).toString().toByteArray()
        try {
            send(body, GarminAuthClient.validAccessToken(context))
        } catch (e: GarminPushException.AuthExpired) {
            GarminAuthClient.refreshIfNeeded(context)
            send(body, GarminAuthClient.validAccessToken(context))
        }
    }

    private fun send(body: ByteArray, accessToken: String) {
        val connection = (URL(GarminConfig.pushUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $accessToken")
        }
        try {
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            when (status) {
                in 200..299 -> return
                401 -> throw GarminPushException.AuthExpired
                in 400..499 -> {
                    val detail = connection.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $status"
                    throw GarminPushException.Rejected(detail)
                }
                else -> throw GarminPushException.Transient("HTTP $status")
            }
        } catch (e: IOException) {
            throw GarminPushException.Transient(e.message ?: "network error")
        } finally {
            connection.disconnect()
        }
    }
}
