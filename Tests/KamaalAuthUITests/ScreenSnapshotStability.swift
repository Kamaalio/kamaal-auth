import Foundation

struct ScreenSnapshotStability {
    enum Outcome {
        case pending
        case settled
        case timedOut
    }

    private var previousPixels: Data?
    private var matchingFrames = 0
    private(set) var firstFrameAt: TimeInterval?
    private(set) var lastChangeAt: TimeInterval = 0
    private(set) var frameCount = 0

    mutating func observe(_ pixels: Data, at time: TimeInterval) -> Outcome {
        frameCount += 1
        if firstFrameAt == nil { firstFrameAt = time }
        if pixels == previousPixels {
            matchingFrames += 1
        } else {
            matchingFrames = 0
            lastChangeAt = time
        }
        previousPixels = pixels

        // Evaluate the sample before the deadline: a delayed callback can
        // still prove that the screen is stable.
        if matchingFrames >= 2, time - lastChangeAt >= 0.5 { return .settled }
        if frameCount >= 3, let firstFrameAt, time - firstFrameAt >= 4 { return .timedOut }
        return .pending
    }
}
