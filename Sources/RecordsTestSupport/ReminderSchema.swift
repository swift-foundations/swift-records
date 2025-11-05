import Foundation
import StructuredQueriesPostgres

// MARK: - Reminder Schema Models
//
// These models match the upstream schema from:
// - pointfreeco/swift-structured-queries (SQLite query generation tests)
// - pointfreeco/sqlite-data (SQLite database operations tests)
//
// This alignment enables:
// - Porting tests from upstream
// - Consistency across Point-Free ecosystem
// - Familiar domain for developers

@Table
public struct Reminder: Equatable, Identifiable, Sendable {
    public let id: Int
    public var assignedUserID: User.ID?
    public var dueDate: Date?
    public var isCompleted: Bool = false
    public var isFlagged: Bool = false
    public var notes: String = ""
    public var priority: Priority?
    public var remindersListID: RemindersList.ID
    public var title: String = ""
    public var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 1_234_567_890)

    public init(
        id: Int,
        assignedUserID: User.ID? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        isFlagged: Bool = false,
        notes: String = "",
        priority: Priority? = nil,
        remindersListID: RemindersList.ID,
        title: String = "",
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 1_234_567_890)
    ) {
        self.id = id
        self.assignedUserID = assignedUserID
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.isFlagged = isFlagged
        self.notes = notes
        self.priority = priority
        self.remindersListID = remindersListID
        self.title = title
        self.updatedAt = updatedAt
    }
}

@Table
public struct RemindersList: Equatable, Identifiable, Sendable {
    public let id: Int
    public var color: Int = 0x4a99ef
    public var title: String = ""
    public var position: Int = 0

    public init(
        id: Int,
        color: Int = 0x4a99ef,
        title: String = "",
        position: Int = 0
    ) {
        self.id = id
        self.color = color
        self.title = title
        self.position = position
    }
}

@Table
public struct User: Equatable, Identifiable, Sendable {
    public let id: Int
    public var name: String = ""

    public init(id: Int, name: String = "") {
        self.id = id
        self.name = name
    }
}

@Table
public struct Tag: Equatable, Identifiable, Sendable {
    public let id: Int
    public var title: String = ""

    public init(id: Int, title: String = "") {
        self.id = id
        self.title = title
    }
}

@Table("remindersTags")
public struct ReminderTag: Equatable, Sendable {
    public let reminderID: Int
    public let tagID: Int

    public init(reminderID: Int, tagID: Int) {
        self.reminderID = reminderID
        self.tagID = tagID
    }
}

public enum Priority: Int, Codable, QueryBindable, Sendable {
    case low = 1
    case medium = 2
    case high = 3
}

// MARK: - Reminder Column Extensions

extension Reminder.TableColumns {
    /// Computed column: is high priority
    public var isHighPriority: some QueryExpression<Bool> {
        priority == Priority.high
    }

    /// Computed column: is past due
    public var isPastDue: some QueryExpression<Bool> {
        !isCompleted && #sql("coalesce(\(dueDate), CURRENT_DATE) < CURRENT_DATE")
    }
}

// MARK: - Reminder Query Helpers

extension Reminder {
    /// All incomplete reminders
    public static var incomplete: Where<Reminder> {
        Self.where { !$0.isCompleted }
    }

    /// Search reminders by text (title or notes)
    public static func searching(_ text: String) -> Where<Reminder> {
        Self.where {
            $0.title.ilike("%\(text)%") || $0.notes.ilike("%\(text)%")
        }
    }
}

// MARK: - RemindersList Query Helpers

extension RemindersList {
    /// Reminders lists with reminder count
    public static var withReminderCount: some Statement {
        group(by: \.id)
            .join(Reminder.all) { $0.id.eq($1.remindersListID) }
            .select { $1.id.count() }
    }
}
