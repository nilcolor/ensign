import Foundation

public enum DisplayFormat: String, CaseIterable, Sendable, Identifiable {
    case fullIP, truncated, flag, flagIP, flagTruncated

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fullIP: "Full IP"
        case .truncated: "Truncated IP"
        case .flag: "Country flag"
        case .flagIP: "Flag + IP"
        case .flagTruncated: "Flag + truncated IP"
        }
    }

    public func format(_ lookup: IPLookup) -> String {
        let flag = Flag.emoji(for: lookup.countryCode)
        return switch self {
        case .fullIP: lookup.ip
        case .truncated: Self.truncate(lookup.ip)
        case .flag: flag
        case .flagIP: "\(flag) \(lookup.ip)"
        case .flagTruncated: "\(flag) \(Self.truncate(lookup.ip))"
        }
    }

    static func truncate(_ ip: String) -> String {
        let separator: Character = ip.contains(":") ? ":" : "."
        let parts = ip.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count > 2 else { return ip }
        return "…" + parts.suffix(2).joined(separator: String(separator))
    }
}

public enum Flag {
    public static let unknown = "🌐"

    public static func emoji(for countryCode: String?) -> String {
        guard let code = countryCode?.uppercased(), code.count == 2,
              code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }),
              // Cloudflare reports "XX" for unknown location (its Tor code "T1" already fails the letter check).
              code != "XX"
        else { return unknown }
        let scalars = code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 0x41) }
        return String(String.UnicodeScalarView(scalars))
    }

    public static func countryName(for countryCode: String?) -> String? {
        guard let countryCode else { return nil }
        return Locale.current.localizedString(forRegionCode: countryCode)
    }
}
