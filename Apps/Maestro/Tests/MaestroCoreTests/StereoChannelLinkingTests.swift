import Testing
@testable import MaestroCore

@Suite("Odd/even stereo input/output channel linking")
struct StereoChannelLinkingTests {
    @Test func completeOddEvenPairsOnly() {
        #expect(StereoChannelLinking.pairStarts(channelCount: 1).isEmpty)
        #expect(StereoChannelLinking.pairStarts(channelCount: 7) == [0, 2, 4])
        #expect(StereoChannelLinking.pairStart(for: 0, channelCount: 64) == 0)
        #expect(StereoChannelLinking.pairStart(for: 1, channelCount: 64) == 0)
        #expect(StereoChannelLinking.partner(of: 62, channelCount: 64) == 63)
        #expect(StereoChannelLinking.partner(of: 63, channelCount: 64) == 62)
        #expect(StereoChannelLinking.partner(of: 6, channelCount: 7) == nil)
        #expect(!StereoChannelLinking.canLink(pairStart: 1, channelCount: 64))
        #expect(!StereoChannelLinking.canLink(pairStart: 63, channelCount: 64))
    }

    @Test func noLinkCrossesBoardOrPortBoundary() {
        #expect(StereoChannelLinking.pairStarts(channelCount: 8, boundaries: [3]) == [0, 4, 6])
        #expect(StereoChannelLinking.partner(of: 2, channelCount: 8, boundaries: [3]) == nil)
        // A correctly aligned port boundary retains pairs 31/32 and 33/34,
        // never physical channels 32/33.
        #expect(StereoChannelLinking.pairStarts(channelCount: 64, boundaries: [32]).count == 32)
        #expect(StereoChannelLinking.partner(of: 31, channelCount: 64, boundaries: [32]) == 30)
        #expect(StereoChannelLinking.partner(of: 32, channelCount: 64, boundaries: [32]) == 33)
    }

    @Test(arguments: [0, 1, 2, 3, 7, 16, 32, 64])
    func groupsPreserveEveryChannelExactlyOnce(channelCount: Int) {
        let links = Set(StereoChannelLinking.pairStarts(channelCount: channelCount))
        let groups = StereoChannelLinking.groups(channelCount: channelCount, linkedPairStarts: links)
        #expect(groups.flatMap(\.indices) == Array(0..<channelCount))
        #expect(Set(groups.map(\.id)).count == groups.count)
        #expect(groups.filter { $0.right != nil }.count == channelCount / 2)
    }

    @Test func staleOrInvalidSavedLinksNeverHideChannels() {
        let groups = StereoChannelLinking.groups(channelCount: 5,
                                                 linkedPairStarts: [-2, -1, 0, 1, 4, 6, 99])
        #expect(groups == [.init(left: 0, right: 1), .init(left: 2), .init(left: 3), .init(left: 4)])
        #expect(StereoChannelLinking.groups(channelCount: -1, linkedPairStarts: [0]).isEmpty)
        #expect(StereoChannelLinking.partner(of: -1, channelCount: 64) == nil)
        #expect(StereoChannelLinking.partner(of: 64, channelCount: 64) == nil)
        #expect(StereoChannelLinking.pairStarts(channelCount: -1).isEmpty)
        #expect(!StereoChannelLinking.canLink(pairStart: .max, channelCount: .max))
        #expect(StereoChannelLinking.pairStart(for: .max - 1, channelCount: .max) == nil)
        #expect(StereoChannelLinking.pairStarts(channelCount: 4, boundaries: [-1, 0, 4, 99]) == [0, 2])
    }

    @Test func unlinkReturnsIndependentMonoGroupsWithoutChangingIndices() {
        let linked = StereoChannelLinking.groups(channelCount: 4, linkedPairStarts: [0, 2])
        let unlinked = StereoChannelLinking.groups(channelCount: 4, linkedPairStarts: [2])
        #expect(linked == [.init(left: 0, right: 1), .init(left: 2, right: 3)])
        #expect(unlinked == [.init(left: 0), .init(left: 1), .init(left: 2, right: 3)])
        #expect(linked.flatMap(\.indices) == unlinked.flatMap(\.indices))
    }

