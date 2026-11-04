import Combine
import Foundation

/// Durable local charge samples. Records survive app quits, restart, and computer shutdown.
@MainActor
final class BatteryHistoryStore: ObservableObject {
    @Published private(set) var records: [BatteryHistoryRecord] = []
    @Published private(set) var persistenceError: String?

    private let fileManager: FileManager
    private let fileURL: URL
    private var cancellable: AnyCancellable?
    private var hasStarted = false

    private let minimumSampleInterval: TimeInterval = 10 * 60
    private let retentionInterval: TimeInterval = 90 * 24 * 60 * 60
    private let maximumRecordCount = 20_000

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = applicationSupport.appendingPathComponent("BitFi", isDirectory: true)
        fileURL = directory.appendingPathComponent("battery-history.json")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            persistenceError = "Unable to create local history storage."
        }

        load()
    }

    func start(monitor: BatteryMonitor) {
        guard !hasStarted else { return }
        hasStarted = true

        cancellable = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.record(snapshot)
            }
    }

    func records(in range: BatteryHistoryRange, now: Date = .now) -> [BatteryHistoryRecord] {
        let earliestDate = now.addingTimeInterval(-range.duration)
        return records.filter { $0.recordedAt >= earliestDate }
    }

    func segments(in range: BatteryHistoryRange, now: Date = .now) -> [BatteryHistorySegment] {
        let filteredRecords = records(in: range, now: now)
        guard !filteredRecords.isEmpty else { return [] }

        var segments: [BatteryHistorySegment] = []
        var currentSegment: [BatteryHistoryRecord] = []
        var segmentID = 0
        let gapThreshold: TimeInterval = 15 * 60

        for record in filteredRecords {
            if let previous = currentSegment.last,
               record.recordedAt.timeIntervalSince(previous.recordedAt) > gapThreshold {
                segments.append(BatteryHistorySegment(id: segmentID, records: currentSegment))
                segmentID += 1
                currentSegment = []
            }
            currentSegment.append(record)
        }

        if !currentSegment.isEmpty {
            segments.append(BatteryHistorySegment(id: segmentID, records: currentSegment))
        }
        return segments
    }

    private func record(_ snapshot: BatterySnapshot) {
        guard snapshot.isAvailable, snapshot.percentage != nil else { return }
        let record = BatteryHistoryRecord(snapshot: snapshot)
        guard shouldStore(record) else { return }

        records.append(record)
        prune()
        save()
    }

    private func shouldStore(_ candidate: BatteryHistoryRecord) -> Bool {
        guard let previous = records.last else { return true }
        if candidate.percentage != previous.percentage ||
            candidate.isCharging != previous.isCharging ||
            candidate.isConnectedToPower != previous.isConnectedToPower {
            return true
        }
        return candidate.recordedAt.timeIntervalSince(previous.recordedAt) >= minimumSampleInterval
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([BatteryHistoryRecord].self, from: data)
                .sorted { $0.recordedAt < $1.recordedAt }
            prune()
        } catch {
            persistenceError = "Unable to read saved battery history."
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Unable to save battery history."
        }
    }

    private func prune(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        records.removeAll { $0.recordedAt < cutoff }
        if records.count > maximumRecordCount {
            records.removeFirst(records.count - maximumRecordCount)
        }
    }
}
