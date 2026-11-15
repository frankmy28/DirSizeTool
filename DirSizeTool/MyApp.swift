import SwiftUI

@main struct MyApp: App {
    @AppStorage(ScanView.showsFileListKey) private var showsFileList = true

    init() {
        #if os(macOS)
        // No window tabs: removes "Show Tab Bar" and "Show All Tabs" from the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

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
            // View menu: show or hide the file list below the directory tree in scan windows.
            CommandGroup(after: .toolbar) {
                Toggle("Show Files", isOn: $showsFileList)
                    .keyboardShortcut("y", modifiers: [.command, .shift])
            }
        }
        #else
        WindowGroup("Directory Size Tool") {
            ContentView()
        }
        #endif

        WindowGroup("Directory Size", id: ScanView.windowID, for: ScanRequest.self) { $request in
            if let request, request.isFromCurrentLaunch {
                ScanView(url: request.url, skipsRemoteDirectories: request.skipsRemoteDirectories)
            } else {
                // Restored by macOS from an earlier launch: close it, so only the main window shows at launch.
                StaleScanWindow()
            }
        }
        .defaultSize(width: 900, height: 700)
        // Scan windows are only opened via Scan; drop the automatic "New Directory Size Window" menu item.
        .commandsRemoved()
        // Don't reopen scan windows that were open when the app quit; launch with only the main window.
        .restorationBehavior(.disabled)
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
