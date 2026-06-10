// ZipReader.swift
//
// Minimal pure-Swift ZIP archive reader. Enough to extract NAMED
// files out of a .docx / .pptx — which are both ZIP-packaged XML.
// We do NOT implement compression (only decompression), encryption,
// or the streaming API; we read a small archive that already fits
// in memory.
//
// Why a custom reader (and not a third-party library)
// ───────────────────────────────────────────────────
// Apple's `Compression` framework gives us DEFLATE on iOS, but the
// public Foundation API does NOT include a ZIP archive parser. The
// alternatives (ZIPFoundation, Zip, etc.) would each add a SwiftPM
// dependency that fights the project's "vendored, zero-dependency"
// posture inherited from the Android side. ~180 lines of pure
// Swift here keep the iOS port as self-contained as the Android
// app already is.
//
// What it supports
//   - DEFLATE-compressed entries (the only method DOCX / PPTX use
//     in practice).
//   - STORE entries (uncompressed). Some apps emit these for tiny
//     XML pieces inside an OOXML archive.
//   - ZIP64 is NOT supported. DOCX / PPTX of any realistic size
//     stay under the 4 GB ZIP32 limit — orders of magnitude
//     larger than the 60-page documents iOS targets.
//
// Format references (for the curious maintainer):
//   - APPNOTE.TXT from PKWARE, sections 4.3.7 (Local File Header)
//     and 4.3.16 (End of Central Directory Record).

import Foundation
import Compression

enum ZipError: Error, LocalizedError {
    case notAZip
    case truncated
    case entryNotFound(String)
    case unsupportedMethod(UInt16)
    case archiveTooLarge(Int64)
    case entryTooLarge(String, UInt32)
    case tooManyEntries(Int)
    case expandedArchiveTooLarge(UInt64)
    case suspiciousCompression(String)
    case duplicateEntry(String)
    case invalidEntryName
    case directoryCountMismatch(expected: Int, actual: Int)
    case decompressedSizeMismatch(expected: Int, actual: Int)
    case decompressFailed

    var errorDescription: String? {
        switch self {
        case .notAZip:                  return "Not a ZIP file."
        case .truncated:                return "ZIP file is truncated."
        case .entryNotFound(let name):  return "Entry not found: \(name)"
        case .unsupportedMethod(let m): return "Unsupported compression method: \(m)"
        case .archiveTooLarge(let bytes): return "Archive is too large to process safely (\(bytes) bytes)."
        case .entryTooLarge(let name, let bytes): return "Archive entry is too large: \(name) (\(bytes) bytes)."
        case .tooManyEntries(let count): return "Archive contains too many entries (\(count))."
        case .expandedArchiveTooLarge(let bytes): return "Expanded archive is too large to process safely (\(bytes) bytes)."
        case .suspiciousCompression(let name): return "Archive entry has a suspicious compression ratio: \(name)."
        case .duplicateEntry(let name): return "Archive contains a duplicate entry: \(name)."
        case .invalidEntryName:         return "Archive contains an invalid entry name."
        case .directoryCountMismatch(let expected, let actual):
            return "Archive directory count mismatch (expected \(expected), found \(actual))."
        case .decompressedSizeMismatch(let expected, let actual):
            return "Decompressed size mismatch (expected \(expected), found \(actual))."
        case .decompressFailed:         return "Decompression failed."
        }
    }
}

struct ZipReader {

    private static let maximumArchiveBytes: Int64 = 256 * 1_024 * 1_024
    private static let maximumEntryBytes: UInt32 = 64 * 1_024 * 1_024
    private static let maximumEntryCount = 20_000
    private static let maximumExpandedBytes: UInt64 = 512 * 1_024 * 1_024
    private static let maximumCompressionRatio: UInt64 = 500

    private let data: Data
    private let entries: [String: Entry]

