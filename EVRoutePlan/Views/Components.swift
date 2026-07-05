import SwiftUI

// MARK: - Glass card surface
// BetterBlue-style floating "liquid glass" pill. Real glass on iOS 26+,
// ultra-thin material with a hairline stroke on iOS 17–18.

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
    }
}

// MARK: - Card container (opaque, for list-style screens)

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Battery progress bar (adapted from BetterBlue's charging card)

struct DiagonalHatch: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}

/// Fat horizontal battery bar: green fill while charging with the remaining
/// time overlaid, a vertical charge-limit line, and a hatch over the region
/// the car won't fill past the limit. Slim gray capsule when idle.
struct BatteryBar: View {
    let percent: Int              // 0–100
    let isCharging: Bool
    let limitPercent: Int?        // DC charge limit, e.g. 80
    let overlayText: String?      // "1 hr 20 min to 80%"

    var body: some View {
        if isCharging {
            chargingBar
        } else {
            idleBar
        }
    }

    private var fillFraction: CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }

    private var chargingBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let limitX: CGFloat? = limitPercent.flatMap {
                $0 < 100 ? width * CGFloat($0) / 100 : nil
            }
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                    if let limitX {
                        DiagonalHatch(spacing: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            .frame(width: max(0, width - limitX))
                            .clipped()
                            .offset(x: limitX)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1)
                            .offset(x: limitX - 0.5)
                    }
                    Rectangle()
                        .fill(Color.green.gradient)
                        .frame(width: width * fillFraction)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let overlayText {
                    Text(overlayText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .padding(.trailing, 8)
                        .frame(width: limitX ?? width, alignment: .trailing)
                }
            }
        }
        .frame(height: 32)
    }

    private var idleBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule()
                    .fill(barColor.gradient)
                    .frame(width: geo.size.width * fillFraction)
            }
        }
        .frame(height: 8)
    }

    private var barColor: Color {
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return .green
    }
}

// MARK: - Small stat tile

struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - SOC change bar (arrival → departure at a charging stop)

struct SOCBar: View {
    let fromSOC: Double
    let toSOC: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemGroupedBackground))
                Capsule()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: geo.size.width * min(toSOC, 1))
                Capsule()
                    .fill(barColor.gradient)
                    .frame(width: geo.size.width * min(fromSOC, 1))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Battery \(Int(fromSOC * 100)) percent arriving, charge to \(Int(toSOC * 100)) percent")
    }

    private var barColor: Color {
        if fromSOC <= 0.15 { return .red }
        if fromSOC <= 0.30 { return .orange }
        return .green
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message).font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
