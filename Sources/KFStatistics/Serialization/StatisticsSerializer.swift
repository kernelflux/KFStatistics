// ── StatisticsSerializer Protocol ──

protocol StatisticsSerializer {
    func serialize<E: EventProtocol>(_ event: E) throws -> Data
    func deserialize(_ data: Data, fields: [FieldDescriptor]) throws -> [String: Any]
}

// ──────────────────────────────────────────────
//  StatisticsBinarySerializer — 二进制编码实现
// ──────────────────────────────────────────────

import Foundation

// ═══════════════════════════════════════════════
//  MARK: - Binary encoder (protobuf-compatible)
// ═══════════════════════════════════════════════

struct StatisticsBinarySerializer: StatisticsSerializer {

    init() {}

    func serialize<E: EventProtocol>(_ event: E) throws -> Data {
        var output = Data()
        let mirror = Mirror(reflecting: event)

        for (index, field) in E.fields.enumerated() {
            guard let child = mirror.children
                .first(where: { $0.label == field.name })?
                .value
            else { continue }

            let tag = UInt64((UInt32(index + 1) << 3) | field.type.wireType.rawValue)
            output.appendVarint(tag)

            switch field.type {
            case .string:
                guard let str = child as? String else { break }
                let strData = Data(str.utf8)
                output.appendVarint(UInt64(strData.count))
                output.append(strData)

            case .int64:
                guard let val = child as? Int64 else { break }
                output.appendVarint(UInt64(bitPattern: val))

            case .uint64:
                if let val = child as? UInt64 { output.appendVarint(val) }

            case .double:
                guard let val = child as? Double else { break }
                withUnsafeBytes(of: val) { output.append(contentsOf: $0) }

            case .bool:
                guard let val = child as? Bool else { break }
                output.append(val ? 1 : 0)

            case .data:
                guard let val = child as? Data else { break }
                output.appendVarint(UInt64(val.count))
                output.append(val)
            }
        }
        return output
    }

    func deserialize(_ data: Data, fields: [FieldDescriptor]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        var offset = 0

        while offset < data.count {
            let (tag, consumed) = data.readVarint(at: offset)
            offset = consumed
            let fieldNumber = Int(tag >> 3)

            guard fieldNumber >= 1, fieldNumber <= fields.count else {
                offset = data.skipField(tag: tag, at: offset)
                continue
            }

            let field = fields[fieldNumber - 1]
            switch field.type {
            case .string:
                let (len, c1) = data.readVarint(at: offset)
                offset = c1
                let strData = data[offset..<offset + Int(len)]
                offset += Int(len)
                result[field.name] = String(data: strData, encoding: .utf8)

            case .int64:
                let (val, c) = data.readVarint(at: offset)
                offset = c
                result[field.name] = Int64(bitPattern: val)

            case .uint64:
                let (val, c) = data.readVarint(at: offset)
                offset = c
                result[field.name] = val

            case .double:
                let raw = data[offset..<offset + 8]
                offset += 8
                result[field.name] = Double(bitPattern: raw.withUnsafeBytes { $0.load(as: UInt64.self) })

            case .bool:
                let (val, c) = data.readVarint(at: offset)
                offset = c
                result[field.name] = (val != 0)

            case .data:
                let (len, c1) = data.readVarint(at: offset)
                offset = c1
                result[field.name] = data[offset..<offset + Int(len)]
                offset += Int(len)
            }
        }
        return result
    }
}

// ═══════════════════════════════════════════════
//  MARK: - Wire type helpers
// ═══════════════════════════════════════════════

private enum WireType: UInt32 {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

extension FieldType {
    fileprivate var wireType: WireType {
        switch self {
        case .string, .data: return .lengthDelimited
        case .int64, .uint64, .bool: return .varint
        case .double: return .fixed64
        }
    }
}

// ═══════════════════════════════════════════════
//  MARK: - Varint helpers
// ═══════════════════════════════════════════════

extension Data {
    mutating func appendVarint(_ value: UInt64) {
        var v = value
        while v > 0x7F {
            append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        append(UInt8(v))
    }

    func readVarint(at offset: Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = offset
        while pos < count {
            let byte = self[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return (result, pos)
    }

    func skipField(tag: UInt64, at offset: Int) -> Int {
        let wireType = UInt32(tag & 0x7)
        switch wireType {
        case 0:
            var pos = offset
            while pos < count, self[pos] & 0x80 != 0 { pos += 1 }
            return pos + 1
        case 1: return offset + 8
        case 2:
            let (len, c) = readVarint(at: offset)
            return c + Int(len)
        case 5: return offset + 4
        default: return offset
        }
    }
}
