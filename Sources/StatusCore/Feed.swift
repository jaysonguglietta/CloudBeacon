import Foundation
import CryptoKit

public enum Health: String, Codable, Sendable {
    case disruption, degraded, resolved, quiet, unknown
    public var label: String {
        switch self {
        case .disruption: return "Service disruption reported"
        case .degraded: return "Service degradation reported"
        case .resolved: return "Latest issue reported resolved"
        case .quiet: return "No reports in the last 24 hours"
        case .unknown: return "Status unconfirmed"
        }
    }
    public static func infer(_ title: String) -> Health {
        let title = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("[resolved]") || title.hasPrefix("resolved:") || title == "service is operating normally" { return .resolved }
        if title.hasPrefix("service disruption:") { return .disruption }
        if title.hasPrefix("service degradation:") || title.hasPrefix("service impact:") { return .degraded }
        return .unknown
    }
}

public struct FeedItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let date: Date?
    public init(id: String, title: String, body: String, date: Date?) {
        self.id = id; self.title = title; self.body = body; self.date = date
    }
    public var health: Health { health(at: Date()) }
    public func health(at now: Date) -> Health {
        guard let date, date <= now.addingTimeInterval(300) else { return .unknown }
        return Health.infer(title)
    }
}

public enum FeedError: LocalizedError {
    case oversized, invalid, rejected, resourceLimit, http(Int)
    public var errorDescription: String? {
        switch self {
        case .oversized: return "AWS returned a feed larger than the 2 MB safety limit."
        case .resourceLimit: return "The feed exceeded safe parsing limits. Retry later or check AWS Health directly."
        case .invalid: return "AWS returned an unreadable RSS feed."
        case .rejected: return "AWS did not return a successful feed response."
        case .http(let code): return "AWS returned HTTP \(code). The app will retry automatically."
        }
    }
}

