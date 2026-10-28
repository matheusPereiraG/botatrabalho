package com.matheusgoncalves.workoutimporter.garmin

import com.matheusgoncalves.workoutimporter.model.EndCondition
import com.matheusgoncalves.workoutimporter.model.InternalExecutableStep
import com.matheusgoncalves.workoutimporter.model.InternalStep
import com.matheusgoncalves.workoutimporter.model.InternalWorkout
import com.matheusgoncalves.workoutimporter.model.StepTarget
import org.json.JSONArray
import org.json.JSONObject

/**
 * Maps InternalWorkout to the Training API push payload. Mirrors
 * ios/WorkoutImporter/Garmin/GarminPushMapper.swift -- see that file's doc
 * comment for why this is a best-effort proxy of the real (gated) schema.
 */
object GarminPushMapper {
    fun map(workout: InternalWorkout): JSONObject = JSONObject().apply {
        put("workoutName", workout.name)
        put("description", workout.description)
        put("sportType", JSONObject().put("sportTypeKey", "running"))
        put(
            "workoutSegments",
            JSONArray().put(
                JSONObject().put("workoutSteps", JSONArray(workout.steps.map(::mapStep)))
            ),
        )
    }

    private fun mapStep(step: InternalStep): JSONObject = when (step) {
        is InternalStep.Single -> mapExecutable(step.step).put("type", "ExecutableStepDTO")
        is InternalStep.RepeatGroup -> JSONObject().apply {
            put("type", "RepeatGroupDTO")
            put("numberOfIterations", step.iterations)
            put("workoutSteps", JSONArray(step.steps.map { mapExecutable(it).put("type", "ExecutableStepDTO") }))
        }
    }

    private fun mapExecutable(exec: InternalExecutableStep): JSONObject {
        val payload = JSONObject()
        payload.put("stepType", JSONObject().put("stepTypeKey", exec.kind.stepTypeKey))

        when (val condition = exec.endCondition) {
            is EndCondition.Time -> {
                payload.put("endCondition", JSONObject().put("conditionTypeKey", "time"))
                payload.put("endConditionValue", condition.seconds)
            }
            is EndCondition.Distance -> {
                payload.put("endCondition", JSONObject().put("conditionTypeKey", "distance"))
                payload.put("endConditionValue", condition.meters)
            }
            EndCondition.Open -> payload.put("endCondition", JSONObject().put("conditionTypeKey", "lap.button"))
        }

        when (val target = exec.target) {
            is StepTarget.PaceZone -> {
                payload.put("targetType", JSONObject().put("workoutTargetTypeKey", "pace.zone"))
                payload.put("targetValueOne", target.slowerMetersPerSecond)
                payload.put("targetValueTwo", target.fasterMetersPerSecond)
            }
            StepTarget.Open, is StepTarget.Unsupported ->
                payload.put("targetType", JSONObject().put("workoutTargetTypeKey", "no.target"))
        }

        return payload
    }
}
