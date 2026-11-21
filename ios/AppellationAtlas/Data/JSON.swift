import Foundation

/// A parsed JSON value. The app reads the Atlas data by key, the same way the website does, so a new field in the data
/// needs no new Swift type. Objects keep their keys in file order, because some sections are shown in that order.
enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON], keys: [String])

    static func read(_ url: URL) -> JSON? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    /// Reads a large file quickly with Foundation's parser. Object keys come back sorted, not in file order.
    static func readFast(_ url: URL) -> JSON? {
        guard let data = try? Data(contentsOf: url), let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSON(any: any)
    }

    init(any: Any) {
        switch any {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSON(any: $0) })
        case let o as [String: Any]:
            var d: [String: JSON] = [:]
            d.reserveCapacity(o.count)
            for (k, v) in o { d[k] = JSON(any: v) }
            self = .object(d, keys: o.keys.sorted())
        default: self = .null
        }
    }

    static func parse(_ data: Data) -> JSON? {
        var p = Parser(bytes: [UInt8](data))
        return p.parse()
    }

    subscript(key: String) -> JSON {
        if case .object(let o, _) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var int: Int? { double.map { Int($0.rounded()) } }
    var bool: Bool? {
        switch self {
        case .bool(let b): b
        case .number(let n): n != 0
        default: nil
        }
    }
    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var strings: [String] { array.compactMap(\.string) }
    var doubles: [Double] { array.compactMap(\.double) }
    var isNull: Bool { self == .null }

    /// Key and value pairs in the order the file lists them.
    var pairs: [(String, JSON)] {
        if case .object(let o, let keys) = self { return keys.compactMap { k in o[k].map { (k, $0) } } }
        return []
    }

    /// True where the website's JavaScript would treat the value as true.
    var truthy: Bool {
        switch self {
        case .null: false
        case .bool(let b): b
        case .number(let n): n != 0
        case .string(let s): !s.isEmpty
        case .array, .object: true
        }
    }
}

/// A small JSON parser that keeps object keys in order, which JSONSerialization does not.
private struct Parser {
    let bytes: [UInt8]
    var i = 0

    mutating func parse() -> JSON? {
        let v = value()
        return v
    }

    mutating func skip() {
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09 { i += 1 }
    }

    mutating func value() -> JSON? {
        skip()
        guard i < bytes.count else { return nil }
        switch bytes[i] {
        case UInt8(ascii: "{"): return object()
        case UInt8(ascii: "["): return array()
        case UInt8(ascii: "\""): return string().map(JSON.string)
        case UInt8(ascii: "t"): i += 4; return .bool(true)
        case UInt8(ascii: "f"): i += 5; return .bool(false)
        case UInt8(ascii: "n"): i += 4; return .null
        default: return number()
        }
    }

    mutating func object() -> JSON? {
        i += 1
        var dict: [String: JSON] = [:]
        var keys: [String] = []
        skip()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(dict, keys: keys) }
        while i < bytes.count {
            skip()
            guard let k = string() else { return nil }
            skip()
            i += 1   // the colon
            guard let v = value() else { return nil }
            if dict.updateValue(v, forKey: k) == nil { keys.append(k) }
            skip()
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(dict, keys: keys) }
            return nil
        }
        return nil
    }

    mutating func array() -> JSON? {
        i += 1
        var out: [JSON] = []
        skip()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(out) }
        while i < bytes.count {
            guard let v = value() else { return nil }
            out.append(v)
            skip()
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(out) }
            return nil
        }
        return nil
    }

    mutating func string() -> String? {
        guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { return nil }
        i += 1
        var buf: [UInt8] = []
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "\"") { i += 1; return String(decoding: buf, as: UTF8.self) }
            if c == UInt8(ascii: "\\") {
                i += 1
                guard i < bytes.count else { return nil }
                let e = bytes[i]
                switch e {
                case UInt8(ascii: "n"): buf.append(0x0A)
                case UInt8(ascii: "t"): buf.append(0x09)
                case UInt8(ascii: "r"): buf.append(0x0D)
                case UInt8(ascii: "b"): buf.append(0x08)
                case UInt8(ascii: "f"): buf.append(0x0C)
                case UInt8(ascii: "u"):
                    guard let u = hex4(i + 1) else { return nil }
                    i += 4
                    var scalar = u
                    if (0xD800...0xDBFF).contains(u), i + 6 < bytes.count, bytes[i + 1] == UInt8(ascii: "\\"), bytes[i + 2] == UInt8(ascii: "u"), let lo = hex4(i + 3) {
                        scalar = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
                        i += 6
                    }
                    if let s = Unicode.Scalar(scalar) { buf.append(contentsOf: Array(String(Character(s)).utf8)) }
                default: buf.append(e)
                }
                i += 1
                continue
            }
            buf.append(c)
            i += 1
        }
        return nil
    }

    func hex4(_ at: Int) -> UInt32? {
        guard at + 3 < bytes.count else { return nil }
        var v: UInt32 = 0
        for k in 0..<4 {
            let c = bytes[at + k]
            let d: UInt32
            switch c {
            case 48...57: d = UInt32(c - 48)
            case 65...70: d = UInt32(c - 55)
            case 97...102: d = UInt32(c - 87)
            default: return nil
            }
            v = v * 16 + d
        }
        return v
    }

    mutating func number() -> JSON? {
        let start = i
        while i < bytes.count {
            let c = bytes[i]
            if (c >= 48 && c <= 57) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") { i += 1 } else { break }
        }
        guard i > start else { return nil }
        let s = String(decoding: bytes[start..<i], as: UTF8.self)
        return Double(s).map(JSON.number)
    }
}
