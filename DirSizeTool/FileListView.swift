import SwiftUI

/// A regular file directly inside a directory, read on demand for the file list.
nonisolated struct FileEntry: Identifiable, Sendable {
    let url: URL
    let name: String
    /// Allocated size on disk, measured the same way as by `DirectoryScanner`.
    let size: Int64
    /// Last content modification; `.distantPast` if the file system doesn't report one,
    /// so the value stays sortable.
    let modificationDate: Date

    var id: URL { url }
}

/// Reads the files (not subdirectories) directly inside one directory.
nonisolated enum FileLister {
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .contentModificationDateKey,
    ]

    /// Symbolic links are skipped, matching the scanner, so the sizes add up to the
    /// directory's own file bytes. Returns an empty list if the directory can't be read.
    @concurrent
    static func files(in directoryURL: URL) async -> [FileEntry] {
        let keySet = Set(resourceKeys)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys
        )) ?? []

        var files: [FileEntry] = []
        for entry in entries {
            if Task.isCancelled { return [] }
            guard let values = try? entry.resourceValues(forKeys: keySet),
                  values.isSymbolicLink != true,
                  values.isDirectory != true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            files.append(FileEntry(
                url: entry,
                name: entry.lastPathComponent,
                size: Int64(size),
                modificationDate: values.contentModificationDate ?? .distantPast
            ))
        }
        return files
    }
}

/// Files directly inside the directory selected in the tree table.
/// They are read when the selection changes, so scanning doesn't keep any file in memory.
struct FileListView: View {
    let directory: DirectoryNode?
    let session: ScanSession

    @State private var files: [FileEntry] = []
    @State private var isLoading = false
    @State private var selection: FileEntry.ID?
    @State private var sortOrder: [KeyPathComparator<FileEntry>] = [KeyPathComparator(\.size, order: .reverse)]
    @State private var pendingDeletion: FileEntry?
    @State private var actionError: ActionError?

    @Environment(\.openURL) private var openURL

    /// A failed context menu action, shown in an alert.
    private struct ActionError {
        let title: String
        let message: String
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

    /// Whether the table is currently sorted by the column showing `keyPath`.
    private func isSorted(by keyPath: PartialKeyPath<FileEntry>) -> Bool {
        sortOrder.first?.keyPath == keyPath
    }

    /// Orders files by `sortOrder`, falling back to the name for a stable order.
    private func sorted(_ files: [FileEntry]) -> [FileEntry] {
        files.sorted { lhs, rhs in
            for comparator in sortOrder {
                let result = comparator.compare(lhs, rhs)
                if result != .orderedSame {
                    return result == .orderedAscending
                }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func file(withID id: FileEntry.ID) -> FileEntry? {
        files.first { $0.id == id }
    }

    #if os(macOS)
    private func showInFinder(_ file: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    #endif

    /// Opens the file in its default application, like double-clicking it in Finder.
    private func open(_ file: FileEntry) {
        #if os(macOS)
        // SwiftUI's `openURL` is meant for web links and doesn't reliably open local
        // files on macOS; NSWorkspace launches the default app and reports why it failed.
        Task {
            do {
                try await NSWorkspace.shared.open(file.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                actionError = ActionError(title: "Could not open file", message: error.localizedDescription)
            }
        }
        #else
        openURL(file.url) { accepted in
            if !accepted {
                actionError = ActionError(
                    title: "Could not open file",
                    message: "No application can open \"\(file.name)\"."
                )
            }
        }
        #endif
    }

    private func delete(_ file: FileEntry) {
        guard let directory else { return }
        do {
            try session.moveToTrash(file, in: directory)
            files.removeAll { $0.id == file.id }
            if selection == file.id {
                selection = nil
            }
        } catch {
            actionError = ActionError(
                title: "Could not delete file",
                message: error.localizedDescription
            )
        }
    }

    var body: some View {
        Table(of: FileEntry.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(
                Text("File").bold(isSorted(by: \.name)),
                value: \.name,
                comparator: .localizedStandard
            ) { file in
                FileNameCell(file: file)
            }
            TableColumn(Text("Date Modified").bold(isSorted(by: \.modificationDate)), value: \.modificationDate) { file in
                if file.modificationDate != .distantPast {
                    Text(file.modificationDate, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .monospacedDigit()
                }
            }
            .width(min: 120, ideal: 160, max: 220)
            TableColumn(Text("Size").bold(isSorted(by: \.size)), value: \.size) { file in
                Text(file.size, format: .byteCount(style: .file, spellsOutZero: false))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 120, max: 200)
        } rows: {
            ForEach(files) { file in
                TableRow(file)
            }
        }
        .overlay {
            if directory == nil {
                ContentUnavailableView("No Directory Selected", systemImage: "folder")
            } else if isLoading {
                ProgressView()
            } else if files.isEmpty {
                ContentUnavailableView("No Files", systemImage: "doc")
            }
        }
        .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
            if ids.count == 1,
               let id = ids.first,
               let file = file(withID: id) {
                Button("Open") {
                    open(file)
                }

                #if os(macOS)
                Button("Show in Finder") {
                    showInFinder(file)
                }
                Divider()
                #endif

                Button("Delete file \(file.name)", role: .destructive) {
                    pendingDeletion = file
                }
                // Until the scan has counted this directory, its size can't be corrected.
                .disabled(directory?.isScanned != true)
            }
        } primaryAction: { ids in
            // Double-click (or Return) opens the file.
            if ids.count == 1, let id = ids.first, let file = file(withID: id) {
                open(file)
            }
        }
        .confirmationDialog(
            "Delete file \(pendingDeletion?.name ?? "")?",
            isPresented: isConfirmingDeletion,
            presenting: pendingDeletion
        ) { file in
            Button("Move to Trash", role: .destructive) {
                delete(file)
            }
        } message: { file in
            Text("\"\(file.url.path(percentEncoded: false))\" (\(file.size.formatted(.byteCount(style: .file)))) will be moved to the Trash.")
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
        .onChange(of: sortOrder) {
            files = sorted(files)
        }
        // Restarts (and cancels any running read) whenever another directory is selected.
        .task(id: directory?.id) {
            selection = nil
            files = []
            isLoading = false
            guard let url = directory?.url else { return }
            isLoading = true
            let loaded = await FileLister.files(in: url)
            guard !Task.isCancelled else { return }
            files = sorted(loaded)
            isLoading = false
        }
    }
}

/// File name with the icon Finder shows for it.
private struct FileNameCell: View {
    let file: FileEntry

    var body: some View {
        Label {
            Text(file.name)
        } icon: {
            #if os(macOS)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
            #else
            Image(systemName: "doc")
            #endif
        }
    }
}
