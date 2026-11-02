import Foundation
import Testing
@testable import EnsignKit

// Fixtures mirror real responses captured 2026-11-02, with addresses swapped for documentation ranges.
@Suite struct ParserTests {
    @Test func cloudflareTrace() throws {
        let body = """
        fl=673f18
        h=1.1.1.1
        ip=203.0.113.7
        ts=1793614931.000
        colo=AMS
        loc=NL
        warp=off
        """
        let r = try Parsers.cloudflareTrace(Data(body.utf8))
        #expect(r == IPLookup(ip: "203.0.113.7", countryCode: "NL"))
    }

    @Test func cloudflareTraceWarp() throws {
        let r = try Parsers.cloudflareTrace(Data("ip=203.0.113.7\nloc=NL\nwarp=plus\n".utf8))
        #expect(r.isWarp)
    }

    @Test func cloudflareTraceWithoutIP() {
        #expect(throws: ParseError.malformed) { try Parsers.cloudflareTrace(Data("loc=NL\n".utf8)) }
    }

    @Test func myipWTF() throws {
        let body = """
        {
          "YourFuckingIPAddress": "203.0.113.7",
          "YourFuckingLocation": "Amsterdam, NH, Netherlands",
          "YourFuckingHostname": "host.example.net",
          "YourFuckingISP": "Example ISP",
          "YourFuckingTorExit": false,
          "YourFuckingCity": "Amsterdam",
          "YourFuckingCountry": "Netherlands",
          "YourFuckingCountryCode": "NL"
        }
        """
        let r = try Parsers.myipWTF(Data(body.utf8))
        #expect(r == IPLookup(ip: "203.0.113.7", countryCode: "NL", city: "Amsterdam", isp: "Example ISP", hostname: "host.example.net"))
    }

    @Test func ipify() throws {
        #expect(try Parsers.ipify(Data(#"{"ip":"203.0.113.7"}"#.utf8)).ip == "203.0.113.7")
    }

    @Test func plainText() throws {
        #expect(try Parsers.plainText(Data("203.0.113.7\n".utf8)).ip == "203.0.113.7")
        #expect(throws: ParseError.malformed) { try Parsers.plainText(Data(" \n".utf8)) }
    }

    @Test func ifconfigCo() throws {
        let body = """
        {"ip":"203.0.113.7","ip_decimal":3405803783,"country":"Netherlands","country_iso":"NL","country_eu":false,
         "city":"Amsterdam","asn":"AS64496","asn_org":"Example ISP","hostname":"host.example.net",
         "user_agent":{"product":"curl"}}
        """
        let r = try Parsers.ifconfigCo(Data(body.utf8))
        #expect(r == IPLookup(ip: "203.0.113.7", countryCode: "NL", city: "Amsterdam", isp: "Example ISP", hostname: "host.example.net"))
    }

    @Test func ipinfo() throws {
        let body = """
        {"ip":"203.0.113.7","hostname":"host.example.net","city":"Rotterdam","region":"South Holland",
         "country":"NL","loc":"52.3740,4.8897","org":"AS64496 Example ISP","timezone":"Europe/Amsterdam"}
        """
        let r = try Parsers.ipinfo(Data(body.utf8))
        #expect(r == IPLookup(ip: "203.0.113.7", countryCode: "NL", city: "Rotterdam", isp: "Example ISP", hostname: "host.example.net"))
    }

    @Test func garbageJSON() {
        #expect(throws: ParseError.malformed) { try Parsers.ipify(Data("<html>".utf8)) }
    }
}
