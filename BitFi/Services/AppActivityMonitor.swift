import AppKit
import Combine
import Foundation

/// Reports public process CPU and resident-memory data for visible app bundles.
@MainActor
final class AppActivityMonitor: NSObject, ObservableObject {
    @Published private(set) var appSlices: [AppActivitySlice] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?

    private var timer: Timer?
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: 30,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    func refresh() {
        let targets = applicationTargets()
        let monitor = self

        Task.detached(priority: .utility) {
            let result = Self.readActivity(for: targets)
            await MainActor.run {
                monitor.apply(result)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hasStarted = false
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    private func applicationTargets() -> [ApplicationTarget] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.processIdentifier > 0,
                  let bundleURL = application.bundleURL,
                  application.activationPolicy != .prohibited
            else {
                return nil
            }

            return ApplicationTarget(
                id: application.bundleIdentifier ?? bundleURL.path,
                name: application.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                bundlePath: bundleURL.path
            )
        }
        .sorted { $0.bundlePath.count > $1.bundlePath.count }
    }

    private func apply(_ result: ActivityReadResult) {
        appSlices = result.slices
        errorMessage = result.errorMessage
        if result.errorMessage == nil {
            lastUpdated = .now
        }
    }

    func slices(for measure: AppActivityMeasure) -> [AppActivitySlice] {
        let sorted = appSlices
            .filter { $0.value(for: measure) > 0 }
            .sorted { $0.value(for: measure) > $1.value(for: measure) }

        let visible = Array(sorted.prefix(5))
        let hidden = sorted.dropFirst(5)
        let otherCPU = hidden.reduce(0) { $0 + $1.cpuPercent }
        let otherMemory = hidden.reduce(Int64(0)) { $0 + $1.residentMemoryBytes }

        guard otherCPU > 0 || otherMemory > 0 else { return visible }
        return visible + [
            AppActivitySlice(
                id: "other",
                name: "Other",
                cpuPercent: otherCPU,
                residentMemoryBytes: otherMemory
            )
        ]
    }

    nonisolated private static func readActivity(for targets: [ApplicationTarget]) -> ActivityReadResult {
        guard !targets.isEmpty else { return ActivityReadResult(slices: [], errorMessage: nil) }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-Ao", "pcpu=,rss=,comm="]

            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return ActivityReadResult(slices: [], errorMessage: "macOS could not read current app activity.")
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(decoding: data, as: UTF8.self)
            var cpuByApplication = [String: Double]()
            var memoryByApplication = [String: Int64]()
            var namesByApplication = [String: String]()

            for line in outputText.split(whereSeparator: \.isNewline) {
                let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                guard parts.count == 3,
                      let cpuPercent = Double(parts[0]),
                      let residentMemoryKiB = Int64(parts[1])
                else {
                    continue
                }

                let command = String(parts[2])
                guard let target = targets.first(where: { command.hasPrefix($0.bundlePath) }) else { continue }
                cpuByApplication[target.id, default: 0] += cpuPercent
                memoryByApplication[target.id, default: 0] += residentMemoryKiB * 1_024
                namesByApplication[target.id] = target.name
            }

            let identifiers = Set(cpuByApplication.keys).union(memoryByApplication.keys)
            let slices = identifiers.map {
                AppActivitySlice(
                    id: $0,
                    name: namesByApplication[$0] ?? "Unknown",
                    cpuPercent: cpuByApplication[$0, default: 0],
                    residentMemoryBytes: memoryByApplication[$0, default: 0]
                )
            }

            return ActivityReadResult(slices: slices, errorMessage: nil)
        } catch {
            return ActivityReadResult(slices: [], errorMessage: "macOS could not start activity sampling.")
        }
    }
}

private struct ApplicationTarget: Sendable {
    let id: String
    let name: String
    let bundlePath: String
}

private struct ActivityReadResult: Sendable {
    let slices: [AppActivitySlice]
    let errorMessage: String?
}
