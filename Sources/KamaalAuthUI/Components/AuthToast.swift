import KamaalPopUp
import SwiftUI

protocol ToastPresentable: Equatable {
    var title: String { get }
    var message: String { get }
}

struct Toast: Equatable, ToastPresentable {
    let title: String
    let message: String
}

extension View {
    func authToast<T: ToastPresentable>(_ toast: T?, dismiss: @escaping () -> Void) -> some View {
        modifier(
            AuthToastModifier(
                isPresented: Binding(get: { toast != nil }, set: { isPresented in if !isPresented { dismiss() } }),
                style: .bottom(title: toast?.title ?? "", type: .error, description: toast?.message)
            ))
    }
}

private struct AuthToastModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isPresented: Binding<Bool>
    let style: KPopUpStyles

    func body(content: Content) -> some View {
        content.kPopUpLite(
            isPresented: isPresented, style: style, backgroundColor: colorScheme == .dark ? .black : .white)
    }
}
