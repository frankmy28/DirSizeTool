import Foundation
import Observation

/// One directory in the scanned tree, with the total size of everything inside it.
@Observable
final class DirectoryNode: Identifiable {
    let url: URL
    let name: String

    /// Allocated size on disk of all files in this directory and its descendants.
    private(set) var size: Int64 = 0

    /// Subdirectories, ordered largest first.
    private(set) var subdirectories: [DirectoryNode] = []

    @ObservationIgnored private(set) weak var parent: DirectoryNode?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Children for the tree table; `nil` marks a leaf so no disclosure triangle is shown.
    var children: [DirectoryNode]? {
        subdirectories.isEmpty ? nil : subdirectories
    }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    func addSubdirectory(_ node: DirectoryNode) {
        node.parent = self
        subdirectories.append(node)
    }

    /// Adds `bytes` to this directory and all of its ancestors.
    /// Every parent whose child order may have changed is collected in `parents`.
    func add(bytes: Int64, touching parents: inout [ObjectIdentifier: DirectoryNode]) {
        var current: DirectoryNode? = self
        while let node = current {
            node.size += bytes
            if let parent = node.parent {
                parents[parent.id] = parent
            }
            current = node.parent
        }
    }

    /// Detaches this directory from the tree and subtracts its size from all ancestors.
    func removeFromParent(touching parents: inout [ObjectIdentifier: DirectoryNode]) {
        guard let parent else { return }
        parent.add(bytes: -size, touching: &parents)
        parent.subdirectories.removeAll { $0 === self }
        self.parent = nil
    }

    /// Orders subdirectories by size (largest first), then by name for a stable order.
    func sortSubdirectories() {
        subdirectories.sort { lhs, rhs in
            if lhs.size != rhs.size {
                return lhs.size > rhs.size
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
