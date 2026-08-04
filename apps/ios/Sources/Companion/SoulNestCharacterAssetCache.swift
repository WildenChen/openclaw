import Foundation

/// Bounded cache for character asset resources. Tracks byte budget and last
/// access time per key so the renderer can answer "is this resource resident?"
/// without touching disk. Real byte loading stays in the rendering layer; this
/// is the data-layer contract.
struct SoulNestCharacterAssetCache: Equatable, Sendable {
    enum EvictionPolicy: String, Codable, Sendable {
        case leastRecentlyUsed
    }

    struct Entry: Equatable, Sendable {
        let key: String
        let byteSize: Int
        var lastAccessedAt: Date
    }

    private(set) var maxBytes: Int
    private(set) var entries: [String: Entry]
    var evictionPolicy: EvictionPolicy

    init(maxBytes: Int, evictionPolicy: EvictionPolicy = .leastRecentlyUsed) {
        precondition(maxBytes >= 0)
        self.maxBytes = maxBytes
        self.evictionPolicy = evictionPolicy
        self.entries = [:]
    }

    var currentBytes: Int {
        self.entries.values.reduce(0) { $0 + $1.byteSize }
    }

    var isOverCapacity: Bool {
        self.currentBytes > self.maxBytes
    }

    var count: Int {
        self.entries.count
    }

    func contains(_ key: String) -> Bool {
        self.entries[key] != nil
    }

    /// Records a preloaded resource. Returns false when a single resource
    /// exceeds the cache budget, so callers can skip oversized entries without
    /// mutating the cache.
    @discardableResult
    mutating func preload(
        resource: SoulNestCharacterAssetResource,
        now: Date = Date()) -> Bool
    {
        guard resource.byteSize <= self.maxBytes else { return false }
        self.evict(toFit: resource.byteSize)
        self.entries[resource.id] = Entry(
            key: resource.id,
            byteSize: resource.byteSize,
            lastAccessedAt: now)
        return true
    }

    mutating func touch(key: String, now: Date = Date()) {
        guard var entry = self.entries[key] else { return }
        entry.lastAccessedAt = now
        self.entries[key] = entry
    }

    mutating func evictLeastRecentlyUsed() {
        guard let oldestKey = self.entries
            .min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key
        else { return }
        self.entries.removeValue(forKey: oldestKey)
    }

    mutating func clear() {
        self.entries.removeAll()
    }

    private mutating func evict(toFit incomingBytes: Int) {
        while self.currentBytes + incomingBytes > self.maxBytes,
              let oldest = self.entries
                  .min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
        {
            self.entries.removeValue(forKey: oldest.key)
        }
    }
}
