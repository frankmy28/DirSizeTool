import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup("Directory Size Tool") {
            ContentView()
        }
        .windowResizability(.contentSize)

        WindowGroup("Directory Size", id: ScanView.windowID, for: URL.self) { $url in
            if let url {
                ScanView(url: url)
            }
        }
        .defaultSize(width: 900, height: 700)
    }
}
