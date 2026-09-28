import SnapshotTesting
import SwiftUI
import Testing

private let precision: Float = 0.95

@MainActor
func assertScreenSnapshot<Screen: View>(
    testName: String, fileID: StaticString = #fileID, file filePath: StaticString = #filePath, line: UInt = #line,
    column: UInt = #column, compact: Bool = false, @ViewBuilder screen: () -> Screen
) async {
    await ScreenSnapshotQueue.acquire()
    defer { ScreenSnapshotQueue.release() }

    for scheme in [ColorScheme.light, .dark] {
        #if os(macOS)
            let hostingView = makeMacOSScreen(screen: screen(), scheme: scheme, compact: compact)
            let window =
                compact
                ? NSWindow(contentRect: hostingView.frame, styleMask: [], backing: .buffered, defer: false)
                : nil
            window?.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window?.contentView = hostingView
            window?.displayIfNeeded()
            if compact { MacOSSnapshotScroll.waitUntilScrolledToBottom(in: hostingView) }
            assertSnapshot(
                of: hostingView,
                as: .image(precision: precision), named: MacOSSnapshotName.name(for: scheme, compact: compact),
                fileID: fileID,
                file: filePath, testName: testName, line: line, column: column)
        #elseif os(iOS)
            let capture = MountedScreenSnapshot(screen: screen(), scheme: scheme, compact: compact)
            guard let image = await capture.image() else {
                Issue.record(
                    "The mounted screen did not settle within four seconds.",
                    sourceLocation: SourceLocation(
                        fileID: "\(fileID)", filePath: "\(filePath)", line: Int(line), column: Int(column)))
                return
            }
            assertSnapshot(
                of: image, as: .image,
                named: compact ? "iPhone-compact-\(scheme)" : "iPhone-\(scheme)",
                fileID: fileID, file: filePath, testName: testName, line: line, column: column)
        #endif
    }
}