    private struct Entry {
        let method: UInt16          // 0 = stored, 8 = deflate
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= Self.maximumArchiveBytes else {
            throw ZipError.archiveTooLarge(byteCount)
        }
        let raw = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: raw)
    }

    init(data: Data) throws {
        guard Int64(data.count) <= Self.maximumArchiveBytes else {
            throw ZipError.archiveTooLarge(Int64(data.count))
        }
        self.data = data
        self.entries = try Self.scanCentralDirectory(data)
    }

    /// Names of every file in the archive (no order guarantees).
    var fileNames: [String] { Array(entries.keys) }

    /// Returns the decompressed bytes for `name`, or throws if the
    /// entry isn't in the archive.
    func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw ZipError.entryNotFound(name)
        }
        guard entry.uncompressedSize <= Self.maximumEntryBytes else {
            throw ZipError.entryTooLarge(name, entry.uncompressedSize)
        }
        return try decompress(entry)
    }

    /// Returns true when the archive contains an entry called `name`.
    func contains(_ name: String) -> Bool { entries[name] != nil }

    // MARK: - Central Directory scan

    private static let sigEOCD: UInt32 = 0x06054b50
    private static let sigCDFH: UInt32 = 0x02014b50
    private static let sigLFH:  UInt32 = 0x04034b50

    private static func scanCentralDirectory(_ data: Data) throws -> [String: Entry] {
        guard data.count >= 22 else { throw ZipError.truncated }
        // End-of-central-directory has a max comment size of 0xFFFF,
        // so it lives in the last 65557 bytes. Scan backwards for
        // the signature.
        let startSearch = max(0, data.count - 22 - 65535)
        var eocdOffset: Int? = nil
        for i in stride(from: data.count - 22, through: startSearch, by: -1) {
            if data.readUInt32LE(at: i) == sigEOCD {
                eocdOffset = i
                break
            }
        }
        guard let eocd = eocdOffset else { throw ZipError.notAZip }

        guard eocd + 22 <= data.count else { throw ZipError.truncated }
        let diskNumber = data.readUInt16LE(at: eocd + 4)
        let directoryDisk = data.readUInt16LE(at: eocd + 6)
        let entriesOnDisk = data.readUInt16LE(at: eocd + 8)
        let totalEntries = data.readUInt16LE(at: eocd + 10)
        let commentLength = Int(data.readUInt16LE(at: eocd + 20))
        guard diskNumber == 0, directoryDisk == 0, entriesOnDisk == totalEntries,
              eocd + 22 + commentLength <= data.count else {
            throw ZipError.truncated
        }
        guard Int(totalEntries) <= maximumEntryCount else {
            throw ZipError.tooManyEntries(Int(totalEntries))
        }
        let cdSize       = data.readUInt32LE(at: eocd + 12)
        let cdOffset     = Int(data.readUInt32LE(at: eocd + 16))
        guard cdOffset >= 0, Int(cdSize) <= data.count - cdOffset,
              cdOffset + Int(cdSize) <= eocd else {
            throw ZipError.truncated
        }

        var map: [String: Entry] = [:]
        map.reserveCapacity(Int(totalEntries))

        var p = cdOffset
        let cdEnd = cdOffset + Int(cdSize)
        var declaredExpandedBytes: UInt64 = 0
        var scannedRecords = 0
        while p < cdEnd {
            scannedRecords += 1
            guard scannedRecords <= maximumEntryCount else {
                throw ZipError.tooManyEntries(scannedRecords)
            }
            guard p + 46 <= cdEnd, p + 46 <= data.count else {
                throw ZipError.truncated
            }
            guard data.readUInt32LE(at: p) == sigCDFH else {
                throw ZipError.truncated
            }
            let method           = data.readUInt16LE(at: p + 10)
            let compressedSize   = data.readUInt32LE(at: p + 20)
            let uncompressedSize = data.readUInt32LE(at: p + 24)
            let nameLen          = Int(data.readUInt16LE(at: p + 28))
            let extraLen         = Int(data.readUInt16LE(at: p + 30))
            let commentLen       = Int(data.readUInt16LE(at: p + 32))
            let localOffset      = data.readUInt32LE(at: p + 42)

            let nameStart = p + 46
            let nameEnd = nameStart + nameLen
            let recordEnd = nameEnd + extraLen + commentLen
            guard nameEnd <= data.count, recordEnd <= cdEnd else {
                throw ZipError.truncated
            }
            guard let name = String(data: data.subdata(in: nameStart..<nameEnd),
                                    encoding: .utf8), !name.contains("\0") else {
                throw ZipError.invalidEntryName
            }

            // Directories end with "/" and have zero-byte content;
            // skip them to keep the map small.
            if !name.hasSuffix("/") && !name.isEmpty {
                guard map[name] == nil else { throw ZipError.duplicateEntry(name) }
                guard uncompressedSize <= maximumEntryBytes else {
                    throw ZipError.entryTooLarge(name, uncompressedSize)
                }
                declaredExpandedBytes += UInt64(uncompressedSize)
                guard declaredExpandedBytes <= maximumExpandedBytes else {
                    throw ZipError.expandedArchiveTooLarge(declaredExpandedBytes)
                }
                if uncompressedSize > 1_024 * 1_024 {
                    let denominator = max(UInt64(compressedSize), 1)
                    guard UInt64(uncompressedSize) / denominator <= maximumCompressionRatio else {
                        throw ZipError.suspiciousCompression(name)
                    }
                }
                map[name] = Entry(method: method,
                                  compressedSize: compressedSize,
                                  uncompressedSize: uncompressedSize,
                                  localHeaderOffset: localOffset)
            }
            p = recordEnd
        }
        guard scannedRecords == Int(totalEntries) else {
            throw ZipError.directoryCountMismatch(expected: Int(totalEntries), actual: scannedRecords)
        }
        return map
    }

    // MARK: - Per-entry decompression

    private func decompress(_ entry: Entry) throws -> Data {
        let lfhOffset = Int(entry.localHeaderOffset)
        guard lfhOffset + 30 <= data.count,
              data.readUInt32LE(at: lfhOffset) == Self.sigLFH else {
            throw ZipError.truncated
        }
        // The LFH name + extra length can differ from the CDFH ones
        // (some packers normalise differently), so we read them again
        // here to find the actual compressed-payload offset.
        let lfhNameLen  = Int(data.readUInt16LE(at: lfhOffset + 26))
        let lfhExtraLen = Int(data.readUInt16LE(at: lfhOffset + 28))
        guard lfhNameLen <= data.count - (lfhOffset + 30),
              lfhExtraLen <= data.count - (lfhOffset + 30 + lfhNameLen) else {
            throw ZipError.truncated
        }
        let payloadStart = lfhOffset + 30 + lfhNameLen + lfhExtraLen
        guard Int(entry.compressedSize) <= data.count - payloadStart else {
            throw ZipError.truncated
        }
        let payloadEnd = payloadStart + Int(entry.compressedSize)

        let payload = data.subdata(in: payloadStart..<payloadEnd)
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else {
                throw ZipError.truncated
            }
            return payload
        case 8:
            return try Self.inflate(payload,
                                     expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    /// DEFLATE → raw bytes via Apple's Compression framework.
    private static func inflate(_ src: Data, expectedSize: Int) throws -> Data {
        // Buffer slightly above the declared uncompressed size; some
        // packers under-report by a byte or two.
        let cap = max(expectedSize + 16, 4096)
        var dst = Data(count: cap)
        let written = src.withUnsafeBytes { srcRaw -> Int in
            dst.withUnsafeMutableBytes { dstRaw -> Int in
                guard let srcPtr = srcRaw.baseAddress?
                        .assumingMemoryBound(to: UInt8.self),
                      let dstPtr = dstRaw.baseAddress?
                        .assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    dstPtr, cap,
                    srcPtr, srcRaw.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        if expectedSize == 0, written == 0 { return Data() }
        guard written > 0 else { throw ZipError.decompressFailed }
        guard written == expectedSize else {
            throw ZipError.decompressedSizeMismatch(expected: expectedSize, actual: written)
        }
        dst.removeSubrange(written..<dst.count)
        return dst
    }
}

// MARK: - Little-endian helpers

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return b0 | (b1 << 8)
    }
    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
