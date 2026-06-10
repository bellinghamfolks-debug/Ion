import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Minimal ZIP writer using the STORE method. DOCX readers accept uncompressed ZIP entries,
/// which avoids third-party dependencies and keeps the project buildable offline.
struct ZipArchiveWriter {
    struct Entry {
        let path: String
        let data: Data
        let crc32: UInt32
        let localOffset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private(set) var data = Data()
    private var entries: [Entry] = []
    private var isFinalized = false

    mutating func add(path: String, data entryData: Data, date: Date = Date()) throws {
        guard !isFinalized else { throw ZipError.alreadyFinalized }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !components.contains(where: { $0 == ".." || $0.isEmpty }),
              entries.contains(where: { $0.path == path }) == false,
              let nameData = path.data(using: .utf8),
              nameData.count <= Int(UInt16.max) else {
            throw ZipError.invalidPath
        }
        let localHeaderSize = 30 + nameData.count
        let maximum = Int(UInt32.max)
        guard entryData.count <= maximum,
              data.count <= maximum,
              localHeaderSize <= maximum - data.count,
              entryData.count <= maximum - data.count - localHeaderSize else {
            throw ZipError.archiveTooLarge
        }

        let crc = CRC32.checksum(entryData)
        let (dosTime, dosDate) = Self.dosDateTime(date)
        let offset = UInt32(data.count)

        data.appendLE(UInt32(0x04034b50))
        data.appendLE(UInt16(20))
        data.appendLE(UInt16(0x0800))
        data.appendLE(UInt16(0))
        data.appendLE(dosTime)
        data.appendLE(dosDate)
        data.appendLE(crc)
        data.appendLE(UInt32(entryData.count))
        data.appendLE(UInt32(entryData.count))
        data.appendLE(UInt16(nameData.count))
        data.appendLE(UInt16(0))
        data.append(nameData)
        data.append(entryData)

        entries.append(Entry(path: path, data: entryData, crc32: crc, localOffset: offset, dosTime: dosTime, dosDate: dosDate))
    }

    mutating func finalize() throws -> Data {
        guard !isFinalized else { throw ZipError.alreadyFinalized }
        let maximum = Int(UInt32.max)
        let centralBytes = entries.reduce(22) { partial, entry in
            partial + 46 + (entry.path.data(using: .utf8)?.count ?? 0)
        }
        guard entries.count <= Int(UInt16.max),
              data.count <= maximum,
              centralBytes <= maximum - data.count else {
            throw ZipError.archiveTooLarge
        }
        let centralStart = UInt32(data.count)

        for entry in entries {
            guard let nameData = entry.path.data(using: .utf8) else { throw ZipError.invalidPath }
            data.appendLE(UInt32(0x02014b50))
            data.appendLE(UInt16(20))
            data.appendLE(UInt16(20))
            data.appendLE(UInt16(0x0800))
            data.appendLE(UInt16(0))
            data.appendLE(entry.dosTime)
            data.appendLE(entry.dosDate)
            data.appendLE(entry.crc32)
            data.appendLE(UInt32(entry.data.count))
            data.appendLE(UInt32(entry.data.count))
            data.appendLE(UInt16(nameData.count))
            data.appendLE(UInt16(0))
            data.appendLE(UInt16(0))
            data.appendLE(UInt16(0))
            data.appendLE(UInt16(0))
            data.appendLE(UInt32(0))
            data.appendLE(entry.localOffset)
            data.append(nameData)
        }

        let centralSize = UInt32(data.count) - centralStart
        data.appendLE(UInt32(0x06054b50))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(entries.count))
        data.appendLE(UInt16(entries.count))
        data.appendLE(centralSize)
        data.appendLE(centralStart)
        data.appendLE(UInt16(0))
        isFinalized = true
        return data
    }

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, components.year ?? 1980))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))

        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, dosDate)
    }
}

enum ZipError: LocalizedError {
    case invalidPath
    case archiveTooLarge
    case alreadyFinalized

