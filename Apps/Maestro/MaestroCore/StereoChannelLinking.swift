/// Presentation/control grouping for adjacent odd/even channel pairs.
/// Indices are zero-based; 0/1 represents physical channels 1/2. Grouping never
/// changes a hardware address, Core Audio channel number, routing or audio data.
public struct StereoChannelGroup: Equatable, Identifiable, Sendable {
    public let left: Int
    public let right: Int?
    public var id: Int { left }
    public var indices: [Int] { right.map { [left, $0] } ?? [left] }

    public init(left: Int, right: Int? = nil) {
        self.left = left
        self.right = right
    }
}

public struct StereoLinkedLevels: Equatable, Sendable {
    public let left: Double
    public let right: Double
    /// The common requested movement after both channel limits were applied.
    public let delta: Double
}

public enum StereoChannelLinking {
    /// `boundaries` contains the zero-based first channel of each subsequent
    /// board/port. A pair cannot straddle that boundary. Invalid boundary values
    /// cannot create an additional channel or change odd/even pair alignment.
    public static func canLink(pairStart: Int, channelCount: Int,
                               boundaries: [Int] = []) -> Bool {
        guard channelCount > 1, pairStart >= 0, pairStart.isMultiple(of: 2),
              pairStart < channelCount - 1 else { return false }
        return !boundaries.contains(pairStart + 1)
    }

    /// Returns the complete eligible odd/even pair containing this channel.
    public static func pairStart(for channel: Int, channelCount: Int,
                                 boundaries: [Int] = []) -> Int? {
        guard channel >= 0, channel < channelCount else { return nil }
        let start = channel - channel % 2
        return canLink(pairStart: start, channelCount: channelCount, boundaries: boundaries)
            ? start : nil
    }

    public static func partner(of channel: Int, channelCount: Int,
                               boundaries: [Int] = []) -> Int? {
        guard let start = pairStart(for: channel, channelCount: channelCount,
                                    boundaries: boundaries) else { return nil }
        return channel == start ? start + 1 : start
    }

    public static func pairStarts(channelCount: Int, boundaries: [Int] = []) -> [Int] {
        guard channelCount > 1 else { return [] }
        return stride(from: 0, to: channelCount - 1, by: 2).filter {
            canLink(pairStart: $0, channelCount: channelCount, boundaries: boundaries)
        }
    }

    /// Stored stale, odd, negative or incomplete pairs are ignored for this
    /// inventory. Every real channel remains present exactly once and in its
    /// original order. Unlinking changes grouping only, never channel values.
    public static func groups(channelCount: Int, linkedPairStarts: Set<Int>,
                              boundaries: [Int] = []) -> [StereoChannelGroup] {
        guard channelCount > 0 else { return [] }
        var groups: [StereoChannelGroup] = []
        var index = 0
        while index < channelCount {
            if linkedPairStarts.contains(index),
               canLink(pairStart: index, channelCount: channelCount, boundaries: boundaries) {
                groups.append(.init(left: index, right: index + 1))
                index += 2
            } else {
                groups.append(.init(left: index))
                index += 1
            }
        }
        return groups
    }

    /// Initial stereo alignment uses the quieter current dB value for both
    /// channels. Never clamp upward to satisfy a mismatched channel range:
    /// return nil if that lowering-only common target is not legal for both.
    /// This computes a target only and does not issue hardware writes.
    public static func quieterLevel(left: Double, right: Double,
                                    leftRange: ClosedRange<Double>,
                                    rightRange: ClosedRange<Double>) -> Double? {
        let values = [left, right, leftRange.lowerBound, leftRange.upperBound,
                      rightRange.lowerBound, rightRange.upperBound]
        guard values.allSatisfy(\.isFinite), leftRange.contains(left),
              rightRange.contains(right) else { return nil }
        let quieter = min(left, right)
        guard leftRange.contains(quieter), rightRange.contains(quieter) else { return nil }
        return quieter
    }

    /// A relative level movement that retains existing L/R offsets. The left
    /// control requests a value; both channels move by the same delta until the
    /// first channel reaches its own limit. Finite in-range starting values and
    /// finite range endpoints are required. Unrepresentable arithmetic returns
    /// nil. Final endpoint clamping absorbs ordinary floating-point rounding.
    /// This returns values only; callers decide whether/how to issue writes.
    public static func movePair(left: Double, right: Double,
                                leftRange: ClosedRange<Double>,
                                rightRange: ClosedRange<Double>,
                                requestedLeft: Double) -> StereoLinkedLevels? {
        let values = [left, right, requestedLeft, leftRange.lowerBound, leftRange.upperBound,
                      rightRange.lowerBound, rightRange.upperBound]
        guard values.allSatisfy(\.isFinite), leftRange.contains(left),
              rightRange.contains(right) else { return nil }
        let minimumDelta = max(leftRange.lowerBound - left, rightRange.lowerBound - right)
        let maximumDelta = min(leftRange.upperBound - left, rightRange.upperBound - right)
        let requestedDelta = requestedLeft - left
        guard minimumDelta.isFinite, maximumDelta.isFinite, requestedDelta.isFinite,
              minimumDelta <= maximumDelta else { return nil }
        let delta = min(max(requestedDelta, minimumDelta), maximumDelta)
        let newLeft = min(max(left + delta, leftRange.lowerBound), leftRange.upperBound)
        let newRight = min(max(right + delta, rightRange.lowerBound), rightRange.upperBound)
        guard newLeft.isFinite, newRight.isFinite else { return nil }
        return StereoLinkedLevels(left: newLeft, right: newRight, delta: delta)
    }
}
