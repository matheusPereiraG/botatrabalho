import Foundation

/// Normalized, platform-agnostic representation of a structured workout.
/// Produced from GarminWorkoutDTO; consumed by the WorkoutKit mapper.
struct InternalWorkout {
    let name: String
    let description: String?
    let steps: [InternalStep]
}

indirect enum InternalStep {
    case single(InternalExecutableStep)
    case repeatGroup(iterations: Int, steps: [InternalExecutableStep])
}

struct InternalExecutableStep {
    enum Kind { case warmup, interval, recovery, cooldown, other(String) }
    enum EndCondition {
        case time(seconds: Double)
        case distance(meters: Double)
        case open
    }
    enum Target {
        /// Slower/faster speed bound, in meters per second (as Garmin provides it).
        case paceZone(slowerMetersPerSecond: Double, fasterMetersPerSecond: Double)
        case open
        /// A target type present in the source JSON with no internal mapping yet.
        case unsupported(String)
    }

    let kind: Kind
    let endCondition: EndCondition
    let target: Target
}

/// A warning surfaced to the user when a step couldn't be fully represented.
struct ImportWarning {
    let stepDescription: String
    let message: String
}

enum InternalWorkoutMapper {
    static func map(_ dto: GarminWorkoutDTO) -> (workout: InternalWorkout, warnings: [ImportWarning]) {
        var warnings: [ImportWarning] = []
        let steps = dto.workoutSegments.flatMap { segment in
            segment.workoutSteps.map { mapStep($0, warnings: &warnings) }
        }
        let workout = InternalWorkout(name: dto.workoutName, description: dto.description, steps: steps)
        return (workout, warnings)
    }

    private static func mapStep(_ step: GarminStepDTO, warnings: inout [ImportWarning]) -> InternalStep {
        switch step {
        case .executable(let exec):
            return .single(mapExecutable(exec, warnings: &warnings))
        case .repeatGroup(let group):
            let inner: [InternalExecutableStep] = group.workoutSteps.compactMap { child in
                switch child {
                case .executable(let exec):
                    return mapExecutable(exec, warnings: &warnings)
                case .repeatGroup:
                    warnings.append(ImportWarning(
                        stepDescription: "Nested repeat group",
                        message: "Repeat groups inside repeat groups aren't supported yet and were skipped."
                    ))
                    return nil
                }
            }
            return .repeatGroup(iterations: group.numberOfIterations, steps: inner)
        }
    }

    private static func mapExecutable(_ exec: GarminExecutableStepDTO, warnings: inout [ImportWarning]) -> InternalExecutableStep {
        let kind: InternalExecutableStep.Kind
        switch exec.stepType.key {
        case "warmup": kind = .warmup
        case "interval": kind = .interval
        case "recovery": kind = .recovery
        case "cooldown": kind = .cooldown
        case .some(let other): kind = .other(other)
        case .none: kind = .other("unknown")
        }

        let endCondition: InternalExecutableStep.EndCondition
        switch (exec.endCondition.key, exec.endConditionValue) {
        case ("time", .some(let seconds)):
            endCondition = .time(seconds: seconds)
        case ("distance", .some(let meters)):
            endCondition = .distance(meters: meters)
        default:
            endCondition = .open
        }

        let target: InternalExecutableStep.Target
        switch exec.targetType.key {
        case "no.target", .none:
            target = .open
        case "pace.zone":
            if let slowerMps = exec.targetValueOne, let fasterMps = exec.targetValueTwo, slowerMps > 0, fasterMps > 0 {
                target = .paceZone(slowerMetersPerSecond: slowerMps, fasterMetersPerSecond: fasterMps)
            } else {
                target = .open
            }
        case .some(let other):
            target = .unsupported(other)
            warnings.append(ImportWarning(
                stepDescription: "\(kind) step",
                message: "Target type '\(other)' isn't supported yet; this step will be sent without a pace/HR target."
            ))
        }

        return InternalExecutableStep(kind: kind, endCondition: endCondition, target: target)
    }
}

enum PaceFormat {
    /// Formats a speed in meters/second as "m:ss/km".
    static func perKm(metersPerSecond: Double) -> String {
        guard metersPerSecond > 0 else { return "-" }
        let secPerKm = Int((1000.0 / metersPerSecond).rounded())
        return String(format: "%d:%02d/km", secPerKm / 60, secPerKm % 60)
    }
}

extension InternalExecutableStep.Kind: CustomStringConvertible {
    var description: String {
        switch self {
        case .warmup: return "Warmup"
        case .interval: return "Interval"
        case .recovery: return "Recovery"
        case .cooldown: return "Cooldown"
        case .other(let raw): return raw.capitalized
        }
    }
}
