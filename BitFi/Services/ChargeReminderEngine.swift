import Combine
import Foundation

enum ChargeReminderState: Equatable {
    case disabled
    case waitingForPower
    case chargingTowardLimit
    case limitReached
    case pausedForSession
    case unavailable

    var title: String {
        switch self {
        case .disabled: "Off"
        case .waitingForPower: "Waiting for power"
        case .chargingTowardLimit: "Monitoring"
        case .limitReached: "Limit reached"
        case .pausedForSession: "Paused for this session"
        case .unavailable: "Battery unavailable"
        }
    }

    var symbolName: String {
        switch self {
        case .disabled: "pause.circle"
        case .waitingForPower: "powerplug"
        case .chargingTowardLimit: "eye"
        case .limitReached: "exclamationmark.circle"
        case .pausedForSession: "arrow.uturn.forward.circle"
        case .unavailable: "battery.0"
        }
    }
}

/// Implements reminder-based charge protection. macOS has no public API for arbitrary hardware caps.
@MainActor
final class ChargeReminderEngine: ObservableObject {
    @Published private(set) var state: ChargeReminderState = .unavailable
    @Published private(set) var isPausedForCurrentPowerSession = false

    private let notificationService: NotificationService
    private var cancellables = Set<AnyCancellable>()
    private var hasNotifiedAtCurrentLimit = false
    private var hasStarted = false

    init(notificationService: NotificationService) {
        self.notificationService = notificationService
    }

    func start(monitor: BatteryMonitor, settings: AppSettings) {
        guard !hasStarted else { return }
        hasStarted = true

        Publishers.CombineLatest3(
            monitor.$snapshot,
            settings.$isChargeReminderEnabled,
            settings.$chargeLimit
        )
        .receive(on: RunLoop.main)
        .sink { [weak self, weak settings] snapshot, isEnabled, limit in
            guard let self, let settings else { return }
            self.evaluate(snapshot: snapshot, isEnabled: isEnabled, limit: limit, shouldNotify: settings.notificationsEnabled)
        }
        .store(in: &cancellables)

        settings.$notificationsEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self, weak monitor, weak settings] _ in
                guard let self, let monitor, let settings else { return }
                self.evaluate(
                    snapshot: monitor.snapshot,
                    isEnabled: settings.isChargeReminderEnabled,
                    limit: settings.chargeLimit,
                    shouldNotify: settings.notificationsEnabled
                )
            }
            .store(in: &cancellables)
    }

    func pauseForCurrentPowerSession() {
        isPausedForCurrentPowerSession = true
        state = .pausedForSession
    }

    func resumeMonitoring() {
        isPausedForCurrentPowerSession = false
        hasNotifiedAtCurrentLimit = false
    }

    private func evaluate(snapshot: BatterySnapshot, isEnabled: Bool, limit: Double, shouldNotify: Bool) {
        guard snapshot.isAvailable else {
            state = .unavailable
            return
        }

        guard isEnabled else {
            state = .disabled
            return
        }

        guard snapshot.isConnectedToPower else {
            isPausedForCurrentPowerSession = false
            hasNotifiedAtCurrentLimit = false
            state = .waitingForPower
            return
        }

        guard !isPausedForCurrentPowerSession else {
            state = .pausedForSession
            return
        }

        guard let percentage = snapshot.percentage else {
            state = .unavailable
            return
        }

        let roundedLimit = Int(limit)
        if percentage >= roundedLimit {
            state = .limitReached
            if shouldNotify, !hasNotifiedAtCurrentLimit {
                hasNotifiedAtCurrentLimit = notificationService.sendChargeLimitReached(
                    limit: roundedLimit,
                    currentPercentage: percentage
                )
            }
        } else {
            state = .chargingTowardLimit
            hasNotifiedAtCurrentLimit = false
        }
    }
}
