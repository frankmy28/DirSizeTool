import Foundation
import Observation

/// A change discovered by the scanner. Directories are referenced by numeric IDs
/// because the scanner runs off the main actor and can't touch `DirectoryNode`s.
nonisolated enum ScanEvent: Sendable {
    /// A new subdirectory `id` was found inside `parentID`.
    case directory(id: Int, parentID: Int, url: URL)
    /// Files directly inside directory `id` occupy `bytes` on disk.
    case bytes(id: Int, bytes: Int64)
}

/// Walks a directory tree in the background and reports what it finds in batches.
nonisolated struct DirectoryScanner {
    /// ID of the root directory in all events.
    static let rootID = 0

    let rootURL: URL

    /// How often collected events are sent to the UI.
    private let flushInterval: Duration = .milliseconds(200)

    private let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
    ]

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Scans depth-first until finished or the surrounding task is cancelled.
    /// Symbolic links are not followed; unreadable directories are skipped.
    @concurrent
    func scan(send: @escaping @Sendable ([ScanEvent]) async -> Void) async {
        let fileManager = FileManager.default
        let keySet = Set(resourceKeys)
        let clock = ContinuousClock()

        var pending: [ScanEvent] = []
        var lastFlush = clock.now
        var nextID = Self.rootID + 1
        var stack: [(id: Int, url: URL)] = [(Self.rootID, rootURL)]

        while let (directoryID, directoryURL) = stack.popLast() {
            if Task.isCancelled { return }

            let entries = (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: resourceKeys
            )) ?? []

            var fileBytes: Int64 = 0
            for entry in entries {
                if Task.isCancelled { return }
                guard let values = try? entry.resourceValues(forKeys: keySet),
                      values.isSymbolicLink != true else { continue }

                if values.isDirectory == true {
                    let id = nextID
                    nextID += 1
                    pending.append(.directory(id: id, parentID: directoryID, url: entry))
                    stack.append((id, entry))
                } else {
                    let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
                    fileBytes += Int64(size)
                }
            }

            if fileBytes > 0 {
                pending.append(.bytes(id: directoryID, bytes: fileBytes))
            }

            // Batch events so the main actor isn't flooded with tiny updates.
            if !pending.isEmpty, clock.now - lastFlush >= flushInterval {
                await send(pending)
                pending.removeAll(keepingCapacity: true)
                lastFlush = clock.now
            }
        }

        if !pending.isEmpty, !Task.isCancelled {
            await send(pending)
        }
    }
}

/// Runs one scan and applies its results to a `DirectoryNode` tree for the UI.
@Observable
final class ScanSession {
    enum Status {
        case scanning, complete, incomplete
    }

    let root: DirectoryNode
    private(set) var status: Status = .scanning

    @ObservationIgnored private var nodesByID: [Int: DirectoryNode]
    /// Lookup from table row IDs back to nodes, e.g. for context menu actions.
    @ObservationIgnored private var nodesByRowID: [DirectoryNode.ID: DirectoryNode]
    @ObservationIgnored private var task: Task<Void, Never>?

    init(url: URL) {
        let root = DirectoryNode(url: url)
        self.root = root
        self.nodesByID = [DirectoryScanner.rootID: root]
        self.nodesByRowID = [root.id: root]
    }

    func node(withID id: DirectoryNode.ID) -> DirectoryNode? {
        nodesByRowID[id]
    }

    /// Moves the directory to the Trash and removes it from the tree.
    func moveToTrash(_ node: DirectoryNode) throws {
        try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)

        var touchedParents: [ObjectIdentifier: DirectoryNode] = [:]
        node.removeFromParent(touching: &touchedParents)
        for parent in touchedParents.values {
            parent.sortSubdirectories()
        }
    }

    func start() {
        guard task == nil else { return }
        let scanner = DirectoryScanner(rootURL: root.url)
        task = Task { [weak self] in
            await scanner.scan { [weak self] batch in
                await self?.apply(batch)
            }
            guard let self, status == .scanning else { return }
            status = .complete
        }
    }

    func abort() {
        guard status == .scanning else { return }
        task?.cancel()
        status = .incomplete
    }

    private func apply(_ batch: [ScanEvent]) {
        guard status == .scanning else { return }

        var touchedParents: [ObjectIdentifier: DirectoryNode] = [:]
        for event in batch {
            switch event {
            case let .directory(id, parentID, url):
                guard let parent = nodesByID[parentID] else { continue }
                let node = DirectoryNode(url: url)
                parent.addSubdirectory(node)
                nodesByID[id] = node
                nodesByRowID[node.id] = node
                touchedParents[parent.id] = parent
            case let .bytes(id, bytes):
                nodesByID[id]?.add(bytes: bytes, touching: &touchedParents)
            }
        }

        // Re-sort once per batch instead of once per event.
        for parent in touchedParents.values {
            parent.sortSubdirectories()
        }
    }
}
