import Foundation
import Testing

struct ScreenSnapshotStabilityTests {
    @Test
    func `Starts settling after the first frame despite slow simulator startup`() {
        var stability = ScreenSnapshotStability()
        let pixels = Data([1, 2, 3])

        #expect(stability.observe(pixels, at: 10) == .pending)
        #expect(stability.observe(pixels, at: 10.25) == .pending)
        #expect(stability.observe(pixels, at: 10.5) == .settled)
    }

    @Test
    func `Accepts a stable frame delivered after the settling deadline`() {
        var stability = ScreenSnapshotStability()
        let pixels = Data([1, 2, 3])

        #expect(stability.observe(pixels, at: 0) == .pending)
        #expect(stability.observe(pixels, at: 0.25) == .pending)
        #expect(stability.observe(pixels, at: 5) == .settled)
    }

    @Test
    func `Waits for enough samples when simulator display callbacks are slow`() {
        var stability = ScreenSnapshotStability()
        let pixels = Data([1, 2, 3])

        #expect(stability.observe(pixels, at: 0) == .pending)
        #expect(stability.observe(pixels, at: 5) == .pending)
        #expect(stability.observe(pixels, at: 10) == .settled)
    }

    @Test
    func `Times out when pixels keep changing after the first frame`() {
        var stability = ScreenSnapshotStability()

        #expect(stability.observe(Data([1]), at: 10) == .pending)
        #expect(stability.observe(Data([2]), at: 13.9) == .pending)
        #expect(stability.observe(Data([3]), at: 14) == .timedOut)
    }

    @Test
    func `Requires two matching frames and a quiet interval after each change`() {
        var stability = ScreenSnapshotStability()
        let pixels = Data([1, 2, 3])

        #expect(stability.observe(Data([0]), at: 0) == .pending)
        #expect(stability.observe(pixels, at: 0.5) == .pending)
        #expect(stability.observe(pixels, at: 0.75) == .pending)
        #expect(stability.observe(pixels, at: 0.9) == .pending)
        #expect(stability.observe(pixels, at: 1) == .settled)
    }
}
