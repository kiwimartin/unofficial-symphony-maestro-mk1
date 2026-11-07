import SwiftUI
import AppKit
import Foundation

/// One presentation strip for a physical odd/even pair. Pairing does not change
/// either channel's identity, routing or individual safety-sensitive controls.
/// The parent owns the optional bounded relative level move and unlink action.
struct StereoChannelStripView<Details: View>: View {
    let label: String
    let leftIndex: Int
    let rightIndex: Int
    let appState: AppState
    let isInput: Bool
    let onUnlink: () -> Void
    let level: Binding<Double>?
    let levelRange: ClosedRange<Double>
    let levelStep: Double
    let levelLabel: String
    let leftValue: Double
    let rightValue: Double
    let showZoneColoring: Bool
    let isUpdating: Bool
    private let details: Details

    @State private var showingDetails = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        label: String,
        leftIndex: Int,
        rightIndex: Int,
        appState: AppState,
        isInput: Bool,
        onUnlink: @escaping () -> Void,
        level: Binding<Double>? = nil,
        levelRange: ClosedRange<Double> = -2...2,
        levelStep: Double = 0.1,
        levelLabel: String = "Linked trim",
        leftValue: Double = 0,
        rightValue: Double = 0,
        showZoneColoring: Bool = false,
        isUpdating: Bool = false,
        @ViewBuilder details: () -> Details
    ) {
        self.label = label
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.appState = appState
        self.isInput = isInput
        self.onUnlink = onUnlink
        self.level = level
        self.levelRange = levelRange
        self.levelStep = levelStep
        self.levelLabel = levelLabel
        self.leftValue = leftValue
        self.rightValue = rightValue
        self.isUpdating = isUpdating
        self.showZoneColoring = showZoneColoring
        self.details = details()
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button(action: onUnlink) {
                    Image(systemName: "link")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(isUpdating)
                .accessibilityLabel("Unlink \(label)")
                .help("Split this stereo pair into mono strips. Levels and routing are preserved.")
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))

            Text(isInput ? "Stereo input · L / R" : "Stereo output · L / R")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            Text(level != nil ? levelLabel : "Independent L/R settings")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 25)

            HStack(alignment: .top, spacing: 5) {
                if let level {
                    FaderView(
                        value: level,
                        range: levelRange,
                        step: levelStep,
                        defaultValue: min(max(0, levelRange.lowerBound), levelRange.upperBound),
                        height: 200,
                        showScale: true,
                        externalReadout: true,
                        thumbHeight: 20,
                        thumbWidth: 18
                    )
                    .disabled(levelRange.lowerBound == levelRange.upperBound)
                    .help("Move both levels together while preserving their L/R difference and limits.")
                }
                meter(index: leftIndex, side: "L", showScale: level == nil)
                meter(index: rightIndex, side: "R", showScale: false)
            }
            .frame(height: 222, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 4) {
                valueReadout(side: "L", value: leftValue)
                valueReadout(side: "R", value: rightValue)
            }

            Button("L/R settings…") { showingDetails = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Individual channel controls, including reference, phase, phantom power and inserts where available.")
                .disabled(isUpdating)
                .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(label) · Individual L/R settings").font(.headline)
                            Spacer()
                            Button("Done") { showingDetails = false }
                        }
                        Text("These remain two physical channels. Individual settings stay separate.")
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView([.horizontal, .vertical]) {
                            details
                        }
                        .frame(maxWidth: 640, maxHeight: 680)
                    }
                    .padding(16)
                    .frame(minWidth: 320)
                }
        }
        .frame(width: 160)
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.controlBackgroundColor).opacity(colorScheme == .light ? 0.6 : 0.3))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label), stereo \(isInput ? "input" : "output")")
    }

    /// Meter arrays are observed here, not in the parent rack: a meter update
    /// invalidates this pair's display rather than the entire channel list.
    private func meterReading(index: Int, peak: Bool) -> Double? {
        guard index >= 0 else { return nil }
        let values: [Double]
        if isInput {
            values = peak ? appState.inputPeakHold : appState.inputMeterLevels
        } else {
            values = peak ? appState.outputPeakHold : appState.outputMeterLevels
        }
        guard values.indices.contains(index) else { return nil }
        let value = values[index]
        guard !value.isNaN, value != .infinity else { return nil }
        return value
    }

    @ViewBuilder
    private func meter(index: Int, side: String, showScale: Bool) -> some View {
        if let reading = meterReading(index: index, peak: false) {
            LEDMeterView(
                level: reading,
                peak: meterReading(index: index, peak: true) ?? -.infinity,
                label: side,
                height: 200,
                width: 11,
                showScale: showScale,
                scaleOnLeft: true,
                rangeDB: 48,
                showZoneColoring: showZoneColoring
            )
            .accessibilityLabel("\(side) meter")
            .accessibilityValue(reading == -.infinity ? "Minus infinity dBFS" : String(format: "%.1f dBFS", reading))
        } else {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay {
                        Text("N/V")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 30, height: 200)
                Text(side).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .help("\(side) meter unavailable. No level is being reported for this channel.")
            .accessibilityLabel("\(side) meter unavailable")
        }
    }

    private func valueReadout(side: String, value: Double) -> some View {
        Text(value.isFinite ? String(format: "%@ %.1f dB", side, value) : "\(side) —")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            .accessibilityLabel("\(side) \(levelLabel)")
    }
}