    @Test func initialAlignmentChoosesQuieterSideInEitherOrder() {
        #expect(StereoChannelLinking.quieterLevel(left: -0.5, right: -1.5,
            leftRange: -2...2, rightRange: -2...2) == -1.5)
        #expect(StereoChannelLinking.quieterLevel(left: -1.5, right: -0.5,
            leftRange: -2...2, rightRange: -2...2) == -1.5)
        #expect(StereoChannelLinking.quieterLevel(left: 35, right: 20,
            leftRange: 0...75, rightRange: 0...75) == 20)
    }

    @Test func initialAlignmentLeavesEqualLevelsUnchanged() {
        #expect(StereoChannelLinking.quieterLevel(left: -1, right: -1,
            leftRange: -2...2, rightRange: -2...2) == -1)
        #expect(StereoChannelLinking.quieterLevel(left: 0, right: 0,
            leftRange: 0...0, rightRange: 0...75) == 0)
    }

    @Test func incompatibleRangesCannotRaiseQuieterSideToCreateAMatch() {
        // Clamping the target from -1 to zero would make the quieter side
        // louder. Refuse alignment instead, leaving both values untouched.
        #expect(StereoChannelLinking.quieterLevel(left: -1, right: 0.5,
            leftRange: -2...2, rightRange: 0...3) == nil)
        #expect(StereoChannelLinking.quieterLevel(left: 0.5, right: -1,
            leftRange: 0...3, rightRange: -2...2) == nil)
        #expect(StereoChannelLinking.quieterLevel(left: -1, right: 2,
            leftRange: -2 ... -0.5, rightRange: 1...3) == nil)
        #expect(StereoChannelLinking.quieterLevel(left: -3, right: 0,
            leftRange: -2...2, rightRange: -2...2) == nil)
    }

    @Test func initialAlignmentRejectsNonfiniteValuesAndRanges() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(StereoChannelLinking.quieterLevel(left: value, right: 0,
                leftRange: -2...2, rightRange: -2...2) == nil)
            #expect(StereoChannelLinking.quieterLevel(left: 0, right: value,
                leftRange: -2...2, rightRange: -2...2) == nil)
        }
        #expect(StereoChannelLinking.quieterLevel(left: 0, right: 0,
            leftRange: -.infinity...2, rightRange: -2...2) == nil)
    }

    @Test func relativeLevelMovePreservesExistingCalibrationOffset() throws {
        let result = try #require(StereoChannelLinking.movePair(
            left: -1, right: -0.5, leftRange: -2...2, rightRange: -2...2, requestedLeft: 0))
        #expect(result.left == 0 && result.right == 0.5 && result.delta == 1)
        #expect(result.right - result.left == 0.5)
    }

    @Test func firstChannelLimitBoundsBothChannelsWithDifferentRanges() throws {
        let upper = try #require(StereoChannelLinking.movePair(
            left: 0, right: 1, leftRange: -2...2, rightRange: -2...1.5, requestedLeft: 2))
        #expect(upper.left == 0.5 && upper.right == 1.5 && upper.delta == 0.5)
        let lower = try #require(StereoChannelLinking.movePair(
            left: 1, right: 0.5, leftRange: 0...4, rightRange: 0...3, requestedLeft: -100))
        #expect(lower.left == 0.5 && lower.right == 0 && lower.delta == -0.5)
    }

    @Test func gainRangesAndZeroWidthLimitAreHandled() throws {
        let gain = try #require(StereoChannelLinking.movePair(
            left: 20, right: 24, leftRange: 0...75, rightRange: 0...75, requestedLeft: 30))
        #expect(gain.left == 30 && gain.right == 34)
        let fixed = try #require(StereoChannelLinking.movePair(
            left: 2, right: 3, leftRange: 2...2, rightRange: 0...10, requestedLeft: 9))
        #expect(fixed.left == 2 && fixed.right == 3 && fixed.delta == 0)
    }

    @Test func invalidOrNonFiniteValuesDoNotGenerateAnAdjustment() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(StereoChannelLinking.movePair(left: value, right: 0,
                leftRange: -2...2, rightRange: -2...2, requestedLeft: 1) == nil)
            #expect(StereoChannelLinking.movePair(left: 0, right: value,
                leftRange: -2...2, rightRange: -2...2, requestedLeft: 1) == nil)
            #expect(StereoChannelLinking.movePair(left: 0, right: 0,
                leftRange: -2...2, rightRange: -2...2, requestedLeft: value) == nil)
        }
        #expect(StereoChannelLinking.movePair(left: 3, right: 0,
            leftRange: -2...2, rightRange: -2...2, requestedLeft: 1) == nil)
        #expect(StereoChannelLinking.movePair(left: 0, right: 0,
            leftRange: -.infinity...2, rightRange: -2...2, requestedLeft: 1) == nil)
        #expect(StereoChannelLinking.movePair(left: 0, right: 0,
            leftRange: -2...2, rightRange: -2...Double.infinity, requestedLeft: 1) == nil)
    }
}
