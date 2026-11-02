import EnsignKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.displayFormat) private var format: DisplayFormat = .fullIP
    @AppStorage(Preferences.notifyOnChange) private var notifyOnChange = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Picker("Menu bar shows", selection: $format) {
                ForEach(DisplayFormat.allCases) { format in
                    Text("\(format.label) — \(format.format(Self.sample))").tag(format)
                }
            }
            Toggle("Notify when IP changes", isOn: $notifyOnChange)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A grouped Form is a scroll view with no intrinsic height; disabling scrolling
        // lets it size to its content so the window fits without a scrollbar.
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let sample = IPLookup(ip: "203.0.113.255", countryCode: "NL")

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin {
            launchAtLogin = actual
        }
    }
}
