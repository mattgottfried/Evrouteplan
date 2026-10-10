//
//  VehicleStatusSection.swift
//  BetterBlue
//
//  The widget's status section (range line + per-axis percentage bars +
//  the app-style EV charging bar). Decoupled from the widget's
//  `VehicleEntity` via `StatusSectionData` so it can be shared with the
//  main app — which lets the interactive debug screen
//  (`WidgetStatusDebugView`) render the real view and preview reliably
//  under the app scheme. Compiled into both the app and WidgetExtension
//  targets.
//

import SwiftUI

/// Plain inputs the status section renders. The widget builds this from
/// its `VehicleEntity`; the debug screen builds it from sliders.
struct StatusSectionData {
    var hasElectricCapability: Bool
    var evRange: String?
    var evBatteryPercentage: Double?
    var gasRange: String?
    var gasFuelPercentage: Double?
    var rangeText: String
    var batteryPercentage: Double?
    var isCharging: Bool
    var chargeSpeedKilowatts: Double?
    var chargeTimeRemainingMinutes: Int?
    var targetStateOfCharge: Int?
    var isLocked: Bool?
    var isClimateOn: Bool?
    var chargingColor: Color
    var gasColor: Color
    /// Append the numeric percentage after the EV / gas range.
    var showEVPercent: Bool = true
    var showGasPercent: Bool = true
}

/// Range + status line on top, a color-coded percentage bar per fuel
/// axis beneath. The EV axis becomes the app-style charging bar while
/// plugged in (on the larger / non-`isSmall` layout).
///   • Gas  → one orange bar.
///   • EV   → one green bar.
///   • PHEV → a green bar then an orange bar.
struct VehicleStatusColumn: View {
    let data: StatusSectionData
    let textColor: Color
    let isSmall: Bool
    /// When set (small widget), the status line leads with this text —
    /// the last-updated time, which has no room of its own there.
    var leadingTime: String?

    /// One fuel axis: its color, display label, and fill level. EV uses
    /// the charging color, gas uses the gas color. The EV axis gets the
    /// richer charging bar when plugged in. `label` is the range plus,
    /// when the matching toggle is on, "· <pct>%".
    private struct Axis: Identifiable {
        let id: Int
        let color: Color
        let label: String
        let fraction: Double
        let isEV: Bool
    }

    /// Builds "<range>" or "<range> · <pct>%" depending on the toggle.
    private func label(range: String, percent: Double?, showPercent: Bool) -> String {
        guard showPercent, let percent else { return range }
        return "\(range) · \(Int(percent.rounded()))%"
    }

    private var axes: [Axis] {
        var result: [Axis] = []

        // EV first (matches the PHEV sketch: EV then gas).
        if data.hasElectricCapability, let evRange = data.evRange {
            result.append(Axis(
                id: 0, color: data.chargingColor,
                label: label(range: evRange, percent: data.evBatteryPercentage, showPercent: data.showEVPercent),
                fraction: (data.evBatteryPercentage ?? 0) / 100, isEV: true
            ))
        }
        if let gasRange = data.gasRange {
            result.append(Axis(
                id: 1, color: data.gasColor,
                label: label(range: gasRange, percent: data.gasFuelPercentage, showPercent: data.showGasPercent),
                fraction: (data.gasFuelPercentage ?? 0) / 100, isEV: false
            ))
        }

        // Fallback: a vehicle with no parsed per-axis data still shows
        // its legacy range + battery so the column isn't empty.
        if result.isEmpty, !data.rangeText.isEmpty {
            let isEV = data.hasElectricCapability
            result.append(Axis(
                id: 2,
                color: isEV ? data.chargingColor : data.gasColor,
                label: label(
                    range: data.rangeText,
                    percent: data.batteryPercentage,
                    showPercent: isEV ? data.showEVPercent : data.showGasPercent
                ),
                fraction: (data.batteryPercentage ?? 0) / 100,
                isEV: isEV
            ))
        }

        return result
    }

