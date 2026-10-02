/// Bounded cache of rendered frames, keyed like the prototype's `sprite()` cache:
/// (look, pose, frame, highlight). Least-recently-used entries are evicted past `capacity`
/// (docs/design/sprites-and-poses.md#done-when). Not thread-safe: use it from one actor.
public final class SpriteCache {
    struct Key: Hashable { let look: Look; let pose: Pose; let frame: Int; let highlight: Bool }
    private struct Entry { let canvas: PixelCanvas; var lastUse: UInt64 }

    public let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    public private(set) var hits = 0, misses = 0

    public init(capacity: Int = Limits.spriteCache) { self.capacity = max(1, capacity) }

    public var count: Int { entries.count }

    public func sprite(_ look: Look, _ pose: Pose, frame: Int, highlight: Bool) -> PixelCanvas {
        let n = pose.frameCount
        let key = Key(look: look, pose: pose, frame: ((frame % n) + n) % n, highlight: highlight)
        clock &+= 1
        if var e = entries[key] {
            hits += 1
            e.lastUse = clock
            entries[key] = e
            return e.canvas
        }
        misses += 1
        let canvas = SpriteRenderer.render(look, pose, frame: key.frame, highlight: highlight)
        if entries.count >= capacity { evict() }
        entries[key] = Entry(canvas: canvas, lastUse: clock)
        return canvas
    }

    /// Drops the least recently used quarter, so eviction cost is amortised over many inserts.
    private func evict() {
        let drop = max(1, capacity / 4)
        let oldest = entries.sorted { $0.value.lastUse < $1.value.lastUse }.prefix(drop)
        for (k, _) in oldest { entries[k] = nil }
    }
}
