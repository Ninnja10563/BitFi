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
    private var chartCache: ChartCache?

    private let minimumSampleInterval: TimeInterval = 10 * 60
    private let retentionInterval: TimeInterval = 2 * 365 * 24 * 60 * 60
    private let maximumRecordCount = 150_000

    private struct ChartCache {
        let startDate: Date
        let endDate: Date
        let maximumPointCount: Int
        let segments: [BatteryHistorySegment]
    }

    var earliestRecordedAt: Date? { records.first?.recordedAt }
    var latestRecordedAt: Date? { records.last?.recordedAt }

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
        let earliestDate = range.visibleDuration.map { now.addingTimeInterval(-$0) }
            ?? earliestRecordedAt
            ?? now
        return records(from: earliestDate, through: now)
    }

    func segments(in range: BatteryHistoryRange, now: Date = .now) -> [BatteryHistorySegment] {
        let earliestDate = range.visibleDuration.map { now.addingTimeInterval(-$0) }
            ?? earliestRecordedAt
            ?? now
        return segments(from: earliestDate, through: now)
    }

    func records(from startDate: Date, through endDate: Date) -> [BatteryHistoryRecord] {
        guard let recordRange = recordRange(from: startDate, through: endDate) else { return [] }
        return Array(records[recordRange])
    }

    func window(from startDate: Date, through endDate: Date) -> BatteryHistoryWindow {
        guard let recordRange = recordRange(from: startDate, through: endDate),
              let first = records[recordRange].first,
              let last = records[recordRange].last
        else {
            return .empty
        }
        return BatteryHistoryWindow(count: recordRange.count, first: first, last: last)
    }

    func segments(from startDate: Date, through endDate: Date) -> [BatteryHistorySegment] {
        let filteredRecords = records(from: startDate, through: endDate)
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

    func chartSegments(
        from startDate: Date,
        through endDate: Date,
        maximumPointCount: Int = 900
    ) -> [BatteryHistorySegment] {
        if let chartCache,
           chartCache.startDate == startDate,
           chartCache.endDate == endDate,
           chartCache.maximumPointCount == maximumPointCount {
            return chartCache.segments
        }

        let sourceSegments = segments(from: startDate, through: endDate)
        let recordCount = sourceSegments.reduce(0) { $0 + $1.records.count }
        let result: [BatteryHistorySegment]
        if recordCount > maximumPointCount {
            result = sourceSegments.map { segment in
                let proportion = Double(segment.records.count) / Double(recordCount)
                let budget = max(4, Int((Double(maximumPointCount) * proportion).rounded()))
                return BatteryHistorySegment(
                    id: segment.id,
                    records: downsample(segment.records, maximumPointCount: budget)
                )
            }
        } else {
            result = sourceSegments
        }

        chartCache = ChartCache(
            startDate: startDate,
            endDate: endDate,
            maximumPointCount: maximumPointCount,
            segments: result
        )
        return result
    }

    func nearestRecord(to date: Date) -> BatteryHistoryRecord? {
        guard !records.isEmpty else { return nil }

        var low = 0
        var high = records.count
        while low < high {
            let middle = (low + high) / 2
            if records[middle].recordedAt < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        let later = low < records.count ? records[low] : nil
        let earlier = low > 0 ? records[low - 1] : nil
        switch (earlier, later) {
        case let (earlier?, later?):
            return date.timeIntervalSince(earlier.recordedAt) <= later.recordedAt.timeIntervalSince(date)
                ? earlier
                : later
        case let (earlier?, nil): return earlier
        case let (nil, later?): return later
        case (nil, nil): return nil
        }
    }

    private func record(_ snapshot: BatterySnapshot) {
        guard snapshot.isAvailable, snapshot.percentage != nil else { return }
        let record = BatteryHistoryRecord(snapshot: snapshot)
        guard shouldStore(record) else { return }

        records.append(record)
        invalidateChartCache()
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
            invalidateChartCache()
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
        invalidateChartCache()
        let cutoff = now.addingTimeInterval(-retentionInterval)
        records.removeAll { $0.recordedAt < cutoff }
        if records.count > maximumRecordCount {
            records.removeFirst(records.count - maximumRecordCount)
        }
    }

    private func downsample(
        _ source: [BatteryHistoryRecord],
        maximumPointCount: Int
    ) -> [BatteryHistoryRecord] {
        guard source.count > maximumPointCount, maximumPointCount >= 4 else { return source }

        let bucketSize = max(1, Int(ceil(Double(source.count) / Double(maximumPointCount / 4))))
        var sampled: [BatteryHistoryRecord] = []
        var seen = Set<UUID>()

        for startIndex in stride(from: 0, to: source.count, by: bucketSize) {
            let endIndex = min(startIndex + bucketSize, source.count)
            let bucket = source[startIndex..<endIndex]
            guard let first = bucket.first, let last = bucket.last else { continue }
            let minimum = bucket.min { $0.percentage < $1.percentage } ?? first
            let maximum = bucket.max { $0.percentage < $1.percentage } ?? last

            [first, minimum, maximum, last]
                .sorted { $0.recordedAt < $1.recordedAt }
                .forEach { record in
                    if seen.insert(record.id).inserted {
                        sampled.append(record)
                    }
                }
        }

        return sampled
    }

    private func firstIndex(onOrAfter date: Date) -> Int {
        var low = 0
        var high = records.count
        while low < high {
            let middle = (low + high) / 2
            if records[middle].recordedAt < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func firstIndex(after date: Date) -> Int {
        var low = 0
        var high = records.count
        while low < high {
            let middle = (low + high) / 2
            if records[middle].recordedAt <= date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func invalidateChartCache() {
        chartCache = nil
    }

    private func recordRange(from startDate: Date, through endDate: Date) -> Range<Int>? {
        guard startDate <= endDate, !records.isEmpty else { return nil }
        let startIndex = firstIndex(onOrAfter: startDate)
        let endIndex = firstIndex(after: endDate)
        guard startIndex < endIndex else { return nil }
        return startIndex..<endIndex
    }
}
