import Foundation

extension Database.Notification {
    /// When a trigger should fire relative to the database operation.
    public enum TriggerTiming: String, Sendable {
        /// Fire before the operation
        case before = "BEFORE"

        /// Fire after the operation
        case after = "AFTER"

        /// Fire instead of the operation (only for views)
        case insteadOf = "INSTEAD OF"
    }
}
