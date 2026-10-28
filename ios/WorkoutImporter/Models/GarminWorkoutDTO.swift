import Foundation

/// Raw mirror of the Garmin Connect workout export JSON schema.
struct GarminWorkoutDTO: Decodable {
    let workoutName: String
    let description: String?
    let sportType: GarminKeyed
    let workoutSegments: [GarminSegmentDTO]
}

struct GarminSegmentDTO: Decodable {
    let workoutSteps: [GarminStepDTO]
}

/// A single step in the workout tree. Garmin's JSON is polymorphic on "type":
/// "ExecutableStepDTO" (a leaf step) or "RepeatGroupDTO" (a repeated block of steps).
enum GarminStepDTO: Decodable {
    case executable(GarminExecutableStepDTO)
    case repeatGroup(GarminRepeatGroupDTO)

    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ExecutableStepDTO":
            self = .executable(try GarminExecutableStepDTO(from: decoder))
        case "RepeatGroupDTO":
            self = .repeatGroup(try GarminRepeatGroupDTO(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown workout step type: \(type)"
            )
        }
    }
}

struct GarminKeyed: Decodable {
    let key: String?

    private enum CodingKeys: String, CodingKey {
        case sportTypeKey, stepTypeKey, conditionTypeKey, workoutTargetTypeKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .sportTypeKey)
            ?? container.decodeIfPresent(String.self, forKey: .stepTypeKey)
            ?? container.decodeIfPresent(String.self, forKey: .conditionTypeKey)
            ?? container.decodeIfPresent(String.self, forKey: .workoutTargetTypeKey)
    }
}

struct GarminExecutableStepDTO: Decodable {
    let stepType: GarminKeyed
    let endCondition: GarminKeyed
    let endConditionValue: Double?
    let targetType: GarminKeyed
    /// Meters/second. For pace.zone targets, this is the SLOWER bound.
    let targetValueOne: Double?
    /// Meters/second. For pace.zone targets, this is the FASTER bound.
    let targetValueTwo: Double?
}

struct GarminRepeatGroupDTO: Decodable {
    let numberOfIterations: Int
    let workoutSteps: [GarminStepDTO]
    let skipLastRestStep: Bool?
}

enum GarminWorkoutLoader {
    static func load(from data: Data) throws -> GarminWorkoutDTO {
        try JSONDecoder().decode(GarminWorkoutDTO.self, from: data)
    }

    static func loadBundledSample() throws -> GarminWorkoutDTO {
        guard let url = Bundle.main.url(forResource: "SampleWorkout", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: Data(contentsOf: url))
    }
}
