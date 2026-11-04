import Foundation

// In-memory transport fixtures: never contact AWS or private network addresses.
final class FixtureProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var declaredLength: Int?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var headers = ["Content-Type": "application/rss+xml"]
        if let length = Self.declaredLength { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct SecurityChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func feed(_ content: String) -> String { "<rss><channel>\(content)</channel></rss>" }
        func item(_ content: String) -> String { "<item>\(content)</item>" }
        func rejects(_ xml: String) {
            do { _ = try FeedParser.parse(Data(xml.utf8)); preconditionFailure("Accepted hostile XML") }
            catch { checks += 1 }
        }
        for xml in [
            "<outer><rss/><channel/><item><title>[RESOLVED] spoof</title></item></outer>",
            "<rss><channel/><channel/></rss>",
            "<rss><item><title>x</title></item><channel/></rss>",
            feed(item("<title>x</title><title>[RESOLVED] y</title>")),
            feed(item("<title>x<b>y</b></title>")),
            feed(item("<title>x</title><item><title>y</title></item>")),
            feed(item("<title>" + String(repeating: "x", count: 4097) + "</title>")),
            feed(item("<title>x</title><description><![CDATA[" + String(repeating: "<", count: 262145) + "]]></description>")),
            feed((0..<513).map { item("<title>x</title><guid>\($0)</guid>") }.joined()),
            feed(String(repeating: "<x/>", count: 50_001)),
            feed(String(repeating: "<x>", count: 20) + String(repeating: "</x>", count: 20)),
            "<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss><channel/></rss>"
        ] { rejects(xml) }
        do {
            _ = try FeedParser.parse("<rss><channel/></rss>".data(using: .utf16)!)
            preconditionFailure("UTF-16 must not bypass declaration checks")
        } catch is FeedError { checks += 1 }
        let boundary = try FeedParser.parse(Data(feed(item("<title>" + String(repeating: "x", count: 4096) + "</title>")).utf8))
        check(boundary[0].title.utf8.count == 4096, "Inclusive title limit")
        let unicode = try FeedParser.parse(Data(feed(item("<title>状態 ☁️</title><description><![CDATA[<p>Recovery &amp; progress ☁️</p>]]></description>")).utf8))
        check(unicode[0].body == "Recovery & progress ☁️", "Unicode and entity conversion")
        let undated = try FeedParser.parse(Data(feed(item("<title>[RESOLVED] x</title>")).utf8))
        check(undated[0].health == .unknown, "Undated resolution must stay unknown")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        for offset: TimeInterval in [0, 301, 86400] {
            let xml = feed(item("<title>[RESOLVED] x</title><pubDate>\(formatter.string(from: now.addingTimeInterval(offset)))</pubDate>"))
            let parsed = try FeedParser.parse(Data(xml.utf8))
            check(parsed[0].health(at: now) == (offset == 0 ? .resolved : .unknown), "Future date policy")
        }
        check(Health.infer("Service is operating normally except for errors") == .unknown, "Ambiguous normal prefix")
        for size in [10_000, 40_000, 100_000, 262_144] {
            let payload = String(repeating: "<", count: size)
            let start = ContinuousClock.now
            let parsed = try FeedParser.parse(Data(feed(item("<title>x</title><description><![CDATA[\(payload)]]></description>")).utf8))
            let duration = ContinuousClock.now - start
            check(parsed[0].body == payload, "Unmatched markup preserved")
            check(duration < .seconds(2), "Parser performance regression")
            print("Adversarial description \(size) bytes: \(duration)")
        }
        let entities = String(repeating: "&#x2713;", count: 30_000)
        let entityStart = ContinuousClock.now
        let decoded = try FeedParser.parse(Data(feed(item("<title>x</title><description><![CDATA[\(entities)]]></description>")).utf8))
        check(decoded[0].body == String(repeating: "✓", count: 30_000), "High-count numeric entities decoded")
        check(ContinuousClock.now - entityStart < .seconds(2), "Entity decoding remains bounded")
        let maximumItems = try FeedParser.parse(Data(feed((0..<512).map { item("<title>x</title><guid>\($0)</guid>") }.joined()).utf8))
        check(maximumItems.count == 512, "Inclusive item limit")
        let task = Task { () throws -> [FeedItem] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try FeedParser.parse(Data("<rss><channel/></rss>".utf8))
        }
        do { _ = try await task.value; preconditionFailure("Cancelled parse accepted") }
        catch is CancellationError { checks += 1 }
        let transport = TrustedSession()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config, delegate: transport, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        FixtureProtocol.body = Data("<rss><channel/></rss>".utf8)
        let downloaded = try await transport.fetch(using: session)
        check(downloaded == FixtureProtocol.body, "Transport delivers fixture")
        for (status, length, bytes) in [(302, nil, 0), (500, nil, 0), (200, 2_000_001, 0), (200, nil, 2_000_001)] as [(Int, Int?, Int)] {
            FixtureProtocol.status = status
            FixtureProtocol.declaredLength = length
            FixtureProtocol.body = Data(repeating: 32, count: bytes)
            do { _ = try await transport.fetch(using: session); preconditionFailure("Unsafe response accepted") }
            catch is FeedError { checks += 1 }
        }
        let request = URLRequest(url: URL(string: "https://status.aws.amazon.com/")!)
        let dummy = session.dataTask(with: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        transport.urlSession(session, task: dummy, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: URL(string: "http://127.0.0.1/")!)) { redirected in
            precondition(redirected == nil, "Redirect must be rejected")
        }
        checks += 1
        print("All \(checks) security regression checks passed.")
    }
}
