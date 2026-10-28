import Foundation

/// Maps InternalWorkout to the Training API push payload. The real payload
/// shape is gated behind Garmin's developer-program approval (see plan risk
/// #2), so this mirrors the publicly-visible Connect export schema -- the
/// strongest available proxy -- and is expected to need adjustment once real
/// API access lands.
enum GarminPushMapper {
    static func map(_ workout: InternalWorkout) -> [String: Any] {
        [
            "workoutName": workout.name,
            "description": workout.description as Any,
            "sportType": ["sportTypeKey": "running"],
            "workoutSegments": [[
                "workoutSteps": workout.steps.map(mapStep),
            ]],
        ]
    }

    private static func mapStep(_ step: InternalStep) -> [String: Any] {
        switch step {
        case .single(let exec):
            var payload = mapExecutable(exec)
            payload["type"] = "ExecutableStepDTO"
            return payload
        case .repeatGroup(let iterations, let steps):
            return [
                "type": "RepeatGroupDTO",
                "numberOfIterations": iterations,
                "workoutSteps": steps.map { exec -> [String: Any] in
                    var payload = mapExecutable(exec)
                    payload["type"] = "ExecutableStepDTO"
                    return payload
                },
            ]
        }
    }

    private static func mapExecutable(_ exec: InternalExecutableStep) -> [String: Any] {
        var payload: [String: Any] = [
            "stepType": ["stepTypeKey": stepTypeKey(exec.kind)],
        ]

        switch exec.endCondition {
        case .time(let seconds):
            payload["endCondition"] = ["conditionTypeKey": "time"]
            payload["endConditionValue"] = seconds
        case .distance(let meters):
            payload["endCondition"] = ["conditionTypeKey": "distance"]
            payload["endConditionValue"] = meters
        case .open:
            payload["endCondition"] = ["conditionTypeKey": "lap.button"]
        }

        switch exec.target {
        case .paceZone(let slower, let faster):
            payload["targetType"] = ["workoutTargetTypeKey": "pace.zone"]
            payload["targetValueOne"] = slower
            payload["targetValueTwo"] = faster
        case .open, .unsupported:
            payload["targetType"] = ["workoutTargetTypeKey": "no.target"]
        }

        return payload
    }

    private static func stepTypeKey(_ kind: InternalExecutableStep.Kind) -> String {
        switch kind {
        case .warmup: return "warmup"
        case .interval: return "interval"
        case .recovery: return "recovery"
        case .cooldown: return "cooldown"
        case .other(let raw): return raw
        }
    }
}
