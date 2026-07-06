import SwiftUI
import WidgetKit

/// Home screen / Lock Screen battery widget, fed by the snapshot the app
/// writes to the App Group on every BlueLink refresh.

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleSnapshot?
}

struct BatteryProvider: TimelineProvider {
    private var placeholderSnapshot: VehicleSnapshot {
        VehicleSnapshot(
            socPercent: 68, rangeMiles: 181, isCharging: true,
            isPluggedIn: true, vehicleName: "Ioniq 5", updatedAt: Date()
        )
    }

    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), snapshot: placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: Date(), snapshot: VehicleSnapshot.load() ?? placeholderSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let entry = BatteryEntry(date: Date(), snapshot: VehicleSnapshot.load())
        // The app pushes reloads on every refresh; this is just a fallback.
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
        completion(timeline)
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BatteryWidget", provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ioniq 5 Battery")
        .description("Battery level, range, and charging state.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryEntry

    private var soc: Int { entry.snapshot?.socPercent ?? 0 }
    private var charging: Bool { entry.snapshot?.isCharging == true }

    private var color: Color {
        if charging { return .green }
        if soc <= 20 { return .red }
        if soc <= 40 { return .orange }
        return .green
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(soc), in: 0...100) {
                Image(systemName: charging ? "bolt.fill" : "car.fill")
            } currentValueLabel: {
                Text("\(soc)")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: charging ? "bolt.fill" : "bolt.car.fill")
                    Text("\(soc)%").fontWeight(.bold)
                }
                if let range = entry.snapshot?.rangeMiles {
                    Text("\(range) mi range")
                }
                Text(charging ? "Charging" : relativeUpdated)
                    .font(.caption2)
            }
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: charging ? "bolt.fill" : "bolt.car.fill")
                    .foregroundStyle(color)
                Spacer()
                if charging {
                    Text("Charging")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
            Text("\(soc)%")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            if let range = entry.snapshot?.rangeMiles {
                Text("\(range) mi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            batteryBar
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot?.vehicleName ?? "Ioniq 5")
                    .font(.headline)
                Text("\(soc)%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                if let range = entry.snapshot?.rangeMiles {
                    Text("\(range) mi range")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .trailing, spacing: 6) {
                if charging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if entry.snapshot?.isPluggedIn == true {
                    Label("Plugged in", systemImage: "powerplug.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                batteryBar
                Text(relativeUpdated)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var batteryBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geo.size.width * CGFloat(min(max(soc, 0), 100)) / 100)
            }
        }
        .frame(height: 8)
    }

    private var relativeUpdated: String {
        guard let updated = entry.snapshot?.updatedAt else { return "No data — open the app" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updated, relativeTo: Date())
    }
}
