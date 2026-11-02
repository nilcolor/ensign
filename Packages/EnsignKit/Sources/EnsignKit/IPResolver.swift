import Darwin
import Foundation

public typealias Fetcher = @Sendable (URL) async throws -> Data

public struct Resolution: Sendable, Equatable {
    public let lookup: IPLookup
    public let provider: String
}

public enum ResolveError: Error, Equatable {
    case wrongFamily(provider: String, got: String)
    case allFailed
}

public struct IPResolver: Sendable {
    let fetch: Fetcher

    public init(fetch: @escaping Fetcher = URLSessionFetcher.fetch) {
        self.fetch = fetch
    }

    public func resolve(_ chain: [IPProvider]) async throws -> Resolution {
        for provider in chain {
            try Task.checkCancellation()
            do {
                let lookup = try provider.parse(try await fetch(provider.url))
                guard IPAddress.isValid(lookup.ip, family: provider.family) else {
                    throw ResolveError.wrongFamily(provider: provider.name, got: lookup.ip)
                }
                return Resolution(lookup: lookup, provider: provider.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        try Task.checkCancellation()
        throw ResolveError.allFailed
    }
}

public enum IPAddress {
    public static func isValid(_ string: String, family: IPFamily) -> Bool {
        switch family {
        case .v4:
            var addr = in_addr()
            return inet_pton(AF_INET, string, &addr) == 1
        case .v6:
            var addr = in6_addr()
            return inet_pton(AF_INET6, string, &addr) == 1
        }
    }
}

public enum URLSessionFetcher {
    struct HTTPError: Error {
        let status: Int
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        // Fail fast so the chain moves to the next provider instead of stalling on a dead network.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    public static let fetch: Fetcher = { url in
        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError(status: http.statusCode)
        }
        return data
    }
}
