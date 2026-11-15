import SwiftUI
import UniformTypeIdentifiers
import Playgrounds

struct ContentView: View {
    @State private var store = RecentFolderStore()
    @State private var selection: RecentFolder.ID?
    @State private var isPickingFolder = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 20) {
            appInfo
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                folderList

                HStack {
                    // Pick a folder, then scan it.
                    Button("Scan...") {
                        isPickingFolder = true
                    }

                    Button("Clear History") {
                        store.clear()
                        selection = nil
                    }
                    .disabled(store.folders.isEmpty)

                    Spacer()

                    HelpLink {
                        // Help content is not available yet.
                    }
                }
            }
            .frame(width: 240)
        }
        .padding(20)
        .frame(width: 500, height: 340)
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                addRecentFolder(url)
                // The picker's confirmation button is labeled "Scan", so start scanning right away.
                scan(url)
            }
        }
        .fileDialogConfirmationLabel("Scan")
    }

    /// App icon, name and short description on the left side.
    private var appInfo: some View {
        VStack(spacing: 12) {
            AppIconView()
                .frame(width: 140, height: 140)

            Text("Helps you to free up space on your drives")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }

    /// Recently used folders; new folders are picked with the "Scan..." button.
    private var folderList: some View {
        List(selection: $selection) {
            ForEach(store.folders) { folder in
                Label {
                    VStack(alignment: .leading) {
                        Text(folder.name)
                            .bold()
                        Text(folder.isAvailable ? folder.path : "Not available – \(folder.path)")
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.orange)
                }
                // Folders that couldn't be found at launch can't be selected or scanned.
                .opacity(folder.isAvailable ? 1 : 0.5)
                .selectionDisabled(!folder.isAvailable)
            }
        }
        .listStyle(.plain)
        .border(.separator)
        // No context menu; the primary action handles double-clicking a folder, same as Scan.
        .contextMenu(forSelectionType: RecentFolder.ID.self) { _ in
        } primaryAction: { ids in
            if let url = ids.first {
                scan(url)
            }
        }
    }

    /// Opens a "Directory Size" window that scans the folder.
    private func scan(_ url: URL) {
        openWindow(id: ScanView.windowID, value: url)
    }

    /// Moves the picked folder to the top of the list and selects it.
    private func addRecentFolder(_ url: URL) {
        selection = store.add(url)
    }
}

/// The app's icon as shown in the main window; also rendered for the About panel.
struct AppIconView: View {
    var body: some View {
        Image(systemName: "square.stack.3d.up.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.blue.gradient)
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
