import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkoutImportViewModel: ObservableObject {
    @Published var workout: InternalWorkout?
    @Published var warnings: [ImportWarning] = []
    @Published var statusMessage: String?
    @Published var isSending = false

    func loadSample() {
        do {
            let dto = try GarminWorkoutLoader.loadBundledSample()
            apply(dto)
        } catch {
            statusMessage = "Couldn't load sample workout: \(error.localizedDescription)"
        }
    }

    func loadFile(at url: URL) {
        statusMessage = nil
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let dto = try GarminWorkoutLoader.load(from: data)
            apply(dto)
        } catch {
            statusMessage = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func apply(_ dto: GarminWorkoutDTO) {
        let (workout, warnings) = InternalWorkoutMapper.map(dto)
        self.workout = workout
        self.warnings = warnings
    }

    func sendToAppleWatch() {
        guard let workout else { return }
        isSending = true
        statusMessage = nil
        Task {
            let (plan, mapWarnings) = WorkoutKitMapper.map(workout)
            warnings = (warnings + mapWarnings).uniqued()
            do {
                try await WorkoutScheduling.scheduleNow(plan)
                statusMessage = "Sent! Open the Workout app on your Apple Watch to start it."
            } catch {
                statusMessage = "Couldn't send to Apple Watch: \(error.localizedDescription)"
            }
            isSending = false
        }
    }
}

private extension Array where Element == ImportWarning {
    func uniqued() -> [ImportWarning] {
        var seen = Set<String>()
        return filter { seen.insert($0.stepDescription + $0.message).inserted }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = WorkoutImportViewModel()
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                if let workout = viewModel.workout {
                    Section(workout.name) {
                        if let description = workout.description {
                            Text(description).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Array(workout.steps.enumerated()), id: \.offset) { _, step in
                            StepRow(step: step)
                        }
                    }

                    if !viewModel.warnings.isEmpty {
                        Section("Warnings") {
                            ForEach(Array(viewModel.warnings.enumerated()), id: \.offset) { _, warning in
                                Text("\(warning.stepDescription): \(warning.message)")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Section {
                        Button {
                            viewModel.sendToAppleWatch()
                        } label: {
                            if viewModel.isSending {
                                ProgressView()
                            } else {
                                Text("Send to Apple Watch")
                            }
                        }
                        .disabled(viewModel.isSending)
                    }

                    if let status = viewModel.statusMessage {
                        Section {
                            Text(status).font(.footnote)
                        }
                    }
                } else {
                    ProgressView("Loading workout…")
                }
            }
            .navigationTitle("Workout Importer")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import…") { isImporterPresented = true }
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    viewModel.loadFile(at: url)
                case .failure(let error):
                    viewModel.statusMessage = "Import cancelled: \(error.localizedDescription)"
                }
            }
            .onAppear { viewModel.loadSample() }
        }
    }
}

private struct StepRow: View {
    let step: InternalStep

    var body: some View {
        switch step {
        case .single(let exec):
            StepDetail(exec: exec)
        case .repeatGroup(let iterations, let steps):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(iterations)x").font(.headline)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, exec in
                    StepDetail(exec: exec).padding(.leading, 12)
                }
            }
        }
    }
}

private struct StepDetail: View {
    let exec: InternalExecutableStep

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exec.kind.description).font(.subheadline.weight(.medium))
            Text(endConditionText + targetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var endConditionText: String {
        switch exec.endCondition {
        case .time(let seconds): return "\(Int(seconds / 60)) min"
        case .distance(let meters): return "\(Int(meters)) m"
        case .open: return "Open"
        }
    }

    private var targetText: String {
        switch exec.target {
        case .paceZone(let slower, let faster):
            return " · \(PaceFormat.perKm(metersPerSecond: faster))–\(PaceFormat.perKm(metersPerSecond: slower))"
        case .open, .unsupported:
            return ""
        }
    }
}

#Preview {
    ContentView()
}