    /// The top line: each axis's range in its fuel color, then smaller
    /// lock and climate glyphs in the default text color. Laid out as an
    /// HStack (rather than concatenated Text, whose `+` is deprecated in
    /// iOS 26) so each run keeps its own color and glyph size.
    private var statusLineView: some View {
        HStack(spacing: 5) {
            if let leadingTime {
                Text(leadingTime).foregroundColor(textColor.opacity(0.7))
            }
            ForEach(axes) { axis in
                Text(axis.label).foregroundColor(axis.color)
            }
            // Charge speed isn't shown here — it lives inside the charging
            // bar (right-aligned) so a PHEV's two-range line isn't cut off.
            if let locked = data.isLocked {
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(glyphFont)
                    .foregroundColor(textColor)
            }
            if let climateOn = data.isClimateOn {
                Image(systemName: climateOn ? "fan.fill" : "fan.slash")
                    .font(glyphFont)
                    .foregroundColor(textColor)
            }
        }
        .font(isSmall ? .caption2 : .footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Lock/climate glyphs render a step smaller than the range.
    private var glyphFont: Font { isSmall ? .system(size: 9) : .caption2 }

    // Width of the status line, measured so the bars are exactly as wide
    // as the text above them rather than spanning the whole column.
    @State private var lineWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: isSmall ? .center : .trailing, spacing: 3) {
            statusLineView
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: StatusLineWidthKey.self, value: geo.size.width)
                    }
                )

            ForEach(axes) { axis in
                // While charging, the EV axis gets the app-style bar
                // (time-remaining text + dashed target marker) on the
                // larger layout; everything else is the thin capsule.
                if axis.isEV, !isSmall, data.isCharging {
                    chargingBar(axis)
                } else {
                    percentageBar(fraction: axis.fraction, color: axis.color)
                }
            }
        }
        .onPreferenceChange(StatusLineWidthKey.self) { lineWidth = $0 }
    }

    private func percentageBar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(textColor.opacity(0.22))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(width: lineWidth > 0 ? lineWidth : nil, height: 5)
    }

    /// App-style charging bar: a taller capsule track with the time
    /// remaining and charge speed inside it and a thin vertical line at
    /// the target charge level — mirroring the main sheet's EV bar.
    /// Text positions are fill-aware so they sit over the green fill or
    /// the gray remainder rather than straddling the boundary/outline.
    private func chargingBar(_ axis: Axis) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let limitX: CGFloat? = data.targetStateOfCharge
                .flatMap { $0 < 100 ? width * (Double($0) / 100.0) : nil }

            ZStack(alignment: .leading) {
                // Track, a hatch over the won't-fill region beyond the
                // limit, the masked rectangular fill, then the limit line.
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(textColor.opacity(0.22))

                    if let limitX {
                        DiagonalHatch(spacing: 5)
                            .stroke(textColor.opacity(0.2), lineWidth: 1)
                            .frame(width: max(0, width - limitX), height: geo.size.height)
                            .clipped()
                            .offset(x: limitX)
                    }

                    Rectangle()
                        .fill(axis.color)
                        .frame(width: fillWidth(axis, width))

                    if let limitX {
                        ChargeLimitLine()
                            .stroke(textColor.opacity(0.2), lineWidth: 1)
                            .frame(width: 1)
                            .offset(x: limitX - 0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))

                // Charge speed — left-aligned over the fill.
                if let kw = data.chargeSpeedKilowatts, kw > 0 {
                    Text("\(Int(kw.rounded()))kw")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        .padding(.leading, 5)
                }

                // Time remaining — right-aligned to the limit line, or the
                // bar's right edge when there's no limit.
                if let minutes = data.chargeTimeRemainingMinutes, minutes > 0 {
                    Text(timeRemainingString(minutes))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        .padding(.trailing, 5)
                        .frame(width: limitX ?? width, alignment: .trailing)
                }
            }
        }
        .frame(width: lineWidth > 0 ? lineWidth : nil, height: 18)
    }

    /// Pixel width of the filled portion for an axis's fraction.
    private func fillWidth(_ axis: Axis, _ width: CGFloat) -> CGFloat {
        width * min(max(axis.fraction, 0), 1)
    }

    private func timeRemainingString(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// A single vertical line centered in its rect. Stroked thin to mark the
/// charge limit on the charging bar. Shared by the widget status bar and
/// the main sheet's `EVChargingProgressView`.
struct ChargeLimitLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Evenly spaced 45° diagonal lines filling the rect — a subtle hatch for
/// the portion of the charging bar beyond the limit that won't fill in.
/// Caller clips it to that region. Shared by the widget status bar and the
/// main sheet's `EVChargingProgressView`.
struct DiagonalHatch: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Lines run bottom-left → top-right; start a height's worth to the
        // left so the slanted lines still cover the rect's left edge.
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// Reports the measured width of the status line so its percentage bars
/// can match it.
private struct StatusLineWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
