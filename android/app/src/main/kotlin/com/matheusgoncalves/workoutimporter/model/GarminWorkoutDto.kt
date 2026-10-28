package com.matheusgoncalves.workoutimporter.model

import org.json.JSONArray
import org.json.JSONObject

/** Raw mirror of the Garmin Connect workout export JSON schema. */
data class GarminWorkoutDto(
    val workoutName: String,
    val description: String?,
    val segments: List<GarminSegmentDto>,
)

data class GarminSegmentDto(val steps: List<GarminStepDto>)

/** Polymorphic on "type": "ExecutableStepDTO" (a leaf step) or "RepeatGroupDTO". */
sealed class GarminStepDto {
    data class Executable(
        val stepTypeKey: String?,
        val conditionTypeKey: String?,
        val endConditionValue: Double?,
        val targetTypeKey: String?,
        /** Meters/second. For pace.zone targets, the SLOWER bound. */
        val targetValueOne: Double?,
        /** Meters/second. For pace.zone targets, the FASTER bound. */
        val targetValueTwo: Double?,
    ) : GarminStepDto()

    data class RepeatGroup(
        val numberOfIterations: Int,
        val steps: List<GarminStepDto>,
    ) : GarminStepDto()
}

class GarminWorkoutParseException(message: String) : Exception(message)

object GarminWorkoutParser {
    fun parse(json: String): GarminWorkoutDto {
        val root = JSONObject(json)
        val segments = root.getJSONArray("workoutSegments").toObjectList().map { segment ->
            GarminSegmentDto(steps = segment.getJSONArray("workoutSteps").toObjectList().map(::parseStep))
        }
        return GarminWorkoutDto(
            workoutName = root.getString("workoutName"),
            description = root.optStringOrNull("description"),
            segments = segments,
        )
    }

    private fun parseStep(obj: JSONObject): GarminStepDto {
        return when (val type = obj.optString("type")) {
            "ExecutableStepDTO" -> GarminStepDto.Executable(
                stepTypeKey = obj.optJSONObject("stepType")?.optStringOrNull("stepTypeKey"),
                conditionTypeKey = obj.optJSONObject("endCondition")?.optStringOrNull("conditionTypeKey"),
                endConditionValue = obj.optDoubleOrNull("endConditionValue"),
                targetTypeKey = obj.optJSONObject("targetType")?.optStringOrNull("workoutTargetTypeKey"),
                targetValueOne = obj.optDoubleOrNull("targetValueOne"),
                targetValueTwo = obj.optDoubleOrNull("targetValueTwo"),
            )
            "RepeatGroupDTO" -> GarminStepDto.RepeatGroup(
                numberOfIterations = obj.optInt("numberOfIterations"),
                steps = obj.getJSONArray("workoutSteps").toObjectList().map(::parseStep),
            )
            else -> throw GarminWorkoutParseException("Unknown workout step type: $type")
        }
    }
}

private fun JSONArray.toObjectList(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

private fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

private fun JSONObject.optDoubleOrNull(key: String): Double? = if (has(key) && !isNull(key)) getDouble(key) else null
