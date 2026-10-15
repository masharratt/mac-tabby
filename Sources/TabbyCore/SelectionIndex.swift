/// Pure index math for the switcher list.
public enum SelectionIndex {
    public static func next(_ i: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (i + 1) % count
    }

    public static func previous(_ i: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (i - 1 + count) % count
    }

    /// Where the selection lands when the switcher arms. Index 0 is the current window, so
    /// "next" lands on 1 and "previous" on the last one. A single window selects itself.
    public static func initial(count: Int, reverse: Bool) -> Int {
        guard count > 1 else { return 0 }
        return reverse ? count - 1 : 1
    }

    /// The slice of rows to draw when only `capacity` rows fit. Always contains `selected`
    /// and is as close to centered on it as the list bounds allow.
    public static func visibleRange(count: Int, selected: Int, capacity: Int) -> Range<Int> {
        guard count > 0, capacity > 0 else { return 0..<0 }
        if count <= capacity { return 0..<count }
        let sel = min(max(selected, 0), count - 1)
        let start = min(max(sel - capacity / 2, 0), count - capacity)
        return start..<(start + capacity)
    }

    /// Number of items left after removing `removed` (duplicates and out-of-range indices ignored).
    public static func remainingCount(count: Int, removed: Set<Int>) -> Int {
        count - removed.filter { (0..<count).contains($0) }.count
    }

    /// Where the selection lands after items are removed in place. A surviving selection keeps
    /// pointing at the same item; a removed selection moves to the item that took its place, or
    /// the new last item when it was at the end. Nil when nothing is left.
    public static func afterRemoval(selected: Int, removed: Set<Int>, count: Int) -> Int? {
        let valid = removed.filter { (0..<count).contains($0) }
        let left = count - valid.count
        guard left > 0 else { return nil }
        let before = valid.filter { $0 < selected }.count
        return min(max(selected - before, 0), left - 1)
    }
}
