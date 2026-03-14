import Foundation
import UserNotifications

enum MdemgNotification {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendServerCrash() {
        send(title: "MDEMG Server Crashed",
             body: "The MDEMG server process has stopped unexpectedly.",
             identifier: "server-crash")
    }

    static func sendHealthDegraded(reason: String) {
        send(title: "MDEMG Health Degraded",
             body: reason,
             identifier: "health-degraded")
    }

    static func sendServerStarted(port: Int) {
        send(title: "MDEMG Server Started",
             body: "Server is running on port \(port).",
             identifier: "server-started")
    }

    private static func send(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
