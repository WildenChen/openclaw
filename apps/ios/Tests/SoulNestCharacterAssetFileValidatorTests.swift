import XCTest
@testable import OpenClaw

final class SoulNestCharacterAssetFileValidatorTests: XCTestCase {
    private var tempDir: URL!
    private var validator: SoulNestCharacterAssetFileValidator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("soulnest-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.tempDir, withIntermediateDirectories: true)
        self.validator = SoulNestCharacterAssetFileValidator()
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    func testMissingFileReportsMissing() {
        let url = self.tempDir.appendingPathComponent("nope.png")
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .missing)
    }

    func testEmptyFileReportsEmpty() throws {
        let url = self.tempDir.appendingPathComponent("empty.png")
        try Data().write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .empty)
    }

    func testUnsupportedExtensionReportsUnsupportedFormat() throws {
        let url = self.tempDir.appendingPathComponent("clip.gif")
        try Data([0x47, 0x49, 0x46, 0x38]).write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .unsupportedFormat)
    }

    func testValidPNGHeaderReportsUsable() throws {
        let url = self.tempDir.appendingPathComponent("ok.png")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0x00, count: 64)
        try png.write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .usable)
    }

    func testCorruptHeaderReportsCorrupt() throws {
        let url = self.tempDir.appendingPathComponent("broken.png")
        try Data(repeating: 0xAA, count: 64).write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .corrupt)
    }

    func testJPEGHeaderReportsUsable() throws {
        let url = self.tempDir.appendingPathComponent("ok.jpg")
        var data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        data.append(Data(repeating: 0x00, count: 64))
        try data.write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .usable)
    }

    func testWEBPHeaderReportsUsable() throws {
        let url = self.tempDir.appendingPathComponent("ok.webp")
        var data = Data("RIFF".utf8)
        data.append(Data([0x10, 0x00, 0x00, 0x00]))
        data.append(Data("WEBP".utf8))
        data.append(Data(repeating: 0x00, count: 32))
        try data.write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .staticImage), .usable)
    }

    func testMP4ContainerReportsUsable() throws {
        let url = self.tempDir.appendingPathComponent("ok.mp4")
        var data = Data(repeating: 0x00, count: 4)
        data.append(Data("ftyp".utf8))
        data.append(Data("mp42".utf8))
        data.append(Data(repeating: 0x00, count: 16))
        try data.write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .loopingVideo), .usable)
    }

    func testCorruptMP4ContainerReportsCorrupt() throws {
        let url = self.tempDir.appendingPathComponent("broken.mp4")
        try Data(repeating: 0xAA, count: 64).write(to: url)
        XCTAssertEqual(self.validator.status(of: url, kind: .loopingVideo), .corrupt)
    }
}