    var errorDescription: String? {
        switch self {
        case .invalidPath: return L10n.text("اسم ملف داخلي غير صالح أثناء إنشاء DOCX.")
        case .archiveTooLarge: return L10n.text("حجم ملف DOCX تجاوز الحد المدعوم في هذه النسخة.")
        case .alreadyFinalized: return L10n.text("تم إغلاق حزمة DOCX ولا يمكن تعديلها مرة أخرى.")
        }
    }
}

private enum CRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}


enum DOCXPackageValidator {
    private static let requiredEntries: Set<String> = [
        "[Content_Types].xml",
        "_rels/.rels",
        "docProps/core.xml",
        "docProps/app.xml",
        "word/document.xml",
        "word/styles.xml",
        "word/settings.xml",
        "word/numbering.xml",
        "word/_rels/document.xml.rels"
    ]

    static func validate(url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 22 else { throw DOCXValidationError.truncatedArchive }
        let entries = try readStoredEntries(from: data)
        let names = Set(entries.keys)
        let missing = requiredEntries.subtracting(names)
        guard missing.isEmpty else {
            throw DOCXValidationError.missingEntries(missing.sorted())
        }

        for (name, payload) in entries where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            let parser = XMLParser(data: payload)
            guard parser.parse() else {
                throw DOCXValidationError.invalidXML(name, parser.parserError?.localizedDescription ?? L10n.text("خطأ XML غير معروف"))
            }
        }

