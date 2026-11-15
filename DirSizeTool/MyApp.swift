import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        #if os(macOS)
        // A single main window (not a WindowGroup), so closing it is unambiguous.
        Window("Directory Size Tool", id: "main") {
            ContentView()
                .onDisappear {
                    // Closing the main window quits the app, including open scan windows.
                    NSApplication.shared.terminate(nil)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Directory Size Tool") {
                    showAboutPanel()
                }
            }
        }
        #else
        WindowGroup("Directory Size Tool") {
            ContentView()
        }
        #endif

        WindowGroup("Directory Size", id: ScanView.windowID, for: URL.self) { $url in
            if let url {
                ScanView(url: url)
            }
        }
        .defaultSize(width: 900, height: 700)
        // Scan windows are only opened via Scan; drop the automatic "New Directory Size Window" menu item.
        .commandsRemoved()
    }

    #if os(macOS)
    /// Shows the standard About panel with the main window's icon.
    /// The copyright line comes from `NSHumanReadableCopyright` in the Info.plist.
    private func showAboutPanel() {
        let renderer = ImageRenderer(content: AppIconView().frame(width: 64, height: 64))
        renderer.scale = 2

        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let icon = renderer.nsImage {
            options[.applicationIcon] = icon
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSApplication.shared.activate()
    }
    #endif
}
