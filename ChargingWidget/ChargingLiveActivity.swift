import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ChargingWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        ChargingLiveActivity()
    }
}

struct ChargingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            LockScreenChargingView(context: context)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.socPercent)%", systemImage: "bolt.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let range = context.state.rangeMiles {
                        Text("\(range) mi")
                            .font(.title3.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ChargingBarView(
                            socPercent: context.state.socPercent,
                            limitPercent: context.state.limitPercent
                        )
                        countdownLine(context.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text("\(context.state.socPercent)%")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func countdownLine(_ state: ChargingActivityAttributes.ContentState) -> some View {
        if let end = state.chargeEndDate, end > Date() {
            HStack(spacing: 4) {
                Text(timerInterval: Date()...end, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 70)
                Text("to \(state.limitPercent.map { "\($0)%" } ?? "limit")")
            }
        } else {
            Text("Charging")
        }
    }
}

// MARK: - Lock Screen view

private struct LockScreenChargingView: View {
    let context: ActivityViewContext<ChargingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                Text("\(context.attributes.vehicleName) · Charging")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let range = context.state.rangeMiles {
                    Text("\(range) mi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ChargingBarView(
                socPercent: context.state.socPercent,
                limitPercent: context.state.limitPercent
            )
            HStack {
                Text("\(context.state.socPercent)%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                Spacer()
                if let end = context.state.chargeEndDate, end > Date() {
                    HStack(spacing: 4) {
                        Text(timerInterval: Date()...end, countsDown: true)
                            .monospacedDigit()
                            .frame(maxWidth: 70)
                        Text("to \(context.state.limitPercent.map { "\($0)%" } ?? "limit")")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Shared battery bar

struct ChargingBarView: View {
    let socPercent: Int
    let limitPercent: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fill = width * CGFloat(min(max(socPercent, 0), 100)) / 100
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.35))
                Rectangle()
                    .fill(Color.green.gradient)
                    .frame(width: fill)
                if let limit = limitPercent, limit < 100 {
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 2)
                        .offset(x: width * CGFloat(limit) / 100 - 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 14)
    }
}