        try validateRelationshipGraph(entries: entries)
        try validateContentTypes(entries: entries)
        try validateMedia(entries: entries)
        try validateCentralDirectory(in: data, localEntries: entries)
    }

    private static func readStoredEntries(from archive: Data) throws -> [String: Data] {
        var offset = 0
        var entries: [String: Data] = [:]

        while offset + 4 <= archive.count {
            let signature = try archive.readUInt32LE(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 { break }
            guard signature == 0x04034b50 else {
                throw DOCXValidationError.invalidLocalHeader(offset)
            }
            guard offset + 30 <= archive.count else { throw DOCXValidationError.truncatedArchive }

            let method = try archive.readUInt16LE(at: offset + 8)
            guard method == 0 else { throw DOCXValidationError.unsupportedCompression(method) }
            let expectedCRC = try archive.readUInt32LE(at: offset + 14)
            let compressedSize = Int(try archive.readUInt32LE(at: offset + 18))
            let uncompressedSize = Int(try archive.readUInt32LE(at: offset + 22))
            let nameLength = Int(try archive.readUInt16LE(at: offset + 26))
            let extraLength = Int(try archive.readUInt16LE(at: offset + 28))
            guard compressedSize == uncompressedSize else {
                throw DOCXValidationError.sizeMismatch
            }

            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + compressedSize
            guard nameEnd <= archive.count, dataEnd <= archive.count else {
                throw DOCXValidationError.truncatedArchive
            }
            guard let name = String(data: archive[nameStart..<nameEnd], encoding: .utf8), !name.isEmpty else {
                throw DOCXValidationError.invalidEntryName
            }
            guard entries[name] == nil else { throw DOCXValidationError.duplicateEntry(name) }

            let payload = Data(archive[dataStart..<dataEnd])
            guard CRC32.checksum(payload) == expectedCRC else {
                throw DOCXValidationError.crcMismatch(name)
            }
            entries[name] = payload
            offset = dataEnd
        }
        return entries
    }

    private static func validateRelationshipGraph(entries: [String: Data]) throws {
        let relationshipParts = [
            (path: "_rels/.rels", source: ""),
            (path: "word/_rels/document.xml.rels", source: "word/document.xml")
        ]

        var documentRelationships: [String: String] = [:]
        for part in relationshipParts {
            guard let data = entries[part.path] else {
                throw DOCXValidationError.missingEntries([part.path])
            }
            let relationships = try parseRelationships(data: data, name: part.path)
            var ids = Set<String>()
            for relationship in relationships {
                guard ids.insert(relationship.id).inserted else {
                    throw DOCXValidationError.duplicateRelationshipID(part.path, relationship.id)
                }
                if relationship.targetMode?.lowercased() == "external" {
                    // Word hyperlinks are legitimate external relationships. Permit only
                    // explicit hyperlink relationships with web/mail schemes, and never
                    // treat their URL as an internal package path.
                    guard part.path == "word/_rels/document.xml.rels",
                          relationship.type.hasSuffix("/hyperlink"),
                          isAllowedExternalHyperlink(relationship.target) else {
                        throw DOCXValidationError.externalRelationship(part.path, relationship.target)
                    }
                    documentRelationships[relationship.id] = "external:\(relationship.target)"
                    continue
                }
                let resolved = try resolveTarget(sourcePart: part.source, target: relationship.target)
                guard entries[resolved] != nil else {
                    throw DOCXValidationError.missingRelationshipTarget(part.path, relationship.target)
                }
                if part.path == "word/_rels/document.xml.rels" {
                    documentRelationships[relationship.id] = resolved
                }
            }
        }

        guard let document = entries["word/document.xml"] else {
            throw DOCXValidationError.missingEntries(["word/document.xml"])
        }
        let references = try parseRelationshipReferences(data: document, name: "word/document.xml")
        for reference in references where documentRelationships[reference] == nil {
            throw DOCXValidationError.missingRelationshipID("word/document.xml", reference)
        }
    }

    private static func isAllowedExternalHyperlink(_ target: String) -> Bool {
        guard target.count <= 4_096,
              let components = URLComponents(string: target),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return false }
        if scheme == "http" || scheme == "https" {
            return components.host?.isEmpty == false
        }
        return !target.dropFirst("mailto:".count).isEmpty
    }

    private static func validateContentTypes(entries: [String: Data]) throws {
        guard let data = entries["[Content_Types].xml"] else {
            throw DOCXValidationError.missingEntries(["[Content_Types].xml"])
        }
        let delegate = ContentTypesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DOCXValidationError.invalidXML(
                "[Content_Types].xml",
                parser.parserError?.localizedDescription ?? L10n.text("خطأ XML غير معروف")
            )
        }
        guard delegate.overrides.contains("/word/document.xml") else {
            throw DOCXValidationError.missingDocumentContentType
        }
        let hasPNG = entries.keys.contains { $0.lowercased().hasPrefix("word/media/") && $0.lowercased().hasSuffix(".png") }
        if hasPNG, !delegate.defaultExtensions.contains("png") {
            throw DOCXValidationError.missingPNGContentType
        }
    }

    private static func validateMedia(entries: [String: Data]) throws {
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        for (name, payload) in entries where name.lowercased().hasPrefix("word/media/") {
            guard name.lowercased().hasSuffix(".png"), payload.starts(with: pngSignature) else {
                throw DOCXValidationError.invalidMedia(name)
            }
        }
    }

    private static func parseRelationships(data: Data, name: String) throws -> [PackageRelationship] {
        let delegate = RelationshipsDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DOCXValidationError.invalidXML(name, parser.parserError?.localizedDescription ?? L10n.text("خطأ XML غير معروف"))
        }
        return delegate.relationships
    }

    private static func parseRelationshipReferences(data: Data, name: String) throws -> Set<String> {
        let delegate = RelationshipReferencesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DOCXValidationError.invalidXML(name, parser.parserError?.localizedDescription ?? L10n.text("خطأ XML غير معروف"))
        }
        return delegate.references
    }

    private static func resolveTarget(sourcePart: String, target: String) throws -> String {
        guard !target.isEmpty, !target.contains("\\") else {
            throw DOCXValidationError.invalidRelationshipTarget(target)
        }
        let baseComponents = sourcePart.isEmpty
            ? []
            : Array(sourcePart.split(separator: "/").dropLast()).map(String.init)
        let targetComponents = target.hasPrefix("/")
            ? target.dropFirst().split(separator: "/").map(String.init)
            : target.split(separator: "/").map(String.init)
        var components = target.hasPrefix("/") ? [] : baseComponents
        for component in targetComponents {
            if component == "." || component.isEmpty { continue }
            if component == ".." {
                guard !components.isEmpty else {
                    throw DOCXValidationError.invalidRelationshipTarget(target)
                }
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        guard !components.isEmpty else { throw DOCXValidationError.invalidRelationshipTarget(target) }
        return components.joined(separator: "/")
    }

    private static func validateCentralDirectory(
        in archive: Data,
        localEntries: [String: Data]
    ) throws {
        let signature = Data([0x50, 0x4B, 0x05, 0x06])
        let searchStart = max(0, archive.count - 65_557)
        guard let range = archive.range(of: signature, options: .backwards, in: searchStart..<archive.count) else {
            throw DOCXValidationError.missingCentralDirectory
        }
        let eocd = range.lowerBound
        guard eocd + 22 <= archive.count else { throw DOCXValidationError.truncatedArchive }
        let disk = try archive.readUInt16LE(at: eocd + 4)
        let centralDisk = try archive.readUInt16LE(at: eocd + 6)
        let entriesOnDisk = Int(try archive.readUInt16LE(at: eocd + 8))
        let totalEntries = Int(try archive.readUInt16LE(at: eocd + 10))
        let centralSize = Int(try archive.readUInt32LE(at: eocd + 12))
        let centralOffset = Int(try archive.readUInt32LE(at: eocd + 16))
        let commentLength = Int(try archive.readUInt16LE(at: eocd + 20))

        guard disk == 0,
              centralDisk == 0,
              entriesOnDisk == totalEntries,
              totalEntries == localEntries.count,
              eocd + 22 + commentLength == archive.count,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset + centralSize == eocd else {
            throw DOCXValidationError.invalidCentralDirectory
        }

        var cursor = centralOffset
        var names = Set<String>()
        for _ in 0..<totalEntries {
            guard cursor + 46 <= eocd,
                  try archive.readUInt32LE(at: cursor) == 0x02014b50 else {
                throw DOCXValidationError.invalidCentralDirectory
            }
            let method = try archive.readUInt16LE(at: cursor + 10)
            let crc = try archive.readUInt32LE(at: cursor + 16)
            let compressedSize = Int(try archive.readUInt32LE(at: cursor + 20))
            let uncompressedSize = Int(try archive.readUInt32LE(at: cursor + 24))
            let nameLength = Int(try archive.readUInt16LE(at: cursor + 28))
            let extraLength = Int(try archive.readUInt16LE(at: cursor + 30))
            let commentLength = Int(try archive.readUInt16LE(at: cursor + 32))
            let localOffset = Int(try archive.readUInt32LE(at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            let next = nameEnd + extraLength + commentLength
            guard method == 0,
                  compressedSize == uncompressedSize,
                  nameEnd <= eocd,
                  next <= eocd,
                  localOffset >= 0,
                  localOffset + 4 <= centralOffset,
                  try archive.readUInt32LE(at: localOffset) == 0x04034b50,
                  let name = String(data: archive[nameStart..<nameEnd], encoding: .utf8),
                  let payload = localEntries[name],
                  payload.count == uncompressedSize,
                  CRC32.checksum(payload) == crc,
                  names.insert(name).inserted else {
                throw DOCXValidationError.invalidCentralDirectory
            }
            cursor = next
        }
        guard cursor == eocd, names.count == localEntries.count else {
            throw DOCXValidationError.invalidCentralDirectory
        }
    }

}

enum DOCXValidationError: LocalizedError {
    case truncatedArchive
    case invalidLocalHeader(Int)
    case unsupportedCompression(UInt16)
    case sizeMismatch
    case invalidEntryName
    case duplicateEntry(String)
    case crcMismatch(String)
    case missingEntries([String])
    case invalidXML(String, String)
    case missingCentralDirectory
    case invalidCentralDirectory
    case duplicateRelationshipID(String, String)
    case externalRelationship(String, String)
    case missingRelationshipTarget(String, String)
    case missingRelationshipID(String, String)
    case invalidRelationshipTarget(String)
    case missingDocumentContentType
    case missingPNGContentType
    case invalidMedia(String)

    var errorDescription: String? {
        switch self {
        case .truncatedArchive:
            return L10n.text("ملف DOCX الناتج مبتور أو غير مكتمل.")
        case .invalidLocalHeader(let offset):
            return L10n.format("بنية ZIP الداخلية غير صالحة عند الموضع %d.", offset)
        case .unsupportedCompression(let method):
            return L10n.format("طريقة ضغط ZIP الداخلية غير مدعومة في فاحص DOCX: %d.", Int(method))
        case .sizeMismatch:
            return L10n.text("أحجام أحد مكونات DOCX الداخلية غير متطابقة.")
        case .invalidEntryName:
            return L10n.text("اسم مكوّن داخلي في DOCX غير صالح.")
        case .duplicateEntry(let name):
            return L10n.format("يوجد مكوّن داخلي مكرر في DOCX: %@.", name)
        case .crcMismatch(let name):
            return L10n.format("فشل فحص CRC للمكوّن الداخلي: %@.", name)
        case .missingEntries(let names):
            return L10n.format("ملف DOCX يفتقد مكونات أساسية: %@.", names.joined(separator: ", "))
        case .invalidXML(let name, let reason):
            return L10n.format("ملف XML الداخلي %@ غير صالح: %@.", name, reason)
        case .missingCentralDirectory:
            return L10n.text("ملف DOCX لا يحتوي على نهاية ZIP صحيحة.")
        case .invalidCentralDirectory:
            return L10n.text("الدليل المركزي لحزمة DOCX غير متطابق مع محتوياتها.")
        case .duplicateRelationshipID(let part, let id):
            return L10n.format("معرّف علاقة مكرر داخل %@: %@.", part, id)
        case .externalRelationship(let part, let target):
            return L10n.format("يحتوي DOCX على علاقة خارجية غير متوقعة داخل %@: %@.", part, target)
        case .missingRelationshipTarget(let part, let target):
            return L10n.format("العلاقة داخل %@ تشير إلى مكوّن مفقود: %@.", part, target)
        case .missingRelationshipID(let part, let id):
            return L10n.format("يستخدم %@ معرّف علاقة غير موجود: %@.", part, id)
        case .invalidRelationshipTarget(let target):
            return L10n.format("مسار علاقة داخلي غير صالح في DOCX: %@.", target)
        case .missingDocumentContentType:
            return L10n.text("تعريف نوع مستند Word الأساسي مفقود من DOCX.")
        case .missingPNGContentType:
            return L10n.text("تعريف صور PNG مفقود من DOCX رغم وجود صور مضمنة.")
        case .invalidMedia(let name):
            return L10n.format("ملف الصورة الداخلي %@ لا يحمل توقيع PNG صالحًا.", name)
        }
    }
}

private struct PackageRelationship {
    let id: String
    let type: String
    let target: String
    let targetMode: String?
}

private final class RelationshipsDelegate: NSObject, XMLParserDelegate {
    private(set) var relationships: [PackageRelationship] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Relationship" || qName?.hasSuffix(":Relationship") == true,
              let id = attributeDict["Id"],
              let type = attributeDict["Type"],
              let target = attributeDict["Target"] else { return }
        relationships.append(PackageRelationship(
            id: id,
            type: type,
            target: target,
            targetMode: attributeDict["TargetMode"]
        ))
    }
}

private final class RelationshipReferencesDelegate: NSObject, XMLParserDelegate {
    private(set) var references = Set<String>()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        for (key, value) in attributeDict where key == "r:id" || key == "r:embed" {
            if !value.isEmpty { references.insert(value) }
        }
    }
}

private final class ContentTypesDelegate: NSObject, XMLParserDelegate {
    private(set) var overrides = Set<String>()
    private(set) var defaultExtensions = Set<String>()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "Override" || qName?.hasSuffix(":Override") == true {
            if let name = attributeDict["PartName"] { overrides.insert(name) }
        } else if elementName == "Default" || qName?.hasSuffix(":Default") == true {
            if let ext = attributeDict["Extension"]?.lowercased() { defaultExtensions.insert(ext) }
        }
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw DOCXValidationError.truncatedArchive }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw DOCXValidationError.truncatedArchive }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
