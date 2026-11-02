import Foundation
import Testing
@testable import EnsignKit

@Suite struct DisplayFormatTests {
    let lookup = IPLookup(ip: "203.0.113.255", countryCode: "NL")

    @Test(arguments: [
        (DisplayFormat.fullIP, "203.0.113.255"),
        (.truncated, "…113.255"),
        (.flag, "🇳🇱"),
        (.flagIP, "🇳🇱 203.0.113.255"),
        (.flagTruncated, "🇳🇱 …113.255"),
    ])
    func formats(format: DisplayFormat, expected: String) {
        #expect(format.format(lookup) == expected)
    }

    @Test func truncatesIPv6() {
        #expect(DisplayFormat.truncate("2001:db8::abcd:ef01") == "…abcd:ef01")
    }

    @Test func flags() {
        #expect(Flag.emoji(for: "NL") == "🇳🇱")
        #expect(Flag.emoji(for: "us") == "🇺🇸")
        #expect(Flag.emoji(for: nil) == Flag.unknown)
        #expect(Flag.emoji(for: "XX") == Flag.unknown)
        #expect(Flag.emoji(for: "T1") == Flag.unknown)
        #expect(Flag.emoji(for: "GEO") == Flag.unknown)
    }

    @Test func menuBarTitles() {
        let info = IPInfo(v4: lookup, v6: nil, provider: "x", checkedAt: .now)
        #expect(IPStatus.offline.menuBarTitle(format: .fullIP, isVPN: true) == "offline")
        #expect(IPStatus.checking(last: nil).menuBarTitle(format: .fullIP, isVPN: false) == "…")
        #expect(IPStatus.checking(last: info).menuBarTitle(format: .fullIP, isVPN: false) == "203.0.113.255")
        #expect(IPStatus.online(info).menuBarTitle(format: .flag, isVPN: true) == "🔒 🇳🇱")
        #expect(IPStatus.failed(last: info).menuBarTitle(format: .fullIP, isVPN: false) == "203.0.113.255 ⚠︎")
        #expect(IPStatus.failed(last: nil).menuBarTitle(format: .fullIP, isVPN: false) == "?")
    }

    @Test func tunnelNames() {
        #expect(NetworkState.isTunnelName("utun4"))
        #expect(NetworkState.isTunnelName("ipsec0"))
        #expect(!NetworkState.isTunnelName("en0"))
        #expect(!NetworkState.isTunnelName(nil))
    }
}
