import AppKit
import Combine
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import MachO

/// Reads public IOKit power-source data. No private IORegistry keys or charger controls.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.unavailable

    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var fallbackTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource(Self.powerSourceChanged, context)?.takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let description = internalBatteryDescription() else {
            snapshot = .unavailable
            return
        }

        let currentCapacity = integer(for: "Current Capacity", in: description)
        let maximumCapacity = integer(for: "Max Capacity", in: description)
        let legacyInfo = legacyBatteryInfo()

        let isCharging = boolean(for: "Is Charging", in: description) ?? false

        snapshot = BatterySnapshot(
            currentCapacity: currentCapacity,
            maximumCapacity: maximumCapacity,
            powerSource: PowerSourceKind(powerSourceState: string(for: "Power Source State", in: description)),
            isCharging: isCharging,
            isCharged: boolean(for: "Is Charged", in: description) ?? false,
            timeToEmptyMinutes: isCharging ? nil : validMinutes(for: "Time to Empty", in: description),
            timeToFullChargeMinutes: isCharging ? validMinutes(for: "Time to Full Charge", in: description) : nil,
            cycleCount: integer(for: "Cycle Count", in: legacyInfo),
            health: string(for: "BatteryHealth", in: description),
            healthCondition: string(for: "BatteryHealthCondition", in: description),
            temperatureCelsius: double(for: "Temperature", in: description),
            voltageMillivolts: integer(for: "Voltage", in: description),
            amperageMilliamps: integer(for: "Current", in: description),
            updatedAt: .now,
            unavailableReason: nil
        )
    }

    func stop() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
        powerSourceRunLoopSource = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        hasStarted = false
    }

    private static let powerSourceChanged: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in
            monitor.refresh()
        }
    }

    private func internalBatteryDescription() -> [String: Any]? {
        guard let infoReference = IOPSCopyPowerSourcesInfo() else { return nil }
        let info = infoReference.takeRetainedValue()
        guard let sourcesReference = IOPSCopyPowerSourcesList(info) else { return nil }
        let sources = sourcesReference.takeRetainedValue() as NSArray

        for source in sources {
            guard let descriptionReference = IOPSGetPowerSourceDescription(info, source as CFTypeRef) else { continue }
            let description = descriptionReference.takeUnretainedValue() as NSDictionary
            guard string(for: "Type", in: description) == "InternalBattery" else { continue }
            return description as? [String: Any]
        }

        return nil
    }

    /// `IOPMCopyBatteryInfo` is public, legacy API. Used only for documented cycle-count field.
    private func legacyBatteryInfo() -> [String: Any]? {
        var batteryInfoReference: Unmanaged<CFArray>?
        let result = IOPMCopyBatteryInfo(mach_port_t(MACH_PORT_NULL), &batteryInfoReference)
        guard result == KERN_SUCCESS,
              let batteryInfo = batteryInfoReference?.takeRetainedValue() as? NSArray,
              let firstBattery = batteryInfo.firstObject as? [String: Any]
        else {
            return nil
        }
        return firstBattery
    }

    private func string(for key: String, in dictionary: [String: Any]?) -> String? {
        normalizedString(dictionary?[key] as? String)
    }

    private func string(for key: String, in dictionary: NSDictionary) -> String? {
        normalizedString(dictionary[key] as? String)
    }

    private func integer(for key: String, in dictionary: [String: Any]?) -> Int? {
        if let number = dictionary?[key] as? NSNumber { return number.intValue }
        return dictionary?[key] as? Int
    }

    private func double(for key: String, in dictionary: [String: Any]?) -> Double? {
        if let number = dictionary?[key] as? NSNumber { return number.doubleValue }
        return dictionary?[key] as? Double
    }

    private func boolean(for key: String, in dictionary: [String: Any]?) -> Bool? {
        if let value = dictionary?[key] as? Bool { return value }
        if let number = dictionary?[key] as? NSNumber { return number.boolValue }
        return nil
    }

    private func validMinutes(for key: String, in dictionary: [String: Any]?) -> Int? {
        guard let minutes = integer(for: key, in: dictionary), minutes >= 0 else { return nil }
        return minutes
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
