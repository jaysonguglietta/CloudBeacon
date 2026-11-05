import Foundation

// Only this endpoint is fetched; feed-supplied URLs are never opened or requested.
public final class TrustedSession: NSObject, URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    // Nonisolated networking keeps byte accumulation off the UI actor.
    public func fetch(using session: URLSession, feedID: String = FeedDescriptor.original.id) async throws -> Data {
        guard FeedCatalog.validID(feedID) else { throw FeedError.rejected }
        let url = URL(string: "https://status.aws.amazon.com/rss/\(feedID).rss")!
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, response.url == url else { throw FeedError.rejected }
        guard http.statusCode == 200 else { throw FeedError.http(http.statusCode) }
        guard response.expectedContentLength <= FeedParser.maximumBytes else { throw FeedError.oversized }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < FeedParser.maximumBytes else { throw FeedError.oversized }
            data.append(byte)
        }
        return data
    }
}

public protocol FeedFetching {
    func fetch() async throws -> Data
}

public final class FeedHTTPClient: FeedFetching {
    private let transport = TrustedSession()
    private let feedID: String
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: transport, delegateQueue: nil)
    }()
    public init(feedID: String = FeedDescriptor.original.id) { self.feedID = feedID }
    public func fetch() async throws -> Data { try await transport.fetch(using: session, feedID: feedID) }
    deinit { session.invalidateAndCancel() }
}
