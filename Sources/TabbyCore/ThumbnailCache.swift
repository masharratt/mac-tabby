import Foundation

/// Byte-budgeted LRU cache of window thumbnails, keyed by window id. Pure: the value type is
/// generic so the app stores CGImages and tests store strings. Not thread-safe; callers lock.
public struct ThumbnailCache<Value> {
    public static var defaultBudget: Int { 64 * 1024 * 1024 }

    public enum StoreResult: Equatable, Sendable {
        /// Stored; `evicted` lists windows dropped (least recently used first) to make room.
        case stored(evicted: [UInt32])
        /// Larger than the whole budget; nothing changed.
        case rejectedOversize
        /// Captured while the window was off-screen and a cached image already exists; kept the old one.
        case rejectedUntrusted
    }

    private struct Entry {
        var value: Value
        var bytes: Int
        var trusted: Bool
        var stamp: UInt64
    }

    public let budget: Int
    public private(set) var totalBytes = 0
    private var entries: [UInt32: Entry] = [:]
    private var clock: UInt64 = 0

    public init(budget: Int = ThumbnailCache.defaultBudget) { self.budget = budget }

    /// RGBA, 4 bytes per pixel.
    public static func bytes(width: Int, height: Int) -> Int { max(width, 0) * max(height, 0) * 4 }

    /// Cached window ids, sorted.
    public var ids: [UInt32] { entries.keys.sorted() }

    /// Reading counts as use.
    public mutating func value(for id: UInt32) -> Value? {
        guard var e = entries[id] else { return nil }
        clock += 1
        e.stamp = clock
        entries[id] = e
        return e.value
    }

    @discardableResult
    public mutating func store(_ value: Value, bytes: Int, trusted: Bool, for id: UInt32) -> StoreResult {
        if !trusted, entries[id] != nil { return .rejectedUntrusted }
        guard bytes <= budget else { return .rejectedOversize }
        remove(id)
        var evicted: [UInt32] = []
        while totalBytes + bytes > budget, let lru = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key {
            remove(lru)
            evicted.append(lru)
        }
        clock += 1
        entries[id] = Entry(value: value, bytes: bytes, trusted: trusted, stamp: clock)
        totalBytes += bytes
        return .stored(evicted: evicted)
    }

    public mutating func remove(_ id: UInt32) {
        if let e = entries.removeValue(forKey: id) { totalBytes -= e.bytes }
    }

    /// Drops every window not in `live` (closed windows). Returns the dropped ids, sorted.
    @discardableResult
    public mutating func prune(keeping live: Set<UInt32>) -> [UInt32] {
        let gone = entries.keys.filter { !live.contains($0) }.sorted()
        gone.forEach { remove($0) }
        return gone
    }
}
