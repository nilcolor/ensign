import AppKit
import EnsignKit
import SwiftUI

struct MenuContent: View {
    let monitor: IPMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let info = monitor.status.info {
            details(info)
        } else {
            Text(monitor.status == .offline ? "No network connection" : "Looking up your IP…")
        }

        Divider()

        if let info = monitor.status.info {
            Button("Copy IP") { copy(info.v4.ip) }
            if let v6 = info.v6 {
                Button("Copy IPv6") { copy(v6) }
            }
        }
        Button("Refresh") { monitor.refresh() }
            .disabled(monitor.status == .offline)

        Divider()

        Button("Settings…") {
            // LSUIElement apps aren't frontmost, so without this the window opens behind other apps.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Ensign") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func details(_ info: IPInfo) -> some View {
        Text("IPv4: \(info.v4.ip)")
        if let v6 = info.v6 {
            Text("IPv6: \(v6)")
        }
        if let location = location(info.v4) {
            Text(location)
        }
        if let isp = info.v4.isp {
            Text(isp)
        }
        if let hostname = info.v4.hostname {
            Text(hostname)
        }
        if monitor.isVPN {
            Text("🔒 VPN active\(monitor.network.primaryInterface.map { " (\($0))" } ?? "")")
        }
        if case .failed = monitor.status {
            Text("⚠︎ Last check failed, retrying")
        }
        Text("via \(info.provider) · \(info.checkedAt.formatted(date: .omitted, time: .shortened))")
    }

    private func location(_ lookup: IPLookup) -> String? {
        let parts = [Flag.countryName(for: lookup.countryCode), lookup.city].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return "\(Flag.emoji(for: lookup.countryCode)) " + parts.joined(separator: ", ")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
