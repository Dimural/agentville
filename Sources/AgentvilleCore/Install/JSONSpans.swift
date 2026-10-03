import Foundation

/// A strict JSON parser that keeps where everything is in the text, so a file can be edited with
/// the smallest possible insertion or deletion instead of being re-serialised (which would reorder
/// keys and change formatting). Used by `ClaudeSettingsHooks` for Path B of Connect.
///
/// Offsets are UTF-8 byte offsets into the text. Strict RFC 8259: no comments, no trailing commas,
/// no leading zeros, no raw control characters in strings. A UTF-8 byte-order mark is skipped.
struct JSONSpans {
    struct ParseError: Error, Equatable {
        let offset: Int
        let reason: String
    }

    indirect enum Value {
        case object(Object)
        case array(Array)
        /// A string, number, `true`, `false` or `null`; `string` is the decoded text of a string.
        case scalar(range: Range<Int>, string: String?)

        var range: Range<Int> {
            switch self {
            case .object(let o): o.range
            case .array(let a): a.range
            case .scalar(let r, _): r
            }
        }
    }

    struct Member {
        let key: String
        /// The key's opening quote to the value's end.
        let range: Range<Int>
        let value: Value
    }

    struct Object {
        /// `{` to `}` inclusive.
        let range: Range<Int>
        let members: [Member]
        /// Spans of the members, for edits.
        var elementRanges: [Range<Int>] { members.map(\.range) }
    }

    struct Array {
        let range: Range<Int>
        let elements: [Value]
        var elementRanges: [Range<Int>] { elements.map(\.range) }
    }

    let bytes: [UInt8]
    let root: Value

    init(_ text: String) throws {
        bytes = Swift.Array(text.utf8)
        var p = Parser(bytes: bytes)
        p.skipBOM()
        p.skipSpace()
        root = try p.value(depth: 0)
        p.skipSpace()
        guard p.i == bytes.count else { throw ParseError(offset: p.i, reason: "unexpected text after the end") }
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0
        static let maxDepth = 512

        mutating func skipBOM() {
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { i = 3 }
        }

        mutating func skipSpace() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        func fail(_ reason: String) -> ParseError { ParseError(offset: i, reason: reason) }

        mutating func expect(_ b: UInt8) throws {
            guard i < bytes.count, bytes[i] == b else { throw fail("expected '\(Character(UnicodeScalar(b)))'") }
            i += 1
        }

        mutating func value(depth: Int) throws -> Value {
            guard depth < Self.maxDepth else { throw fail("nested too deeply") }
            guard i < bytes.count else { throw fail("unexpected end") }
            switch bytes[i] {
            case UInt8(ascii: "{"): return .object(try object(depth: depth))
            case UInt8(ascii: "["): return .array(try array(depth: depth))
            case UInt8(ascii: "\""):
                let start = i
                let s = try string()
                return .scalar(range: start..<i, string: s)
            case UInt8(ascii: "t"): return try literal("true")
            case UInt8(ascii: "f"): return try literal("false")
            case UInt8(ascii: "n"): return try literal("null")
            default: return try number()
            }
        }

        mutating func object(depth: Int) throws -> Object {
            let start = i
            try expect(UInt8(ascii: "{"))
            skipSpace()
            var members: [Member] = []
            var keys = Set<String>()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") {
                i += 1
                return Object(range: start..<i, members: [])
            }
            while true {
                skipSpace()
                let keyStart = i
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
                let key = try string()
                guard keys.insert(key).inserted else { throw ParseError(offset: keyStart, reason: "duplicate key \"\(key)\"") }
                skipSpace()
                try expect(UInt8(ascii: ":"))
                skipSpace()
                let v = try value(depth: depth + 1)
                members.append(Member(key: key, range: keyStart..<v.range.upperBound, value: v))
                skipSpace()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                try expect(UInt8(ascii: "}"))
                return Object(range: start..<i, members: members)
            }
        }

        mutating func array(depth: Int) throws -> Array {
            let start = i
            try expect(UInt8(ascii: "["))
            skipSpace()
            var elements: [Value] = []
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") {
                i += 1
                return Array(range: start..<i, elements: [])
            }
            while true {
                skipSpace()
                elements.append(try value(depth: depth + 1))
                skipSpace()
                guard i < bytes.count else { throw fail("unexpected end") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                try expect(UInt8(ascii: "]"))
                return Array(range: start..<i, elements: elements)
            }
        }

        mutating func literal(_ word: String) throws -> Value {
            let start = i
            for b in word.utf8 { try expect(b) }
            return .scalar(range: start..<i, string: nil)
        }

        mutating func number() throws -> Value {
            let start = i
            func digits() -> Int { let s = i; while i < bytes.count, (0x30...0x39).contains(bytes[i]) { i += 1 }; return i - s }
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard i < bytes.count, (0x30...0x39).contains(bytes[i]) else { throw fail("expected a value") }
            if bytes[i] == UInt8(ascii: "0") {
                i += 1
                if i < bytes.count, (0x30...0x39).contains(bytes[i]) { throw fail("leading zero") }
            } else {
                _ = digits()
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
                i += 1
                guard digits() > 0 else { throw fail("expected a digit") }
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                i += 1
                if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
                guard digits() > 0 else { throw fail("expected a digit") }
            }
            return .scalar(range: start..<i, string: nil)
        }

        /// A string token; returns its decoded text.
        mutating func string() throws -> String {
            try expect(UInt8(ascii: "\""))
            var out: [UInt8] = []
            while true {
                guard i < bytes.count else { throw fail("unterminated string") }
                let b = bytes[i]
                if b == UInt8(ascii: "\"") { i += 1; break }
                if b < 0x20 { throw fail("control character in a string") }
                if b != UInt8(ascii: "\\") { out.append(b); i += 1; continue }
                i += 1
                guard i < bytes.count else { throw fail("unterminated string") }
                let e = bytes[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800...0xDBFF).contains(scalar) {
                        // A surrogate pair; a lone surrogate becomes U+FFFD.
                        if i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                            i += 2
                            let low = try hex4()
                            scalar = (0xDC00...0xDFFF).contains(low) ? 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00) : 0xFFFD
                        } else {
                            scalar = 0xFFFD
                        }
                    }
                    let ch = Character(UnicodeScalar(scalar) ?? "\u{FFFD}")
                    out.append(contentsOf: Swift.Array(String(ch).utf8))
                default: throw fail("bad escape")
                }
            }
            return String(decoding: out, as: UTF8.self)
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= bytes.count else { throw fail("bad \\u escape") }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[i]
                let d: UInt32
                switch b {
                case 0x30...0x39: d = UInt32(b - 0x30)
                case 0x41...0x46: d = UInt32(b - 0x41 + 10)
                case 0x61...0x66: d = UInt32(b - 0x61 + 10)
                default: throw fail("bad \\u escape")
                }
                v = v * 16 + d
                i += 1
            }
            return v
        }
    }
}
