import SwiftUI

/// Content of the "Directory Size" window: a live tree table of directory sizes.
struct ScanView: View {
    /// Scene ID used to open this window with `openWindow(id:value:)`.
    static let windowID = "directory-size"
    /// `UserDefaults` key for whether the file list is shown; toggled from the View menu.
    static let showsFileListKey = "showsFileList"

    @State private var session: ScanSession
    @State private var isRootExpanded = true
    @State private var selection: DirectoryNode.ID?
    @State private var pendingDeletion: DirectoryNode?
    @State private var actionError: ActionError?
    @AppStorage(ScanView.showsFileListKey) private var showsFileList = true

    /// A failed context menu action, shown in an alert.
    private struct ActionError {
        let title: String
        let message: String
    }

    init(url: URL) {
        _session = State(initialValue: ScanSession(url: url))
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var isShowingActionError: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )
    }

    #if os(macOS)
    /// Opens a Finder window showing the directory's contents. Rooting the viewer at
    /// the path (instead of opening it) avoids launching packages such as `.app` bundles.
    private func showInFinder(_ node: DirectoryNode) {
        let path = node.url.path(percentEncoded: false)
        if !NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) {
            actionError = ActionError(
                title: "Could not show directory in Finder",
                message: "\"\(path)\" may no longer exist."
            )
        }
    }
    #endif

    /// Whether the table is currently sorted by the column showing `keyPath`.
    private func isSorted(by keyPath: PartialKeyPath<DirectoryNode>) -> Bool {
        session.sortOrder.first?.keyPath == keyPath
    }

    private func delete(_ node: DirectoryNode) {
        do {
            try session.moveToTrash(node)
            if selection == node.id {
                selection = nil
            }
        } catch {
            actionError = ActionError(
                title: "Could not delete directory",
                message: error.localizedDescription
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            VSplitView {
                directoryTable
                    .frame(minHeight: 150)
                if showsFileList {
                    fileList
                        .frame(minHeight: 100)
                }
            }
            #else
            directoryTable
            if showsFileList {
                Divider()
                fileList
            }
            #endif

            if session.status == .scanning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                    Button("Abort") {
                        session.abort()
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Same setting as View > Show Files; a toggle is shown highlighted while on.
                Toggle(isOn: $showsFileList) {
                    Label("Show Files", systemImage: "rectangle.bottomthird.inset.filled")
                }
                .help(showsFileList ? "Hide Files" : "Show Files")
            }
        }
        .task {
            session.start()
        }
        .onDisappear {
            session.abort()
        }
    }

    /// Files of the directory selected in the tree table.
    private var fileList: some View {
        FileListView(directory: selection.flatMap(session.node(withID:)), session: session)
    }

    /// Tree table of all scanned directories and their sizes.
    private var directoryTable: some View {
        Table(of: DirectoryNode.self, selection: $selection, sortOrder: $session.sortOrder) {
            TableColumn(
                Text("Directory").bold(isSorted(by: \.name)),
                value: \.name,
                comparator: .localizedStandard
            ) { node in
                NameCell(node: node)
            }
            TableColumn(Text("Size").bold(isSorted(by: \.size)), value: \.size) { node in
                SizeCell(node: node)
            }
            .width(min: 80, ideal: 120, max: 200)
        } rows: {
            DisclosureTableRow(session.root, isExpanded: $isRootExpanded) {
                OutlineGroup(session.root.subdirectories, children: \.children)
            }
        }
        .contextMenu(forSelectionType: DirectoryNode.ID.self) { ids in
            if ids.count == 1,
               let id = ids.first,
               let node = session.node(withID: id) {
                #if os(macOS)
                Button("Show in Finder") {
                    showInFinder(node)
                }
                #endif

                // Deleting the scanned root itself is not offered.
                if node !== session.root {
                    Divider()
                    Button("Delete directory \(node.name)", role: .destructive) {
                        pendingDeletion = node
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete directory \(pendingDeletion?.name ?? "")?",
            isPresented: isConfirmingDeletion,
            presenting: pendingDeletion
        ) { node in
            Button("Move to Trash", role: .destructive) {
                delete(node)
            }
        } message: { node in
            Text("\"\(node.url.path(percentEncoded: false))\" (\(node.size.formatted(.byteCount(style: .file)))) will be moved to the Trash.")
        }
        .alert(
            actionError?.title ?? "",
            isPresented: isShowingActionError,
            presenting: actionError
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.message)
        }
    }

    private var title: String {
        switch session.status {
        case .scanning:
            if let path = session.currentPath {
                "Scanning \(path)…"
            } else {
                "Scanning…"
            }
        case .complete: rootPath
        case .incomplete: "\(rootPath) (Scan aborted)"
        }
    }

    private var rootPath: String {
        session.root.url.path(percentEncoded: false)
    }
}

/// Directory name with the same icon Finder shows for it (including custom
/// folder icons and package icons such as apps).
private struct NameCell: View {
    let node: DirectoryNode

    var body: some View {
        Label {
            Text(node.name)
        } icon: {
            #if os(macOS)
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
            #else
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            #endif
        }
    }
}

/// Size cell as its own view: reading `node.size` in this body makes SwiftUI
/// observe it, so the cell redraws as the size grows. Table doesn't reliably
/// re-evaluate column closures when only a row object's properties change.
private struct SizeCell: View {
    let node: DirectoryNode

    var body: some View {
        Group {
            if node.isScanned {
                Text(node.size, format: .byteCount(style: .file, spellsOutZero: false))
            } else {
                Text("?")
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
