import SnapshotTesting
import SwiftUI

private let precision: Float = 0.95

@MainActor
func assertScreenSnapshot<Screen: View>(
    testName: String, fileID: StaticString = #fileID, file filePath: StaticString = #filePath, line: UInt = #line,
    column: UInt = #column, compact: Bool = false, @ViewBuilder screen: () -> Screen
) {
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
            assertSnapshot(
                of: screen(),
                as: .image(
                    layout: compact ? .fixed(width: 390, height: 500) : .device(config: .iPhone13),
                    traits: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)),
                named: IOSSnapshotName.name(for: scheme, compact: compact), fileID: fileID,
                file: filePath, testName: testName, line: line,
                column: column)
        #endif
    }
}

#if os(iOS)
    private enum IOSSnapshotName {
        static func name(for scheme: ColorScheme, compact: Bool) -> String {
            if compact, ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 {
                return "iPhone-compact-iOS26-\(scheme)"
            }
            return compact ? "iPhone-compact-\(scheme)" : "iPhone-\(scheme)"
        }
    }
#endif

#if os(macOS)
    private enum MacOSSnapshotName {
        static func name(for scheme: ColorScheme, compact: Bool) -> String {
            if compact, scheme == .dark, ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 {
                return "compact-macOS26-dark"
            }
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
    ) -> NSHostingView<some View> {
        let backgroundColor = scheme == .dark ? Color.black : Color.white
        let hostingView = NSHostingView(
            rootView:
                screen
                .background(backgroundColor.ignoresSafeArea())
                .preferredColorScheme(scheme)
        )
        hostingView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: compact ? 560 : 1_280, height: compact ? 420 : 960)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor(backgroundColor).cgColor
        return hostingView
    }
#endif
