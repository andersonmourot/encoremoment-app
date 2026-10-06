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

/// Pinned tab header that collapses from the 28pt title row into a slim
/// centered title once the content beneath it scrolls — mirroring the
/// system large-title behavior.
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
            if collapsed {
                ZStack {
                    Text(title)
                        .font(.headline)
                    HStack {
                        Spacer()
                        actions
                    }
                    .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .padding(.vertical, 4)
            } else {
                TabHeader(title) { actions }
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

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Zero-height marker placed at the top of scrollable content. Pair with
/// `trackScrollOffset(_:)` on the containing scroll view to read how far
/// the content has scrolled.
struct ScrollSentinel: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetKey.self,
                value: geo.frame(in: .named("tabScroll")).minY
            )
        }
        .frame(height: 0)
    }
}

extension View {
    /// Reports the scroll offset of this scroll view to `binding`. Requires a
    /// `ScrollSentinel` at the top of the scrolled content.
    func trackScrollOffset(_ binding: Binding<CGFloat>) -> some View {
        coordinateSpace(name: "tabScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { binding.wrappedValue = $0 }
    }
}
