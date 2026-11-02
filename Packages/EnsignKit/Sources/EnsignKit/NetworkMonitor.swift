import Foundation
import Network

public struct NetworkState: Sendable, Equatable {
    public var isOnline: Bool
    public var isVPN: Bool
    public var primaryInterface: String?

    public init(isOnline: Bool, isVPN: Bool = false, primaryInterface: String? = nil) {
        self.isOnline = isOnline
        self.isVPN = isVPN
        self.primaryInterface = primaryInterface
    }

    init(_ path: NWPath) {
        let primary = path.availableInterfaces.first
        isOnline = path.status == .satisfied
        primaryInterface = primary?.name
        // macOS keeps several idle utun interfaces around at all times; they only show up
        // in the path's interface list when a tunnel is actually routing traffic.
        isVPN = isOnline && (primary?.type == .other || Self.isTunnelName(primary?.name))
    }

    static func isTunnelName(_ name: String?) -> Bool {
        guard let name else { return false }
        return ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { name.hasPrefix($0) }
    }
}

public enum NetworkMonitor {
    public static func states() -> AsyncStream<NetworkState> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(NetworkState(path))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "ensign.network-monitor"))
        }
    }
}
