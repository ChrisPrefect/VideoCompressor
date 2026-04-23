import SwiftUI

/// Root der Haupt-App. Konstruiert das LibraryViewModel mit den geteilten
/// Services aus dem AppEnvironment.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        LibraryScreen(viewModel: LibraryViewModel(
            library: environment.library,
            authorization: environment.authorization,
            statistics: environment.statistics,
            settings: environment.settings,
            presets: environment.presets
        ))
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.shared)
}
