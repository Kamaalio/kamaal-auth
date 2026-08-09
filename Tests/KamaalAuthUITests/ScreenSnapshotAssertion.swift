import SnapshotTesting
import SwiftUI

private let precision: Float = 0.95

@MainActor
func assertScreenSnapshot<Screen: View>(
    testName: String, fileID: StaticString = #fileID, file filePath: StaticString = #filePath, line: UInt = #line,
    column: UInt = #column, @ViewBuilder screen: () -> Screen
) {
    for scheme in [ColorScheme.light, .dark] {
        #if os(macOS)
            assertSnapshot(
                of: makeMacOSScreen(screen: screen(), scheme: scheme),
                as: .image(precision: precision), named: "\(scheme)", fileID: fileID,
                file: filePath, testName: testName, line: line, column: column)
        #elseif os(iOS)
            assertSnapshot(
                of: screen(),
                as: .image(
                    layout: .device(config: .iPhone13),
                    traits: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)),
                named: "iPhone-\(scheme)", fileID: fileID, file: filePath, testName: testName, line: line,
                column: column)
        #endif
    }
}

#if os(macOS)
    @MainActor
    private func makeMacOSScreen<Screen: View>(screen: Screen, scheme: ColorScheme) -> NSHostingView<some View> {
        let backgroundColor = scheme == .dark ? Color.black : Color.white
        let hostingView = NSHostingView(
            rootView:
                screen
                .background(backgroundColor.ignoresSafeArea())
                .preferredColorScheme(scheme)
        )
        hostingView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_280, height: 960)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor(backgroundColor).cgColor
        return hostingView
    }
#endif
