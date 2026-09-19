import Foundation
import UserNotifications

/// Rappel quotidien « Chacounette vous salue ».
/// Une notification par jour est programmée 14 jours à l'avance, puis reprogrammée
/// à chaque ouverture de l'app (le message change chaque jour).
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let enabledKey = "chacounette.notif.enabled"
    private let hourKey = "chacounette.notif.hour"
    private let minuteKey = "chacounette.notif.minute"
    private let idPrefix = "chacounette.daily."
    private let daysAhead = 14

    private let messages: [String] = [
        "Chacounette vous salue. D’un regard.",
        "Elle vous a vu passer. Elle ne dira rien.",
        "Sieste en cours. Aucun ronron à signaler.",
        "Aujourd’hui : observation de la fenêtre.",
        "Elle juge, en silence. Bonne journée.",
        "Un genou est disponible. Elle y réfléchit.",
        "Elle est là. Elle observe. Elle attend."
    ]

    private var isEnabled: Bool { defaults.bool(forKey: enabledKey) }
    private var hour: Int { defaults.object(forKey: hourKey) as? Int ?? 9 }
    private var minute: Int { defaults.object(forKey: minuteKey) as? Int ?? 0 }

    /// État à renvoyer au site : rappel actif ou non, heure choisie, notifications refusées dans Réglages ou non.
    func status(completion: @escaping ([String: Any]) -> Void) {
        center.getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            let state: [String: Any] = [
                "enabled": self.isEnabled && !denied,
                "hour": self.hour,
                "minute": self.minute,
                "denied": denied
            ]
            DispatchQueue.main.async { completion(state) }
        }
    }

    func enable(hour: Int, minute: Int, completion: @escaping ([String: Any]) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                self.defaults.set(true, forKey: self.enabledKey)
                self.defaults.set(hour, forKey: self.hourKey)
                self.defaults.set(minute, forKey: self.minuteKey)
                self.schedule()
            } else {
                self.defaults.set(false, forKey: self.enabledKey)
            }
            self.status(completion: completion)
        }
    }

    func disable(completion: @escaping ([String: Any]) -> Void) {
        defaults.set(false, forKey: enabledKey)
        removeAll()
        status(completion: completion)
    }

    /// À appeler à chaque ouverture de l'app : garde les 14 prochains jours programmés.
    func refreshIfEnabled() {
        guard isEnabled else { return }
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                self.defaults.set(false, forKey: self.enabledKey)
            } else {
                self.schedule()
            }
        }
    }

    // MARK: - Programmation

    private func schedule() {
        removeAll()
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Chacounette"
            let dayNumber = Int(fireDate.timeIntervalSince1970 / 86400)
            content.body = messages[dayNumber % messages.count]
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: idPrefix + String(offset),
                                                content: content,
                                                trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func removeAll() {
        let ids = (0..<daysAhead).map { idPrefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
