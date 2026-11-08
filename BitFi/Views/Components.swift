import AppKit
import SwiftUI

struct BatteryLevelSymbol: View {
    let snapshot: BatterySnapshot
    var tint: Color = .primary
    var width: CGFloat = 24
    var height: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            // Slightly lighter than the system battery symbol at this compact size.
            let lineWidth = max(1, min(size.width, size.height) * 0.075)
            let terminalWidth = max(2, size.width * 0.075)
            let bodyRect = CGRect(
                x: lineWidth / 2,
                y: lineWidth / 2,
                width: max(1, size.width - terminalWidth - lineWidth * 1.8),
                height: max(1, size.height - lineWidth)
            )
            let cornerRadius = min(bodyRect.height * 0.23, 3)
            let bodyPath = Path(roundedRect: bodyRect, cornerRadius: cornerRadius)
            context.stroke(bodyPath, with: .color(tint), lineWidth: lineWidth)

            let terminalRect = CGRect(
                x: bodyRect.maxX + lineWidth * 0.5,
                y: bodyRect.midY - bodyRect.height * 0.16,
                width: terminalWidth,
                height: bodyRect.height * 0.32
            )
            context.fill(Path(roundedRect: terminalRect, cornerRadius: 1), with: .color(tint))

            let innerRect = bodyRect.insetBy(dx: lineWidth * 1.2, dy: lineWidth * 1.2)
            let fraction = CGFloat(snapshot.batteryLevelFraction ?? 0)
            let fillWidth = innerRect.width * fraction
            guard fillWidth > 0 else { return }

            let fillRect = CGRect(
                x: innerRect.minX,
                y: innerRect.minY,
                width: max(min(fillWidth, innerRect.width), lineWidth * 0.75),
                height: innerRect.height
            )
            context.fill(
                Path(roundedRect: fillRect, cornerRadius: min(fillRect.height * 0.2, 2)),
                with: .color(tint)
            )
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

struct BatteryHeader: View {
    let snapshot: BatterySnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            BatteryLevelSymbol(
                snapshot: snapshot,
                tint: snapshot.isCharging ? .accentColor : .secondary,
                width: 38,
                height: 22
            )
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text("Battery")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    BatteryLevelSymbol(snapshot: snapshot, tint: .secondary, width: 20, height: 12)
                    Text(snapshot.statusTitle)
                }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(snapshot.percentageText)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Battery level \(snapshot.percentageText)")
        }
    }
}

enum SystemAppLauncher {
    static func activityMonitorURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
    }

    @discardableResult
    static func openActivityMonitor() -> Bool {
        guard let url = activityMonitorURL() else { return false }
        return NSWorkspace.shared.open(url)
    }
}

struct BatteryLevelBar: View {
    let percentage: Int?

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(0, proxy.size.width * Double(percentage ?? 0) / 100))
                }
        }
        .frame(height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(percentage.map(String.init) ?? "Unavailable")
    }
}

struct BatteryMetricRow: View {
    let title: String
    let value: String
    var symbolName: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let symbolName {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button("Copy Value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChargeReminderStatusView: View {
    let state: ChargeReminderState
    let limit: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch state {
        case .disabled:
            "No charge-limit reminder is running."
        case .waitingForPower:
            "Connect power; reminder starts automatically."
        case .chargingTowardLimit:
            "Will notify at \(limit)% while power is connected."
        case .limitReached:
            "Unplug power to remain near \(limit)%."
        case .pausedForSession:
            "Charge reminder resumes after power is disconnected."
        case .unavailable:
            "macOS has not reported an internal battery."
        }
    }

    private var symbolColor: Color {
        switch state {
        case .limitReached: .orange
        case .chargingTowardLimit: .accentColor
        default: .secondary
        }
    }
}

struct BatteryUnavailableView: View {
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label("Battery Unavailable", systemImage: "battery.0")
        } description: {
            Text(reason)
        }
    }
}
