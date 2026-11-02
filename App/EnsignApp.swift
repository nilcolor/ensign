import AppKit
import EnsignKit
import SwiftUI

@main
struct EnsignApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Preferences.displayFormat) private var format: DisplayFormat = .fullIP

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: appDelegate.monitor)
        } label: {
            Text(appDelegate.monitor.status.menuBarTitle(format: format, isVPN: appDelegate.monitor.isVPN))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

enum Preferences {
    static let displayFormat = "displayFormat"
    static let notifyOnChange = "notifyOnChange"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = IPMonitor()
    private let notifier = ChangeNotifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Preferences.notifyOnChange: true])
        monitor.onIPChange = { [notifier] old, new in
            guard UserDefaults.standard.bool(forKey: Preferences.notifyOnChange) else { return }
            notifier.post(old: old, new: new)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [monitor] _ in
            MainActor.assumeIsolated { monitor.systemDidWake() }
        }
        monitor.start()
    }
}
