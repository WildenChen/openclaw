import Foundation

/// Validates a character asset file on disk without attempting a full decode.
/// Detection stays narrow: missing file, empty file, unsupported extension, or
/// wrong container magic. Anything outside `usable` lets the resolver fall back
/// instead of risking a half-rendered frame during chat.
struct SoulNestCharacterAssetFileValidator: Sendable {
    func status(of url: URL, kind: SoulNestCharacterAssetKind) -> SoulNestCharacterAssetFileStatus {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let sizeNumber = attributes[.size] as? Int, sizeNumber > 0
        else {
            return .empty
        }

        guard kind.isSupported(fileExtension: url.pathExtension) else { return .unsupportedFormat }

        guard let header = Self.readHeader(from: url, fileManager: fileManager) else { return .corrupt }
        return kind.matchesMagicBytes(header) ? .usable : .corrupt
    }

    private static func readHeader(from url: URL, fileManager: FileManager) -> Data? {
        guard fileManager.isReadableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return nil
        }
        defer { try? handle.close() }
        return try? handle.read(upToCount: 16)
    }
}

extension SoulNestCharacterAssetKind {
    /// First-byte signatures accepted for each kind. JPEG allows arbitrary bytes
    /// after `FF D8 FF`; for the others we look at a small, deterministic prefix
    /// (PNG), trailer (RIFF/WEBP), or offset box (ISO-BMFF `ftyp`).
    fileprivate func matchesMagicBytes(_ header: Data) -> Bool {
        switch self {
        case .staticImage:
            Self.isPNG(header) ||
                Self.isJPEG(header) ||
                Self.isGIF(header) ||
                Self.isWEBP(header)
        case .loopingVideo:
            Self.isISOBMFF(header)
        }
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data.starts(with: [0xFF, 0xD8, 0xFF])
    }

    private static func isGIF(_ data: Data) -> Bool {
        data.count >= 3 && data.starts(with: [0x47, 0x49, 0x46])
    }

    private static func isWEBP(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let riff = Data("RIFF".utf8)
        let webp = Data("WEBP".utf8)
        return data.prefix(4) == riff && data.subdata(in: 8..<12) == webp
    }

    private static func isISOBMFF(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let ftyp = Data("ftyp".utf8)
        return data.subdata(in: 4..<8) == ftyp
    }
}
