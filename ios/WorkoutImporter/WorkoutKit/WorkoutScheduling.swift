import Foundation
import WorkoutKit

enum SchedulingError: Error, LocalizedError {
    case notAuthorized
    case notSupported

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "WorkoutKit access wasn't granted. Enable it in Settings to send workouts to Apple Watch."
        case .notSupported: return "Scheduled workouts aren't supported on this device."
        }
    }
}

/// Thin wrapper around WorkoutScheduler. Schedules for "right now" (today's date
/// components) so the workout shows up ready to start in the Watch's Workout app,
/// since WorkoutScheduler only exposes date-based scheduling, not an explicit
/// "start immediately" call (see plan risk #3).
enum WorkoutScheduling {
    static func scheduleNow(_ plan: WorkoutPlan) async throws {
        guard WorkoutScheduler.isSupported else { throw SchedulingError.notSupported }

        let state = await WorkoutScheduler.shared.requestAuthorization()
        guard state == .authorized else { throw SchedulingError.notAuthorized }

        let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        await WorkoutScheduler.shared.schedule(plan, at: now)
    }
}
