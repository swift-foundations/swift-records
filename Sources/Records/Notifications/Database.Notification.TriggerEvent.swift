import Foundation

extension Database.Notification {
    /// Events that can trigger a database notification.
    ///
    /// Used with `setupNotificationChannel()` to specify which database operations
    /// should send notifications.
    public enum TriggerEvent: String, Sendable, Hashable {
        /// INSERT operations
        case insert = "INSERT"

        /// UPDATE operations
        case update = "UPDATE"

        /// DELETE operations
        case delete = "DELETE"

        /// TRUNCATE operations
        case truncate = "TRUNCATE"
    }
}
