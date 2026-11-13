// Notifications macOS : une alerte quand l'état du Drobo change.

import Foundation
import UserNotifications

enum Notifier {
    /// Le centre de notifications exige un vrai bundle `.app` ; lancé nu par
    /// `swift run`, le binaire n'en a pas et l'appel planterait.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Demande l'autorisation (macOS ne pose la question qu'une fois).
    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
