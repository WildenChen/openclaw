import XCTest
@testable import OpenClaw

final class SoulNestCharacterAssetCacheTests: XCTestCase {
    private func resource(id: String, bytes: Int) -> SoulNestCharacterAssetResource {
        SoulNestCharacterAssetResource(
            id: id,
            kind: .staticImage,
            resourceName: "res",
            fileExtension: "png",
            byteSize: bytes,
            sha256: nil,
            license: nil)
    }

    func testEmptyCacheHasZeroBytes() {
        let cache = SoulNestCharacterAssetCache(maxBytes: 1024)
        XCTAssertEqual(cache.currentBytes, 0)
        XCTAssertFalse(cache.isOverCapacity)
        XCTAssertEqual(cache.count, 0)
    }

    func testPreloadStoresEntryWithinBudget() {
        var cache = SoulNestCharacterAssetCache(maxBytes: 1024)
        XCTAssertTrue(cache.preload(resource: self.resource(id: "idle", bytes: 256)))
        XCTAssertEqual(cache.currentBytes, 256)
        XCTAssertTrue(cache.contains("idle"))
        XCTAssertEqual(cache.count, 1)
    }

    func testPreloadRejectsSingleOversizedResource() {
        var cache = SoulNestCharacterAssetCache(maxBytes: 1024)
        XCTAssertFalse(cache.preload(resource: self.resource(id: "huge", bytes: 4096)))
        XCTAssertEqual(cache.currentBytes, 0)
        XCTAssertFalse(cache.contains("huge"))
    }

    func testPreloadEvictsLeastRecentlyUsedWhenOverBudget() {
        var cache = SoulNestCharacterAssetCache(maxBytes: 1000)
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertTrue(cache.preload(resource: self.resource(id: "old", bytes: 400), now: date))
        XCTAssertTrue(cache.preload(resource: self.resource(id: "mid", bytes: 400), now: date.addingTimeInterval(10)))
        XCTAssertTrue(cache.preload(resource: self.resource(id: "new", bytes: 400), now: date.addingTimeInterval(20)))

        XCTAssertEqual(cache.currentBytes, 800)
        XCTAssertFalse(cache.contains("old"))
        XCTAssertTrue(cache.contains("mid"))
        XCTAssertTrue(cache.contains("new"))
    }

    func testTouchMakesEntryNewestForEvictionOrder() {
        var cache = SoulNestCharacterAssetCache(maxBytes: 600)
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertTrue(cache.preload(resource: self.resource(id: "old", bytes: 200), now: date))
        XCTAssertTrue(cache.preload(resource: self.resource(id: "mid", bytes: 200), now: date.addingTimeInterval(10)))
        XCTAssertTrue(cache.preload(resource: self.resource(id: "new", bytes: 200), now: date.addingTimeInterval(20)))

        cache.touch(key: "old", now: date.addingTimeInterval(30))

        XCTAssertTrue(cache.preload(
            resource: self.resource(id: "incoming", bytes: 200),
            now: date.addingTimeInterval(40)))

        XCTAssertFalse(cache.contains("mid"))
        XCTAssertTrue(cache.contains("old"))
        XCTAssertTrue(cache.contains("new"))
        XCTAssertTrue(cache.contains("incoming"))
    }

    func testClearRemovesAllEntries() {
        var cache = SoulNestCharacterAssetCache(maxBytes: 1024)
        XCTAssertTrue(cache.preload(resource: self.resource(id: "idle", bytes: 100)))
        XCTAssertTrue(cache.preload(resource: self.resource(id: "talking", bytes: 100)))
        XCTAssertEqual(cache.count, 2)

        cache.clear()
        XCTAssertEqual(cache.currentBytes, 0)
        XCTAssertEqual(cache.count, 0)
    }

    func testEvictLeastRecentlyUsedRemovesOldestEntry() {
        var cache = SoulNestCharacterAssetCache(maxBytes: 1024)
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(cache.preload(resource: self.resource(id: "first", bytes: 100), now: date))
        XCTAssertTrue(cache.preload(resource: self.resource(id: "second", bytes: 100), now: date.addingTimeInterval(5)))

        cache.evictLeastRecentlyUsed()
        XCTAssertFalse(cache.contains("first"))
        XCTAssertTrue(cache.contains("second"))
    }
}
