import Foundation

public struct StatusSnapshot: Equatable {
    public var health: Health
    public var reason: String
    public static func evaluate(items: [FeedItem], checked: Date?, stale: Bool, savedCopy: Bool, failure: String?, now: Date) -> Self {
        if let failure { return Self(health: .unknown, reason: failure) }
        if savedCopy { return Self(health: .unknown, reason: "Showing a saved copy. Refresh to verify the latest AWS report.") }
        guard checked != nil else { return Self(health: .unknown, reason: "Waiting for the first successful check.") }
        if stale { return Self(health: .unknown, reason: "The last successful check is stale. Refresh to verify this feed.") }
        guard let latest = items.first else { return Self(health: .unknown, reason: "This feed contains no updates. An empty feed cannot confirm service health.") }
        guard items.allSatisfy({ $0.date.map { $0 <= now.addingTimeInterval(300) } ?? false }) else {
            return Self(health: .unknown, reason: "An update has a missing or future publication date. The newest report cannot be confirmed.")
        }
        let health = latest.health(at: now)
        let reason: String
        switch health {
        case .disruption: reason = "The latest regional RSS report describes a disruption. Reports do not expire into a healthy state."
        case .degraded: reason = "The latest regional RSS report describes degraded service. Check the update for details."
        case .resolved: reason = "The latest report says its issue is resolved. This does not establish that all AWS issues are closed."
        case .unknown: reason = "The latest title uses an unrecognized status. Open AWS Health to confirm its meaning."
        }
        return Self(health: health, reason: reason)
    }
}

public struct MonitorFailure: Error, Equatable {
    public let category: String
    public let message: String
    public static func classify(_ error: Error) -> Self {
        if let error = error as? FeedError {
            let category: String
            switch error {
            case .http(let status): category = "HTTP \(status)"
            case .oversized, .resourceLimit: category = "Safety limit"
            case .invalid: category = "Unreadable feed"
            case .rejected: category = "Rejected response"
            }
            return Self(category: category, message: error.localizedDescription)
        }
        if let error = error as? URLError {
            if error.code == .timedOut { return Self(category: "Timeout", message: "AWS did not respond in time. An automatic retry is scheduled.") }
            if [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code) {
                return Self(category: "Connection", message: "Couldn’t reach AWS. Check your connection or wait for the automatic retry.")
            }
            if [.secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid].contains(error.code) {
                return Self(category: "TLS", message: "The secure connection could not be verified. Check your Mac’s date and network; certificate checks remain enabled.")
            }
        }
        return Self(category: "Request failed", message: "The check failed. Try Refresh or copy diagnostics for support.")
    }
}

public struct CheckOutcome: Identifiable {
    public let id = UUID()
    public let date: Date
    public let summary: String
}
