import Foundation
import os
import Testing
@testable import EnsignKit

private struct Unreachable: Error {}

/// Responses keyed by host, swappable mid-test.
private final class MutableFetcher: Sendable {
    let responses: OSAllocatedUnfairLock<[String: String]>

    init(_ responses: [String: String]) {
        self.responses = OSAllocatedUnfairLock(initialState: responses)
    }

    var fetch: Fetcher {
        { [self] url in
            guard let body = responses.withLock({ $0[url.host() ?? ""] }) else { throw Unreachable() }
            return Data(body.utf8)
        }
    }
}

@MainActor
@Suite struct MonitorTests {
    fileprivate let fetcher = MutableFetcher([
        "v4": "ip=203.0.113.7\nloc=NL\n",
        "geo": #"{"ip":"203.0.113.7","country_iso":"NL","city":"Amsterdam","asn_org":"ISP"}"#,
    ])

    func makeMonitor() -> (IPMonitor, AsyncStream<NetworkState>.Continuation) {
        let (stream, continuation) = AsyncStream<NetworkState>.makeStream()
        let resolver = IPResolver(fetch: fetcher.fetch)
        let monitor = IPMonitor(
            resolver: resolver,
            enricher: GeoEnricher(resolver: resolver, chain: { ip in
                [IPProvider(name: "geo", url: URL(string: "https://geo/\(ip)")!, family: .v4, parse: Parsers.ifconfigCo)]
            }),
            v4Chain: [IPProvider(name: "v4", url: URL(string: "https://v4/")!, family: .v4, parse: Parsers.cloudflareTrace)],
            v6Chain: [IPProvider(name: "v6", url: URL(string: "https://v6/")!, family: .v6, parse: Parsers.plainText)],
            networkStates: stream,
            debounce: .milliseconds(10),
            backoff: [.milliseconds(10)]
        )
        return (monitor, continuation)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func resolvesAndEnrichesWhenOnline() async throws {
        let (monitor, network) = makeMonitor()
        monitor.start()
        network.yield(NetworkState(isOnline: true))

        try await waitUntil { monitor.status.info?.v4.city != nil }
        guard case .online(let info) = monitor.status else {
            Issue.record("expected online, got \(monitor.status)")
            return
        }
        #expect(info.v4 == IPLookup(ip: "203.0.113.7", countryCode: "NL", city: "Amsterdam", isp: "ISP"))
        #expect(info.v6 == nil)
        #expect(info.provider == "v4")
    }

    @Test func goesOfflineAndRecovers() async throws {
        let (monitor, network) = makeMonitor()
        monitor.start()
        network.yield(NetworkState(isOnline: true))
        try await waitUntil { monitor.status.info != nil }

        network.yield(NetworkState(isOnline: false))
        try await waitUntil { monitor.status == .offline }

        network.yield(NetworkState(isOnline: true))
        try await waitUntil { if case .online = monitor.status { true } else { false } }
    }

    @Test func reportsIPChangeButNotFirstResult() async throws {
        let (monitor, network) = makeMonitor()
        var changes: [(String, String)] = []
        monitor.onIPChange = { old, new in changes.append((old.v4.ip, new.v4.ip)) }
        monitor.start()
        network.yield(NetworkState(isOnline: true))
        try await waitUntil { monitor.status.info != nil }
        #expect(changes.isEmpty)

        fetcher.responses.withLock { $0["v4"] = "ip=198.51.100.4\nloc=DE\n" }
        monitor.refresh()
        try await waitUntil { monitor.status.info?.v4.ip == "198.51.100.4" }
        #expect(changes.count == 1)
        #expect(changes.first?.0 == "203.0.113.7")
        #expect(changes.first?.1 == "198.51.100.4")
    }

    @Test func rechecksOnPathUpdateThatLooksUnchanged() async throws {
        let (monitor, network) = makeMonitor()
        monitor.start()
        network.yield(NetworkState(isOnline: true, primaryInterface: "en0"))
        try await waitUntil { monitor.status.info != nil }

        fetcher.responses.withLock { $0["v4"] = "ip=198.51.100.4\nloc=UA\nwarp=on\n" }
        network.yield(NetworkState(isOnline: true, primaryInterface: "en0"))
        try await waitUntil { monitor.status.info?.v4.ip == "198.51.100.4" }
        #expect(monitor.isVPN)
    }

    @Test func keepsLastIPWhenChecksFail() async throws {
        let (monitor, network) = makeMonitor()
        monitor.start()
        network.yield(NetworkState(isOnline: true))
        try await waitUntil { monitor.status.info != nil }

        fetcher.responses.withLock { $0["v4"] = nil }
        monitor.refresh()
        try await waitUntil { if case .failed = monitor.status { true } else { false } }
        #expect(monitor.status.info?.v4.ip == "203.0.113.7")

        fetcher.responses.withLock { $0["v4"] = "ip=203.0.113.7\nloc=NL\n" }
        try await waitUntil { if case .online = monitor.status { true } else { false } }
    }

    @Test func warpCountsAsVPN() async throws {
        fetcher.responses.withLock { $0["v4"] = "ip=203.0.113.7\nloc=NL\nwarp=on\n" }
        let (monitor, network) = makeMonitor()
        monitor.start()
        network.yield(NetworkState(isOnline: true))
        try await waitUntil { monitor.status.info != nil }
        #expect(monitor.isVPN)
    }
}
