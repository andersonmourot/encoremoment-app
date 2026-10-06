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

/// Tab header that scrolls away entirely once the content beneath it
/// scrolls — no slim title bar, the feed takes the full height.
struct CollapsingTabHeader<Actions: View>: View {
    let title: String
    let collapsed: Bool
    let actions: Actions

    init(_ title: String, collapsed: Bool, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.collapsed = collapsed
        self.actions = actions()
    }

    var body: some View {
        Group {
            if !collapsed {
                TabHeader(title) { actions }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: collapsed)
    }
}

extension CollapsingTabHeader where Actions == EmptyView {
    init(_ title: String, collapsed: Bool) {
        self.init(title, collapsed: collapsed) { EmptyView() }
    }
}

extension View {
    /// Reports how far this scroll view's content has scrolled past its
    /// resting top offset to `binding` — 0 at rest, positive when scrolled.
    /// Works on ScrollView and List.
    func trackScrollOffset(_ binding: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, new in
            binding.wrappedValue = new
        }
    }
}
