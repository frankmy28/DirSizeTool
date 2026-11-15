import SwiftUI
import UniformTypeIdentifiers
import Playgrounds

/// A folder the user has picked before and can scan again.
struct RecentFolder: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var path: String { url.path(percentEncoded: false) }
}

struct ContentView: View {
    @State private var recentFolders: [RecentFolder] = []
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
                    Button("Scan") {
                        // RecentFolder.ID is the folder's URL.
                        if let url = selection {
                            openWindow(id: ScanView.windowID, value: url)
                        }
                    }
                    .disabled(selection == nil)

                    Button("Clear History") {
                        recentFolders.removeAll()
                        selection = nil
                    }
                    .disabled(recentFolders.isEmpty)

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
                openWindow(id: ScanView.windowID, value: url)
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

    /// Recently used folders, followed by an entry to pick another folder.
    private var folderList: some View {
        List(selection: $selection) {
            ForEach(recentFolders) { folder in
                Label {
                    VStack(alignment: .leading) {
                        Text(folder.name)
                            .bold()
                        Text(folder.path)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.orange)
                }
            }

            Button {
                isPickingFolder = true
            } label: {
                VStack(alignment: .leading) {
                    Text("Scan folder...")
                        .bold()
                    Text("…")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .border(.separator)
    }

    /// Moves the picked folder to the top of the list and selects it.
    private func addRecentFolder(_ url: URL) {
        // Keep sandbox access open for the app's lifetime so the scan window can read the folder.
        _ = url.startAccessingSecurityScopedResource()

        let folder = RecentFolder(url: url)
        recentFolders.removeAll { $0 == folder }
        recentFolders.insert(folder, at: 0)
        selection = folder.id
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