// Swift Testing runs suites concurrently. Keep each mounted hierarchy and both
// appearance comparisons exclusive within a test process.
@MainActor
private enum ScreenSnapshotQueue {
    private static var isCapturing = false
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    static func acquire() async {
        if !isCapturing {
            isCapturing = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    static func release() {
        guard !waiting.isEmpty else {
            isCapturing = false
            return
        }
        waiting.removeFirst().resume()
    }
}

#if os(iOS)
    @MainActor
    private final class MountedScreenSnapshot: NSObject {
        private let window: ScreenSnapshotWindow
        private let controller: UIViewController
        private let hosting: UIViewController
        private let traits: UITraitCollection
        private var previousImage: Data?
        private var matchingFrames = 0
        private var lastImageChange: CFTimeInterval = 0
        private var completion: CheckedContinuation<UIImage?, Never>?
        private var deadline: CFTimeInterval = 0

        init<Screen: View>(screen: Screen, scheme: ColorScheme, compact: Bool) {
            let config =
                compact
                ? ViewImageConfig(size: CGSize(width: 390, height: 500), traits: ViewImageConfig.iPhone13.traits)
                : ViewImageConfig.iPhone13
            traits = config.traits.modifyingTraits {
                $0.userInterfaceStyle = scheme == .dark ? .dark : .light
                $0.activeAppearance = .active
            }
            window = ScreenSnapshotWindow(config: config)
            hosting = UIHostingController(rootView: screen)
            controller = UIViewController()
            super.init()

            // UIKit controls also resolve appearance through their window.
            // Pin it before mounting so host settings cannot change their symbols.
            window.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
            window.traitOverrides.activeAppearance = traits.activeAppearance
            controller.view.backgroundColor = .clear
            controller.view.frame = window.bounds
            hosting.view.frame = window.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.addChild(hosting)
            controller.view.addSubview(hosting.view)
            hosting.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
            hosting.traitOverrides.activeAppearance = traits.activeAppearance
            hosting.traitOverrides.horizontalSizeClass = traits.horizontalSizeClass
            hosting.traitOverrides.verticalSizeClass = traits.verticalSizeClass
            hosting.traitOverrides.userInterfaceIdiom = traits.userInterfaceIdiom
            hosting.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
            hosting.traitOverrides.layoutDirection = traits.layoutDirection
            hosting.traitOverrides.forceTouchCapability = traits.forceTouchCapability
            hosting.didMove(toParent: controller)
            window.rootViewController = controller
            window.isHidden = false
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
        }

        func image() async -> UIImage? {
            deadline = CACurrentMediaTime() + 4
            return await withCheckedContinuation { completion in
                self.completion = completion
                let displayLink = CADisplayLink(target: self, selector: #selector(captureFrame))
                displayLink.add(to: .main, forMode: .common)
            }
        }

        // Observe one mounted hierarchy instead of restarting SwiftUI and UIKit
        // initialization on each frame. The reference never participates in settling.
        @objc private func captureFrame(_ displayLink: CADisplayLink) {
            guard CACurrentMediaTime() < deadline else {
                finish(displayLink, image: nil)
                return
            }
            let view = hosting.view!
            view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: .init(for: traits))
            let image = renderer.image { view.layer.render(in: $0.cgContext) }
            guard let data = image.pngData() else {
                finish(displayLink, image: nil)
                return
            }
            if data == previousImage {
                matchingFrames += 1
            } else {
                matchingFrames = 0
                lastImageChange = CACurrentMediaTime()
            }
            previousImage = data
            // Native controls can pause between their initial image and entrance fade.
            // A quiet interval spans that pause; any changed pixel restarts it.
            guard matchingFrames >= 2, CACurrentMediaTime() - lastImageChange >= 0.5 else { return }
            finish(displayLink, image: image)
        }

        private func finish(_ displayLink: CADisplayLink, image: UIImage?) {
            displayLink.invalidate()
            controller.beginAppearanceTransition(false, animated: false)
            controller.endAppearanceTransition()
            window.isHidden = true
            window.rootViewController = nil
            guard let completion else { preconditionFailure("A screen capture must have a waiting assertion.") }
            self.completion = nil
            completion.resume(returning: image)
        }
    }

    private final class ScreenSnapshotWindow: UIWindow {
        private let config: ViewImageConfig

        init(config: ViewImageConfig) {
            self.config = config
            guard let size = config.size else { preconditionFailure("Screen snapshots require a fixed device size.") }
            super.init(frame: CGRect(origin: .zero, size: size))
        }

        required init?(coder: NSCoder) {
            fatalError("Screen snapshot windows require a device configuration.")
        }

        override var safeAreaInsets: UIEdgeInsets { config.safeArea }
    }
#endif

#if os(macOS)
    // Keep bitmap dimensions independent of the host display scale.
    private final class SnapshotHostingView<Content: View>: NSHostingView<Content> {
        var bitmapScale: CGFloat = 2

        override func bitmapImageRepForCachingDisplay(in rect: NSRect) -> NSBitmapImageRep? {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(rect.width * bitmapScale),
                pixelsHigh: Int(rect.height * bitmapScale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
            bitmap?.size = rect.size
            return bitmap
        }
    }

    private enum MacOSSnapshotName {
        static func name(for scheme: ColorScheme, compact: Bool) -> String {
            return compact ? "compact-\(scheme)" : "\(scheme)"
        }
    }

    @MainActor
    private enum MacOSSnapshotScroll {
        static func waitUntilScrolledToBottom(in view: NSView) {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if let scrollView = firstScrollView(in: view), let documentView = scrollView.documentView {
                    let maxOffset = documentView.bounds.height - scrollView.contentView.bounds.height
                    if maxOffset > 0, scrollView.contentView.bounds.minY >= maxOffset - 0.5 { return }
                }
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }

        private static func firstScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView { return scrollView }
            for subview in view.subviews {
                if let scrollView = firstScrollView(in: subview) { return scrollView }
            }
            return nil
        }
    }

    @MainActor
    private func makeMacOSScreen<Screen: View>(
        screen: Screen, scheme: ColorScheme, compact: Bool
    ) -> SnapshotHostingView<some View> {
        let backgroundColor = scheme == .dark ? Color.black : Color.white
        let hostingView = SnapshotHostingView(
            rootView:
                screen
                .background(backgroundColor.ignoresSafeArea())
                .preferredColorScheme(scheme)
        )
        hostingView.bitmapScale = compact ? 1 : 2
        hostingView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: compact ? 560 : 1_280, height: compact ? 420 : 960)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor(backgroundColor).cgColor
        return hostingView
    }
#endif
