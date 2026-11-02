import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.nilcolor.Ensign", category: "monitor")

public struct IPInfo: Sendable, Equatable {
    public var v4: IPLookup
    public var v6: String?
    public var provider: String
    public var checkedAt: Date
}

public enum IPStatus: Sendable, Equatable {
    case offline
    case checking(last: IPInfo?)
    case online(IPInfo)
    case failed(last: IPInfo?)

    public var info: IPInfo? {
        switch self {
        case .offline: nil
        case .checking(let last), .failed(let last): last
        case .online(let info): info
        }
    }

    public func menuBarTitle(format: DisplayFormat, isVPN: Bool) -> String {
        let title: String
        switch self {
        case .offline:
            return "offline"
        case .checking(nil):
            title = "…"
        case .failed(nil):
            title = "?"
        case .checking(let info?), .online(let info):
            title = format.format(info.v4)
        case .failed(let info?):
            title = format.format(info.v4) + " ⚠︎"
        }
        return isVPN ? "🔒 " + title : title
    }
}

@MainActor
@Observable
public final class IPMonitor {
    public private(set) var status: IPStatus = .checking(last: nil)
    public private(set) var network = NetworkState(isOnline: true)

    public var isVPN: Bool {
        network.isVPN || (status.info?.v4.isWarp ?? false)
    }

    /// Called with (old, new) when the public IPv4 changes. Not called for the first result.
    @ObservationIgnored public var onIPChange: ((IPInfo, IPInfo) -> Void)?

    @ObservationIgnored private let resolver: IPResolver
    @ObservationIgnored private let enricher: GeoEnricher
    @ObservationIgnored private let v4Chain: [IPProvider]
    @ObservationIgnored private let v6Chain: [IPProvider]
    @ObservationIgnored private let networkStates: AsyncStream<NetworkState>
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let backoff: [Duration]
    @ObservationIgnored private var lastInfo: IPInfo?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var hasNetworkState = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?

    public init(
        resolver: IPResolver = IPResolver(),
        enricher: GeoEnricher? = nil,
        v4Chain: [IPProvider] = IPProvider.v4Chain,
        v6Chain: [IPProvider] = IPProvider.v6Chain,
        networkStates: AsyncStream<NetworkState> = NetworkMonitor.states(),
        interval: Duration = .seconds(15 * 60),
        // Path updates arrive in bursts while an interface comes up; wait for it to settle.
        debounce: Duration = .seconds(2),
        backoff: [Duration] = [.seconds(5), .seconds(15), .seconds(60)]
    ) {
        self.resolver = resolver
        self.enricher = enricher ?? GeoEnricher(resolver: resolver)
        self.v4Chain = v4Chain
        self.v6Chain = v6Chain
        self.networkStates = networkStates
        self.interval = interval
        self.debounce = debounce
        self.backoff = backoff
    }

    public func start() {
        guard networkTask == nil else { return }
        let states = networkStates
        networkTask = Task { [weak self] in
            for await state in states {
                self?.handle(state)
            }
        }
    }

    public func refresh() {
        schedule(after: .zero)
    }

    public func systemDidWake() {
        schedule(after: debounce)
    }

    private func handle(_ state: NetworkState) {
        let isFirst = !hasNetworkState
        hasNetworkState = true
        network = state
        log.info("network online=\(state.isOnline) vpn=\(state.isVPN) interface=\(state.primaryInterface ?? "-", privacy: .public)")

        guard state.isOnline else {
            pending?.cancel()
            status = .offline
            return
        }
        // Re-check on every path update, even when our summary of it looks unchanged:
        // tunnels like Cloudflare WARP reroute traffic without becoming the primary interface.
        schedule(after: isFirst ? .zero : debounce)
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    private func check() async {
        guard network.isOnline else {
            status = .offline
            return
        }
        status = .checking(last: lastInfo)

        let resolver = resolver
        let v4Chain = v4Chain
        let v6Chain = v6Chain
        async let v6 = try? resolver.resolve(v6Chain)
        let v4: Resolution
        do {
            v4 = try await resolver.resolve(v4Chain)
        } catch {
            _ = await v6
            guard !Task.isCancelled else { return }
            status = .failed(last: lastInfo)
            let delay = failures < backoff.count ? backoff[failures] : interval
            log.error("all v4 providers failed; retry in \(delay, privacy: .public)")
            failures += 1
            schedule(after: delay)
            return
        }
        let v6Address = await v6?.lookup.ip
        guard !Task.isCancelled else { return }

        var info = IPInfo(v4: v4.lookup, v6: v6Address, provider: v4.provider, checkedAt: .now)
        if let last = lastInfo, last.v4.ip == info.v4.ip {
            info.v4 = info.v4.merged(with: last.v4)
        }
        let previous = lastInfo
        publish(info)
        log.info("v4=\(info.v4.ip, privacy: .public) via \(info.provider, privacy: .public) v6=\(info.v6 ?? "-", privacy: .public)")

        if let previous, previous.v4.ip != info.v4.ip {
            onIPChange?(previous, info)
        }

        let enriched = await enricher.enrich(info.v4)
        guard !Task.isCancelled else { return }
        if enriched != info.v4, lastInfo?.v4.ip == enriched.ip {
            info.v4 = enriched
            publish(info)
            log.info("enriched country=\(enriched.countryCode ?? "-", privacy: .public) city=\(enriched.city ?? "-", privacy: .public)")
        }
        // Must come last: scheduling cancels `pending`, which is the task running this check.
        schedule(after: interval)
    }

    private func publish(_ info: IPInfo) {
        lastInfo = info
        failures = 0
        status = .online(info)
    }
}
