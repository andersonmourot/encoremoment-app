import SwiftUI

/// Compact tab-root header: a 28pt bold title with optional trailing actions.
/// Used in place of the navigation bar on tab roots so headers stay small.
struct TabHeader<Actions: View>: View {
    let title: String
    let actions: Actions

    init(_ title: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
            Spacer(minLength: 0)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

extension TabHeader where Actions == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