public final class FeedParser: NSObject, XMLParserDelegate {
    public static let maximumBytes = 2_000_000
    private static let fieldLimits = ["title": 4_096, "description": 262_144, "guid": 4_096, "pubDate": 256]
    private var items: [FeedItem] = []
    private var identities: [String: FeedItem] = [:]
    private var fields: [String: String] = [:]
    private var fieldBytes: [String: Int] = [:]
    private var stack: [String] = []
    private var sawChannel = false
    private var callbacks = 0
    private var failure: Error?
    private let clock = ContinuousClock()
    private let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.isLenient = false
        return formatter
    }()

    public static func parse(_ data: Data) throws -> [FeedItem] {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw FeedError.oversized }
        // UTF-8 only: reject declarations before handing any bytes to XMLParser.
        guard let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else { throw FeedError.invalid }
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let parsed = parser.parse()
        if let failure = delegate.failure { throw failure }
        try Task.checkCancellation()
        guard parsed, delegate.sawChannel, delegate.stack.isEmpty else { throw FeedError.invalid }
        return delegate.items.enumerated().sorted {
            let left = $0.element.date ?? .distantPast
            let right = $1.element.date ?? .distantPast
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }

    private func reject(_ parser: XMLParser, _ error: Error = FeedError.invalid) {
        failure = error
        parser.abortParsing()
    }

    private func withinBudget(_ parser: XMLParser) -> Bool {
        guard failure == nil else { return false }
        callbacks += 1
        if Task.isCancelled { reject(parser, CancellationError()); return false }
        guard callbacks <= 100_000, clock.now < deadline else {
            reject(parser, FeedError.resourceLimit); return false
        }
        return true
    }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard withinBudget(parser) else { return }
        guard stack.count < 16 else { reject(parser, FeedError.resourceLimit); return }
        if stack.isEmpty && name != "rss" { reject(parser); return }
        if name == "rss" && !stack.isEmpty { reject(parser); return }
        if name == "channel" {
            guard stack == ["rss"], !sawChannel else { reject(parser); return }
            sawChannel = true
        }
        if name == "item" {
            guard stack == ["rss", "channel"] else { reject(parser); return }
            guard items.count < 512 else { reject(parser, FeedError.resourceLimit); return }
            fields = [:]; fieldBytes = [:]
        }
        if Self.fieldLimits[name] != nil && stack.contains("item") {
            guard stack == ["rss", "channel", "item"], fields[name] == nil else { reject(parser); return }
            fields[name] = ""
            fieldBytes[name] = 0
        } else if stack.count == 4 && Self.fieldLimits[stack[3]] != nil {
            // Item fields must contain text/CDATA, never ambiguous nested markup.
            reject(parser); return
        }
        stack.append(name)
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard withinBudget(parser) else { return }
        guard stack.count == 4, stack[2] == "item", let limit = Self.fieldLimits[stack[3]] else { return }
        let name = stack[3]
        let count = fieldBytes[name, default: 0] + string.utf8.count
        guard count <= limit else { reject(parser, FeedError.resourceLimit); return }
        fieldBytes[name] = count
        fields[name, default: ""] += string
    }

    public func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { reject(parser); return }
        self.parser(parser, foundCharacters: string)
    }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard withinBudget(parser) else { return }
        guard stack.last == name else { reject(parser); return }
        if name == "item" {
            let title = fields["title", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { reject(parser); return }
            let date = formatter.date(from: fields["pubDate", default: ""].trimmingCharacters(in: .whitespacesAndNewlines))
            let body = Self.plainText(fields["description", default: ""])
            let guid = fields["guid", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let fingerprint = Self.digest([title, fields["pubDate", default: ""], body])
            let id = guid.isEmpty ? "content-\(fingerprint)" : "guid-\(Self.digest([guid]))"
            let item = FeedItem(id: id, title: title, body: body, date: date)
            if let existing = identities[id] {
                // Identical repeats are harmless; conflicting GUID reuse is ambiguous.
                guard existing == item else { reject(parser); return }
            } else {
                identities[id] = item
                items.append(item)
            }
        }
        stack.removeLast()
    }

    private static func digest(_ parts: [String]) -> String {
        let data = parts.reduce(into: Data()) { result, part in
            result.append(contentsOf: "\(part.utf8.count):".utf8)
            result.append(contentsOf: part.utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func plainText(_ text: String) -> String {
        // One pass, with no backtracking. Preserve an unmatched trailing '<' literally.
        var result = String.UnicodeScalarView()
        var tagStart: String.UnicodeScalarView.Index?
        let scalars = text.unicodeScalars
        for index in scalars.indices {
            let scalar = scalars[index]
            if tagStart != nil {
                if scalar == ">", let start = tagStart {
                    let tag = String(scalars[scalars.index(after: start)..<index]).lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = tag.split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "\t" }).first.map(String.init) ?? ""
                    if ["p", "div", "br", "li", "ul", "ol", "h1", "h2", "h3", "blockquote"].contains(name) {
                        if result.last != "\n" { result.append("\n") }
                    }
                    tagStart = nil
                }
            } else if scalar == "<" {
                tagStart = index
            } else {
                result.append(scalar)
            }
        }
        if let tagStart { result.append(contentsOf: scalars[tagStart...]) }
        // Decode once using bounded lookahead, avoiding repeated String replacement
        // and UTF-16 range conversion on adversarial high-entity-count descriptions.
        let named = ["lt": "<", "gt": ">", "quot": "\"", "apos": "'", "amp": "&", "nbsp": " ",
                     "mdash": "—", "ndash": "–", "hellip": "…", "bull": "•"]
        var output = String.UnicodeScalarView()
        var index = result.startIndex
        while index < result.endIndex {
            if result[index] == "&" {
                var cursor = result.index(after: index)
                var token = ""
                while cursor < result.endIndex && token.utf8.count <= 12 && result[cursor] != ";" {
                    token.unicodeScalars.append(result[cursor]); cursor = result.index(after: cursor)
                }
                if cursor < result.endIndex && result[cursor] == ";" {
                    var decoded = named[token]
                    if token.hasPrefix("#") {
                        let number = String(token.dropFirst())
                        let value = number.lowercased().hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                        if let value, let scalar = UnicodeScalar(value), value >= 32 || value == 10 || value == 9 {
                            decoded = String(scalar)
                        }
                    }
                    if let decoded {
                        output.append(contentsOf: decoded.unicodeScalars)
                        index = result.index(after: cursor); continue
                    }
                }
            }
            output.append(result[index]); index = result.index(after: index)
        }
        return String(output).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
