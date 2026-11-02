import EnsignKit
import UserNotifications

@MainActor
final class ChangeNotifier {
    func post(old: IPInfo, new: IPInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Public IP changed"
        content.body = "\(old.v4.ip) → \(new.v4.ip) \(Flag.emoji(for: new.v4.countryCode))"
        let request = UNNotificationRequest(identifier: "ip-change", content: content, trigger: nil)

        Task {
            let center = UNUserNotificationCenter.current()
            // Asked on the first change rather than at launch, when the prompt would have no context.
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }
}
