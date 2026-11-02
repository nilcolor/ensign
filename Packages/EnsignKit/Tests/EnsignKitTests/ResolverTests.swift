import Foundation
import os
import Testing
@testable import EnsignKit

private struct StubError: Error {}

private final class StubFetcher: Sendable {
    let responses: [String: String]
    let calls = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(_ responses: [String: String]) {
        self.responses = responses
    }

    var fetch: Fetcher {
        { [self] url in
            calls.withLock { $0.append(url.host() ?? url.absoluteString) }
            guard let body = responses[url.host() ?? ""] else { throw StubError() }
            return Data(body.utf8)
        }
    }
}

private func provider(_ host: String, _ family: IPFamily = .v4) -> IPProvider {
    IPProvider(name: host, url: URL(string: "https://\(host)/")!, family: family, parse: Parsers.plainText)
}

@Suite struct ResolverTests {
    @Test func firstGoodAnswerWins() async throws {
        let stub = StubFetcher(["a": "203.0.113.1", "b": "203.0.113.2"])
        let r = try await IPResolver(fetch: stub.fetch).resolve([provider("a"), provider("b")])
        #expect(r == Resolution(lookup: IPLookup(ip: "203.0.113.1"), provider: "a"))
        #expect(stub.calls.withLock { $0 } == ["a"])
    }

    @Test func skipsNetworkErrorGarbageAndWrongFamily() async throws {
        let stub = StubFetcher(["garbage": "<html>oops</html>", "v6": "2001:db8::1", "good": "203.0.113.9"])
        let chain = [provider("down"), provider("garbage"), provider("v6"), provider("good")]
        let r = try await IPResolver(fetch: stub.fetch).resolve(chain)
        #expect(r.provider == "good")
        #expect(stub.calls.withLock { $0 } == ["down", "garbage", "v6", "good"])
    }

    @Test func allFailed() async {
        let stub = StubFetcher([:])
        await #expect(throws: ResolveError.allFailed) {
            try await IPResolver(fetch: stub.fetch).resolve([provider("a"), provider("b")])
        }
    }

    @Test func validatesFamilies() {
        #expect(IPAddress.isValid("203.0.113.7", family: .v4))
        #expect(!IPAddress.isValid("203.0.113", family: .v4))
        #expect(!IPAddress.isValid("2001:db8::1", family: .v4))
        #expect(IPAddress.isValid("2001:db8::1", family: .v6))
        #expect(!IPAddress.isValid("203.0.113.7", family: .v6))
    }
}

@Suite struct EnricherTests {
    private func geoChain(_ ip: String) -> [IPProvider] {
        [IPProvider(name: "geo", url: URL(string: "https://geo/\(ip)")!, family: .v4, parse: Parsers.ifconfigCo)]
    }

    @Test func fillsMissingFieldsAndCaches() async {
        let stub = StubFetcher(["geo": #"{"ip":"203.0.113.7","country_iso":"DE","city":"Berlin","asn_org":"ISP"}"#])
        let enricher = GeoEnricher(resolver: IPResolver(fetch: stub.fetch), chain: { [self] in geoChain($0) })
        let input = IPLookup(ip: "203.0.113.7", countryCode: "NL")

        let first = await enricher.enrich(input)
        let second = await enricher.enrich(input)

        #expect(first == IPLookup(ip: "203.0.113.7", countryCode: "NL", city: "Berlin", isp: "ISP"))
        #expect(second == first)
        #expect(stub.calls.withLock { $0.count } == 1)
    }

    @Test func skipsWhenAlreadyDetailed() async {
        let stub = StubFetcher([:])
        let enricher = GeoEnricher(resolver: IPResolver(fetch: stub.fetch), chain: { [self] in geoChain($0) })
        let input = IPLookup(ip: "203.0.113.7", countryCode: "NL", city: "Amsterdam", isp: "ISP")
        #expect(await enricher.enrich(input) == input)
        #expect(stub.calls.withLock { $0.isEmpty })
    }

    @Test func ignoresAnswerForDifferentIP() async {
        let stub = StubFetcher(["geo": #"{"ip":"198.51.100.1","city":"Elsewhere"}"#])
        let enricher = GeoEnricher(resolver: IPResolver(fetch: stub.fetch), chain: { [self] in geoChain($0) })
        let input = IPLookup(ip: "203.0.113.7")
        #expect(await enricher.enrich(input) == input)
    }
}
