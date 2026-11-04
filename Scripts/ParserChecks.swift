// Standalone checks for Command Line Tools installations without XCTest.
import Foundation

@main struct ParserChecks {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        let xml = """
        <rss><channel><item><title>Unfamiliar status</title></item><item><title><![CDATA[Service disruption: Increased Error Rates]]></title><description><![CDATA[<p>Recovery &amp; progress</p>]]></description><pubDate>Tue, 15 Sep 2026 03:27:10 PDT</pubDate></item></channel></rss>
        """
        let items = try FeedParser.parse(Data(xml.utf8))
        check(items.count == 2, "Item count")
        check(items[0].health(at: Date(timeIntervalSince1970: 1_800_000_000)) == .disruption, "Newest item sorted first")
        check(items[0].body == "Recovery & progress", "CDATA rendered as plain text")
        check(items[0].date != nil, "AWS timezone date parsed")
        check(items[0].id != items[1].id, "Unique identities")
        check(Health.infer("Investigating unresolved errors") == .unknown, "Unknown title stays unknown")
        check(Health.infer("[RESOLVED] Errors") == .resolved, "Explicit resolution")
        check(Health.infer("Service impact: errors") == .degraded, "Impact classification")
        let empty = try FeedParser.parse(Data("<rss><channel/></rss>".utf8))
        check(empty.isEmpty, "Empty feed")
        for invalid in [Data("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss><channel/></rss>".utf8), Data("<rss><channel>".utf8), Data("<html/>".utf8), Data("<rss><channel><item/></channel></rss>".utf8), Data(repeating: 32, count: 2_000_001)] {
            do { _ = try FeedParser.parse(invalid); fatalError("Unsafe/invalid feed accepted") }
            catch is FeedError { }
        }
        if CommandLine.arguments.count > 1 {
            let live = try FeedParser.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            check(!live.isEmpty, "Live feed contains updates")
            print("Live AWS fixture: \(live.count) updates; latest: \(live[0].title)")
        }
        print("All 14 parser and classification checks passed.")
    }
}
