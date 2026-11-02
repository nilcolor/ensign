import Foundation

public enum IPFamily: Sendable {
    case v4, v6
}

public struct IPLookup: Sendable, Equatable {
    public var ip: String
    public var countryCode: String?
    public var city: String?
    public var isp: String?
    public var hostname: String?
    public var isWarp: Bool

    public init(
        ip: String,
        countryCode: String? = nil,
        city: String? = nil,
        isp: String? = nil,
        hostname: String? = nil,
        isWarp: Bool = false
    ) {
        self.ip = ip
        self.countryCode = countryCode
        self.city = city
        self.isp = isp
        self.hostname = hostname
        self.isWarp = isWarp
    }

    var hasDetails: Bool {
        countryCode != nil && city != nil && isp != nil
    }

    func merged(with other: IPLookup) -> IPLookup {
        IPLookup(
            ip: ip,
            countryCode: countryCode ?? other.countryCode,
            city: city ?? other.city,
            isp: isp ?? other.isp,
            hostname: hostname ?? other.hostname,
            isWarp: isWarp || other.isWarp
        )
    }
}

public enum ParseError: Error, Equatable {
    case malformed
}

public struct IPProvider: Sendable {
    public let name: String
    public let url: URL
    public let family: IPFamily
    public let parse: @Sendable (Data) throws -> IPLookup

    public init(name: String, url: URL, family: IPFamily, parse: @escaping @Sendable (Data) throws -> IPLookup) {
        self.name = name
        self.url = url
        self.family = family
        self.parse = parse
    }
}

public extension IPProvider {
    static let v4Chain: [IPProvider] = [
        IPProvider(name: "Cloudflare", url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!, family: .v4, parse: Parsers.cloudflareTrace),
        IPProvider(name: "myip.wtf", url: URL(string: "https://myip.wtf/json")!, family: .v4, parse: Parsers.myipWTF),
        IPProvider(name: "ipify", url: URL(string: "https://api4.ipify.org?format=json")!, family: .v4, parse: Parsers.ipify),
        IPProvider(name: "Amazon", url: URL(string: "https://checkip.amazonaws.com")!, family: .v4, parse: Parsers.plainText),
    ]

    static let v6Chain: [IPProvider] = [
        IPProvider(name: "Cloudflare", url: URL(string: "https://[2606:4700:4700::1111]/cdn-cgi/trace")!, family: .v6, parse: Parsers.cloudflareTrace),
        IPProvider(name: "ipify", url: URL(string: "https://api6.ipify.org?format=json")!, family: .v6, parse: Parsers.ipify),
        IPProvider(name: "icanhazip", url: URL(string: "https://ipv6.icanhazip.com")!, family: .v6, parse: Parsers.plainText),
    ]

    static func geoChain(for ip: String) -> [IPProvider] {
        [
            IPProvider(name: "ifconfig.co", url: URL(string: "https://ifconfig.co/json?ip=\(ip)")!, family: .v4, parse: Parsers.ifconfigCo),
            IPProvider(name: "ipinfo", url: URL(string: "https://ipinfo.io/\(ip)/json")!, family: .v4, parse: Parsers.ipinfo),
        ]
    }
}

public enum Parsers {
    public static let cloudflareTrace: @Sendable (Data) throws -> IPLookup = { data in
        guard let text = String(data: data, encoding: .utf8) else { throw ParseError.malformed }
        var fields: [Substring: Substring] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            fields[line[..<eq]] = line[line.index(after: eq)...]
        }
        guard let ip = fields["ip"] else { throw ParseError.malformed }
        let warp = fields["warp"].map { $0 == "on" || $0 == "plus" } ?? false
        return IPLookup(ip: String(ip), countryCode: fields["loc"].map(String.init), isWarp: warp)
    }

    public static let myipWTF: @Sendable (Data) throws -> IPLookup = { data in
        struct Response: Decodable {
            let YourFuckingIPAddress: String
            let YourFuckingCountryCode: String?
            let YourFuckingCity: String?
            let YourFuckingISP: String?
            let YourFuckingHostname: String?
        }
        let r = try decode(Response.self, data)
        return IPLookup(
            ip: r.YourFuckingIPAddress,
            countryCode: r.YourFuckingCountryCode,
            city: r.YourFuckingCity,
            isp: r.YourFuckingISP,
            hostname: r.YourFuckingHostname
        )
    }

    public static let ipify: @Sendable (Data) throws -> IPLookup = { data in
        struct Response: Decodable { let ip: String }
        return IPLookup(ip: try decode(Response.self, data).ip)
    }

    public static let plainText: @Sendable (Data) throws -> IPLookup = { data in
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { throw ParseError.malformed }
        return IPLookup(ip: text)
    }

    public static let ifconfigCo: @Sendable (Data) throws -> IPLookup = { data in
        struct Response: Decodable {
            let ip: String
            let country_iso: String?
            let city: String?
            let asn_org: String?
            let hostname: String?
        }
        let r = try decode(Response.self, data)
        return IPLookup(ip: r.ip, countryCode: r.country_iso, city: r.city, isp: r.asn_org, hostname: r.hostname)
    }

    public static let ipinfo: @Sendable (Data) throws -> IPLookup = { data in
        struct Response: Decodable {
            let ip: String
            let country: String?
            let city: String?
            let org: String?
            let hostname: String?
        }
        let r = try decode(Response.self, data)
        return IPLookup(ip: r.ip, countryCode: r.country, city: r.city, isp: r.org.map(stripASN), hostname: r.hostname)
    }

    /// ipinfo prefixes the org with its ASN ("AS64496 Example ISP").
    static func stripASN(_ org: String) -> String {
        guard org.hasPrefix("AS"), let space = org.firstIndex(of: " ") else { return org }
        return String(org[org.index(after: space)...])
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ParseError.malformed
        }
    }
}
