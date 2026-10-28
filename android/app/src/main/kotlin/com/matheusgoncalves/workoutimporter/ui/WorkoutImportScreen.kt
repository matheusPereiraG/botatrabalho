package com.matheusgoncalves.workoutimporter.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.matheusgoncalves.workoutimporter.model.EndCondition
import com.matheusgoncalves.workoutimporter.model.ImportWarning
import com.matheusgoncalves.workoutimporter.model.InternalExecutableStep
import com.matheusgoncalves.workoutimporter.model.InternalStep
import com.matheusgoncalves.workoutimporter.model.InternalWorkout
import com.matheusgoncalves.workoutimporter.model.PaceFormat
import com.matheusgoncalves.workoutimporter.model.StepTarget

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkoutImportScreen(
    workout: InternalWorkout?,
    warnings: List<ImportWarning>,
    statusMessage: String?,
    isGarminConnected: Boolean,
    isBusy: Boolean,
    onImportFile: () -> Unit,
    onConnectGarmin: () -> Unit,
    onDisconnectGarmin: () -> Unit,
    onSendToGarmin: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Workout Importer") },
                actions = { TextButton(onClick = onImportFile) { Text("Import…") } },
            )
        }
    ) { padding ->
        if (workout == null) {
            Column(
                modifier = Modifier.padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        LazyColumn(modifier = Modifier.padding(padding).padding(16.dp)) {
            item {
                Text(workout.name, style = MaterialTheme.typography.headlineSmall)
                workout.description?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
                }
            }
            items(workout.steps) { step -> StepRow(step); Divider() }

            if (warnings.isNotEmpty()) {
                item { Text("Warnings", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp)) }
                items(warnings) { warning ->
                    Text("${warning.stepDescription}: ${warning.message}", style = MaterialTheme.typography.bodySmall)
                }
            }

            item {
                Column(modifier = Modifier.padding(top = 16.dp)) {
                    if (isGarminConnected) {
                        Button(onClick = onSendToGarmin, enabled = !isBusy) { Text(if (isBusy) "Sending…" else "Send to Garmin") }
                        TextButton(onClick = onDisconnectGarmin) { Text("Disconnect Garmin") }
                    } else {
                        Button(onClick = onConnectGarmin, enabled = !isBusy) { Text(if (isBusy) "Connecting…" else "Connect Garmin") }
                    }
                }
            }

            statusMessage?.let { message ->
                item { Text(message, modifier = Modifier.padding(top = 16.dp)) }
            }
        }
    }
}

@Composable
private fun StepRow(step: InternalStep) {
    when (step) {
        is InternalStep.Single -> StepDetail(step.step)
        is InternalStep.RepeatGroup -> Column {
            Text("${step.iterations}x", style = MaterialTheme.typography.titleMedium)
            step.steps.forEach { StepDetail(it, indent = 12.dp) }
        }
    }
}

@Composable
private fun StepDetail(exec: InternalExecutableStep, indent: androidx.compose.ui.unit.Dp = 0.dp) {
    Column(modifier = Modifier.padding(start = indent, top = 4.dp, bottom = 4.dp)) {
        Text(exec.kind.displayName, style = MaterialTheme.typography.bodyLarge)
        Text(endConditionText(exec) + targetText(exec), style = MaterialTheme.typography.bodySmall)
    }
}

private fun endConditionText(exec: InternalExecutableStep): String = when (val c = exec.endCondition) {
    is EndCondition.Time -> "${(c.seconds / 60).toInt()} min"
    is EndCondition.Distance -> "${c.meters.toInt()} m"
    EndCondition.Open -> "Open"
}

private fun targetText(exec: InternalExecutableStep): String = when (val t = exec.target) {
    is StepTarget.PaceZone -> " · ${PaceFormat.perKm(t.fasterMetersPerSecond)}–${PaceFormat.perKm(t.slowerMetersPerSecond)}"
    else -> ""
}
