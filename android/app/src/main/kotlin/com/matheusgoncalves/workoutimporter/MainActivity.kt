package com.matheusgoncalves.workoutimporter

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.matheusgoncalves.workoutimporter.garmin.GarminAuthClient
import com.matheusgoncalves.workoutimporter.garmin.GarminPushClient
import com.matheusgoncalves.workoutimporter.model.GarminWorkoutParser
import com.matheusgoncalves.workoutimporter.model.ImportWarning
import com.matheusgoncalves.workoutimporter.model.InternalWorkout
import com.matheusgoncalves.workoutimporter.model.InternalWorkoutMapper
import com.matheusgoncalves.workoutimporter.ui.WorkoutImportScreen
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var workout by mutableStateOf<InternalWorkout?>(null)
    private var warnings by mutableStateOf<List<ImportWarning>>(emptyList())
    private var statusMessage by mutableStateOf<String?>(null)
    private var isGarminConnected by mutableStateOf(false)
    private var isBusy by mutableStateOf(false)

    private val filePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) loadFile(uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        isGarminConnected = GarminAuthClient.isConnected(this)
        loadSample()

        setContent {
            WorkoutImportScreen(
                workout = workout,
                warnings = warnings,
                statusMessage = statusMessage,
                isGarminConnected = isGarminConnected,
                isBusy = isBusy,
                onImportFile = { filePicker.launch("application/json") },
                onConnectGarmin = ::connectGarmin,
                onDisconnectGarmin = ::disconnectGarmin,
                onSendToGarmin = ::sendToGarmin,
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let { uri -> if (uri.scheme == "workoutimporter") GarminAuthClient.handleRedirect(uri) }
    }

    private fun loadSample() {
        try {
            val json = assets.open("sample_workout.json").bufferedReader().use { it.readText() }
            apply(json)
        } catch (e: Exception) {
            statusMessage = "Couldn't load sample workout: ${e.message}"
        }
    }

    private fun loadFile(uri: Uri) {
        statusMessage = null
        try {
            val json = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: throw IllegalStateException("couldn't open file")
            apply(json)
        } catch (e: Exception) {
            statusMessage = "Couldn't import file: ${e.message}"
        }
    }

    private fun apply(json: String) {
        val dto = GarminWorkoutParser.parse(json)
        val mapped = InternalWorkoutMapper.map(dto)
        workout = mapped.workout
        warnings = mapped.warnings
    }

    private fun connectGarmin() {
        isBusy = true
        statusMessage = null
        lifecycleScope.launch {
            try {
                GarminAuthClient.connect(this@MainActivity)
                isGarminConnected = true
                statusMessage = "Connected to Garmin."
            } catch (e: Exception) {
                statusMessage = "Couldn't connect to Garmin: ${e.message}"
            }
            isBusy = false
        }
    }

    private fun disconnectGarmin() {
        GarminAuthClient.disconnect(this)
        isGarminConnected = false
        statusMessage = "Disconnected from Garmin."
    }

    private fun sendToGarmin() {
        val current = workout ?: return
        isBusy = true
        statusMessage = null
        lifecycleScope.launch {
            try {
                GarminPushClient.push(this@MainActivity, current)
                statusMessage = "Sent to Garmin Connect. It'll sync to your device shortly."
            } catch (e: Exception) {
                statusMessage = "Couldn't send to Garmin: ${e.message}"
            }
            isBusy = false
        }
    }
}
