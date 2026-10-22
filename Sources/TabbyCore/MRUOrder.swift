/// Most-recently-used ordering of window ids. Pure: the app feeds it focus changes.
public struct MRUOrder: Sendable, Equatable {
    /// Upper bound on remembered ids. Closed windows are never pruned explicitly: a window can drop
    /// out of one listing and come back, and window ids are not reused, so stale ids are harmless.
    public static let capacity = 512

    /// Most recent first.
    public private(set) var order: [UInt32]

    /// `seed` is most recent first (front-to-back z-order at launch).
    public init(seed: [UInt32] = []) {
        var seen = Set<UInt32>()
        order = seed.filter { seen.insert($0).inserted }
        if order.count > Self.capacity { order.removeLast(order.count - Self.capacity) }
    }

    public mutating func focused(_ id: UInt32) {
        if let i = order.firstIndex(of: id) { order.remove(at: i) }
        order.insert(id, at: 0)
        if order.count > Self.capacity { order.removeLast(order.count - Self.capacity) }
    }

    /// Known windows by recency, then windows never seen focused in their incoming order.
    /// Windows absent from `windows` (closed) never appear.
    public func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        var rank: [UInt32: Int] = [:]
        for (i, id) in order.enumerated() { rank[id] = i }
        let known = windows.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        let unknown = windows.filter { rank[$0.id] == nil }
        return known + unknown
    }
}
