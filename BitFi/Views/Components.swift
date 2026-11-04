import AppKit
import SwiftUI

struct BatteryHeader: View {
    let snapshot: BatterySnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(systemName: snapshot.batterySymbolName)
                .font(.system(size: 24, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(snapshot.isCharging ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Battery")
                    .font(.title2.weight(.semibold))
                Label(snapshot.statusTitle, systemImage: snapshot.powerSource.symbolName)
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
