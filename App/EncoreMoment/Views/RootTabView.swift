import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }

            FollowingFeedView()
                .tabItem { Label("Following", systemImage: "person.2") }

            CreatorsView()
                .tabItem { Label("Creators", systemImage: "person.text.rectangle") }

            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    RootTabView().environmentObject(AppModel())
}
