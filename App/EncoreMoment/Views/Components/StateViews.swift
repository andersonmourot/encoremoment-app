import SwiftUI

/// Renders the right state for a data-backed screen: a loading indicator on the
/// first load, an error state with Retry when loading failed and there is nothing
/// to show, the provided empty state when there is no data, otherwise the content.
struct AsyncContentView<Content: View, Empty: View>: View {
    let isLoading: Bool
    let hasLoaded: Bool
    let isEmpty: Bool
    let errorMessage: String?
    let retry: () async -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var empty: () -> Empty

    var body: some View {
        if let errorMessage, isEmpty {
            ErrorStateView(message: errorMessage, retry: retry)
        } else if isEmpty && (isLoading || !hasLoaded) {
            LoadingStateView()
        } else if isEmpty {
            empty()
        } else {
            content()
        }
    }
}

/// Centered spinner used while a screen loads for the first time.
struct LoadingStateView: View {
    var label = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-screen error state with a Retry button.
struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isRetrying = true
                Task {
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Try Again").bold()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shimmer

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.4)
                .offset(x: geo.size.width * phase)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
    }
}

extension View {
    /// Adds an animated shimmer sweep — used on image placeholders while loading.
    func shimmering() -> some View { modifier(Shimmer()) }
}

#Preview("Loading") { LoadingStateView() }
#Preview("Error") { ErrorStateView(message: "The network connection was lost.") {} }
