import SwiftUI

/// Content of the "Directory Size" window: a live tree table of directory sizes.
struct ScanView: View {
    /// Scene ID used to open this window with `openWindow(id:value:)`.
    static let windowID = "directory-size"

    @State private var session: ScanSession
    @State private var isRootExpanded = true
    @State private var selection: DirectoryNode.ID?
    @State private var pendingDeletion: DirectoryNode?
    @State private var deletionError: String?

    init(url: URL) {
        _session = State(initialValue: ScanSession(url: url))
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var isShowingDeletionError: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )
    }

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
            deletionError = error.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                // Offer deletion for a single directory, but not for the scanned root itself.
                if ids.count == 1,
                   let id = ids.first,
                   let node = session.node(withID: id),
                   node !== session.root {
                    Button("Delete directory \(node.name)", role: .destructive) {
                        pendingDeletion = node
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
                "Could not delete directory",
                isPresented: isShowingDeletionError,
                presenting: deletionError
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }

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
        .task {
            session.start()
        }
        .onDisappear {
            session.abort()
        }
    }

    private var title: String {
        let status = switch session.status {
        case .scanning: "Scanning…"
        case .complete: "Complete"
        case .incomplete: "Incomplete"
        }
        return "DirSizeTool – Directory Size – \(status)"
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
        Text(node.size, format: .byteCount(style: .file))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
