package com.matheusgoncalves.workoutimporter.model

/** Normalized, platform-agnostic representation of a structured workout. */
data class InternalWorkout(
    val name: String,
    val description: String?,
    val steps: List<InternalStep>,
)

sealed class InternalStep {
    data class Single(val step: InternalExecutableStep) : InternalStep()
    data class RepeatGroup(val iterations: Int, val steps: List<InternalExecutableStep>) : InternalStep()
}

sealed class StepKind {
    object Warmup : StepKind()
    object Interval : StepKind()
    object Recovery : StepKind()
    object Cooldown : StepKind()
    data class Other(val raw: String) : StepKind()

    val displayName: String
        get() = when (this) {
            Warmup -> "Warmup"
            Interval -> "Interval"
            Recovery -> "Recovery"
            Cooldown -> "Cooldown"
            is Other -> raw.replaceFirstChar { it.uppercase() }
        }

    /** The Garmin stepTypeKey this kind maps back to, for push payloads. */
    val stepTypeKey: String
        get() = when (this) {
            Warmup -> "warmup"
            Interval -> "interval"
            Recovery -> "recovery"
            Cooldown -> "cooldown"
            is Other -> raw
        }
}

sealed class EndCondition {
    data class Time(val seconds: Double) : EndCondition()
    data class Distance(val meters: Double) : EndCondition()
    object Open : EndCondition()
}

sealed class StepTarget {
    data class PaceZone(val slowerMetersPerSecond: Double, val fasterMetersPerSecond: Double) : StepTarget()
    object Open : StepTarget()
    data class Unsupported(val rawType: String) : StepTarget()
}

data class InternalExecutableStep(
    val kind: StepKind,
    val endCondition: EndCondition,
    val target: StepTarget,
)

data class ImportWarning(val stepDescription: String, val message: String)

data class MappedWorkout(val workout: InternalWorkout, val warnings: List<ImportWarning>)

object InternalWorkoutMapper {
    fun map(dto: GarminWorkoutDto): MappedWorkout {
        val warnings = mutableListOf<ImportWarning>()
        val steps = dto.segments.flatMap { segment -> segment.steps.map { mapStep(it, warnings) } }
        return MappedWorkout(InternalWorkout(dto.workoutName, dto.description, steps), warnings)
    }

    private fun mapStep(step: GarminStepDto, warnings: MutableList<ImportWarning>): InternalStep = when (step) {
        is GarminStepDto.Executable -> InternalStep.Single(mapExecutable(step, warnings))
        is GarminStepDto.RepeatGroup -> {
            val inner = step.steps.mapNotNull { child ->
                when (child) {
                    is GarminStepDto.Executable -> mapExecutable(child, warnings)
                    is GarminStepDto.RepeatGroup -> {
                        warnings.add(
                            ImportWarning(
                                "Nested repeat group",
                                "Repeat groups inside repeat groups aren't supported yet and were skipped.",
                            )
                        )
                        null
                    }
                }
            }
            InternalStep.RepeatGroup(step.numberOfIterations, inner)
        }
    }

    private fun mapExecutable(exec: GarminStepDto.Executable, warnings: MutableList<ImportWarning>): InternalExecutableStep {
        val kind = when (exec.stepTypeKey) {
            "warmup" -> StepKind.Warmup
            "interval" -> StepKind.Interval
            "recovery" -> StepKind.Recovery
            "cooldown" -> StepKind.Cooldown
            else -> StepKind.Other(exec.stepTypeKey ?: "unknown")
        }

        val endCondition = when {
            exec.conditionTypeKey == "time" && exec.endConditionValue != null -> EndCondition.Time(exec.endConditionValue)
            exec.conditionTypeKey == "distance" && exec.endConditionValue != null -> EndCondition.Distance(exec.endConditionValue)
            else -> EndCondition.Open
        }

        val target = when (exec.targetTypeKey) {
            null, "no.target" -> StepTarget.Open
            "pace.zone" -> {
                val slower = exec.targetValueOne
                val faster = exec.targetValueTwo
                if (slower != null && faster != null && slower > 0 && faster > 0) {
                    StepTarget.PaceZone(slower, faster)
                } else {
                    StepTarget.Open
                }
            }
            else -> {
                warnings.add(
                    ImportWarning(
                        "${kind.displayName} step",
                        "Target type '${exec.targetTypeKey}' isn't supported yet; this step will be sent without a pace/HR target.",
                    )
                )
                StepTarget.Unsupported(exec.targetTypeKey)
            }
        }

        return InternalExecutableStep(kind, endCondition, target)
    }
}

object PaceFormat {
    /** Formats a speed in meters/second as "m:ss/km". */
    fun perKm(metersPerSecond: Double): String {
        if (metersPerSecond <= 0) return "-"
        val secPerKm = Math.round(1000.0 / metersPerSecond).toInt()
        return String.format("%d:%02d/km", secPerKm / 60, secPerKm % 60)
    }
}
