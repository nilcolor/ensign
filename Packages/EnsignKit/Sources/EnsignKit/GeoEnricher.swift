import Foundation

public actor GeoEnricher {
    private let resolver: IPResolver
    private let chain: @Sendable (String) -> [IPProvider]
    private var cache: [String: IPLookup] = [:]

    public init(resolver: IPResolver, chain: @escaping @Sendable (String) -> [IPProvider] = IPProvider.geoChain(for:)) {
        self.resolver = resolver
        self.chain = chain
    }

    /// Returns `lookup` with missing details filled in; on failure returns it unchanged.
    public func enrich(_ lookup: IPLookup) async -> IPLookup {
        if lookup.hasDetails { return lookup }
        if let cached = cache[lookup.ip] { return lookup.merged(with: cached) }
        guard let geo = try? await resolver.resolve(chain(lookup.ip)).lookup, geo.ip == lookup.ip else {
            return lookup
        }
        cache[lookup.ip] = geo
        return lookup.merged(with: geo)
    }
}
