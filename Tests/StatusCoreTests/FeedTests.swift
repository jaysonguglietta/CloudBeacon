import XCTest
@testable import StatusCore

final class FeedTests: XCTestCase {
    func testAWSCDATAAndDates() throws {
        let xml = """
        <rss><channel><item><title><![CDATA[Service disruption: Increased Error Rates]]></title><description><![CDATA[<p>Recovery &amp; progress</p>]]></description><pubDate>Tue, 15 Sep 2026 03:27:10 PDT</pubDate><guid>incident</guid></item></channel></rss>
        """
        let items = try FeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].health(at: Date(timeIntervalSince1970: 1_800_000_000)), .disruption)
        XCTAssertEqual(items[0].body, "Recovery & progress")
        XCTAssertNotNil(items[0].date)
    }
    func testDoesNotInferRecoveryFromDescriptionOrUnknownTitle() {
        XCTAssertEqual(Health.infer("Investigating unresolved errors"), .unknown)
        XCTAssertEqual(Health.infer("[RESOLVED] Increased Error Rates"), .resolved)
        XCTAssertEqual(Health.infer("Service degradation: errors"), .degraded)
    }
    func testRejectsEntitiesMalformedAndNonRSS() {
        for xml in ["<!DOCTYPE rss [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><rss><channel/></rss>", "<rss><channel>", "<html/>", "<rss><channel><item/></channel></rss>"] {
            XCTAssertThrowsError(try FeedParser.parse(Data(xml.utf8)))
        }
    }
    func testOversizedAndEmpty() throws {
        XCTAssertThrowsError(try FeedParser.parse(Data(repeating: 32, count: 2_000_001)))
        XCTAssertEqual(try FeedParser.parse(Data("<rss><channel/></rss>".utf8)), [])
    }
    func testNewestFirstAndMissingDates() throws {
        let xml = "<rss><channel><item><title>Unknown</title></item><item><title>Service impact: errors</title><pubDate>Tue, 15 Sep 2026 03:27:10 PDT</pubDate></item></channel></rss>"
        let items = try FeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.first?.health(at: Date(timeIntervalSince1970: 1_800_000_000)), .degraded)
        XCTAssertNotEqual(items[0].id, items[1].id)
    }
    func testRejectsAmbiguousStructure() {
        for xml in [
            "<outer><rss/><channel/><item><title>[RESOLVED] x</title></item></outer>",
            "<rss><channel><item><title>x</title><title>y</title></item></channel></rss>",
            "<rss><channel><item><title>x<b>y</b></title></item></channel></rss>"
        ] { XCTAssertThrowsError(try FeedParser.parse(Data(xml.utf8))) }
    }
    func testUndatedAndFutureResolutionCannotEstablishHealth() throws {
        let undated = try FeedParser.parse(Data("<rss><channel><item><title>[RESOLVED] x</title></item></channel></rss>".utf8))
        XCTAssertEqual(undated[0].health, .unknown)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = FeedItem(id: "future", title: "[RESOLVED] x", body: "", date: now.addingTimeInterval(301))
        XCTAssertEqual(future.health(at: now), .unknown)
    }
    func testPathologicalDescriptionRemainsLiteral() throws {
        let payload = String(repeating: "<", count: 100_000)
        let xml = "<rss><channel><item><title>x</title><description><![CDATA[\(payload)]]></description></item></channel></rss>"
        let items = try FeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(items[0].body, payload)
    }
}
