import Foundation
import HealthKit
import WorkoutKit

/// Maps the normalized InternalWorkout into a WorkoutKit CustomWorkout/WorkoutPlan.
/// Targets WorkoutKit can't represent are degraded to an open goal, with a warning
/// recorded rather than silently dropped (per the degrade-and-warn product decision).
enum WorkoutKitMapper {
    static func map(_ workout: InternalWorkout) -> (plan: WorkoutPlan, warnings: [ImportWarning]) {
        var warnings: [ImportWarning] = []

        var warmupStep: WorkoutStep?
        var cooldownStep: WorkoutStep?
        var blocks: [IntervalBlock] = []

        for step in workout.steps {
            switch step {
            case .single(let exec):
                let workoutStep = mapWorkoutStep(exec, warnings: &warnings)
                switch exec.kind {
                case .warmup:
                    warmupStep = workoutStep
                case .cooldown:
                    cooldownStep = workoutStep
                default:
                    // A bare (non-repeated) interval/recovery step: wrap as a single-iteration block.
                    blocks.append(IntervalBlock(steps: [IntervalStep(.work, step: workoutStep)], iterations: 1))
                }
            case .repeatGroup(let iterations, let steps):
                let intervalSteps: [IntervalStep] = steps.map { exec in
                    let purpose: IntervalStep.Purpose = (exec.kind == .recovery) ? .recovery : .work
                    return IntervalStep(purpose, step: mapWorkoutStep(exec, warnings: &warnings))
                }
                blocks.append(IntervalBlock(steps: intervalSteps, iterations: iterations))
            }
        }

        let customWorkout = CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: workout.name,
            warmup: warmupStep,
            blocks: blocks,
            cooldown: cooldownStep
        )
        return (WorkoutPlan(.custom(customWorkout)), warnings)
    }

    private static func mapWorkoutStep(_ exec: InternalExecutableStep, warnings: inout [ImportWarning]) -> WorkoutStep {
        let goal: WorkoutGoal
        switch exec.endCondition {
        case .time(let seconds):
            goal = .time(seconds, .seconds)
        case .distance(let meters):
            goal = .distance(meters, .meters)
        case .open:
            goal = .open
        }

        let alert: (any WorkoutAlert)?
        switch exec.target {
        case .paceZone(let slower, let faster):
            let lower = Measurement(value: min(slower, faster), unit: UnitSpeed.metersPerSecond)
            let upper = Measurement(value: max(slower, faster), unit: UnitSpeed.metersPerSecond)
            alert = SpeedRangeAlert(target: lower...upper, metric: .current)
        case .open:
            alert = nil
        case .unsupported(let type):
            alert = nil
            warnings.append(ImportWarning(
                stepDescription: "\(exec.kind) step",
                message: "Target type '\(type)' isn't supported by Apple Watch workouts; sent without a target."
            ))
        }

        return WorkoutStep(goal: goal, alert: alert)
    }
}

extension InternalExecutableStep.Kind: Equatable {
    static func == (lhs: InternalExecutableStep.Kind, rhs: InternalExecutableStep.Kind) -> Bool {
        switch (lhs, rhs) {
        case (.warmup, .warmup), (.interval, .interval), (.recovery, .recovery), (.cooldown, .cooldown):
            return true
        case (.other(let a), .other(let b)):
            return a == b
        default:
            return false
        }
    }
}
