import SwiftUI

@main
struct VideoCompressorApp: App {
    @State private var environment = AppEnvironment.shared

    init() {
        // Beim Start liegen gebliebene Share-Exports im
        // App-Group-Container aufräumen.
        TempFiles.purgeStaleSharedExports()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
