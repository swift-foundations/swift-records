import Dependencies
import Dependencies_Test_Support
import Foundation
import Records_Test_Support
import Testing

@Suite(

    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct StatementExtensionTestsNew {
    @Dependency(\.defaultDatabase) var database

    @Test
    func `Statement.execute(db) works correctly`() async throws {
        do {
            // Test execute with insert statement
            try await database.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        notes: "Test notes",
                        remindersListID: 1,
                        title: "Test Reminder"
                    )
                }.execute(db)
            }

            // Verify insertion (6 from sample data + 1 new = 7)
            let count = try await database.read { db in
                try await Reminder.fetchCount(db)
            }

            #expect(count == 7)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test
    func `Statement.fetch All(db) returns all results`() async throws {
        // Sample data already loaded by withReminderData()

        // Test fetchAll using static method
        let reminders = try await database.read { db in
            try await Reminder.fetchAll(db)
        }

        #expect(reminders.count == 6)
        #expect(reminders.contains { $0.title == "Groceries" })
        #expect(reminders.contains { $0.title == "Finish report" })
    }

    @Test
    func `Statement.fetch One(db) returns single result`() async throws {
        // Sample data already loaded by withReminderData()

        // Test fetchOne
        let reminder = try await database.read { db in
            try await Reminder
                .where { $0.title == "Groceries" }
                .asSelect()
                .fetchOne(db)
        }

        #expect(reminder != nil)
        #expect(reminder?.notes == "Milk, Eggs, Apples")
    }

    @Test
    func `Select Statement.fetch Count(db) returns count`() async throws {
        // Sample data already loaded by withReminderData()

        // Test fetchCount using static method
        let totalCount = try await database.read { db in
            try await Reminder.fetchCount(db)
        }

        #expect(totalCount == 6)

        // Test fetchCount with filter
        let filteredCount = try await database.read { db in
            try await Reminder
                .where { $0.isFlagged == true }
                .asSelect()
                .fetchCount(db)
        }

        #expect(filteredCount == 2)  // Haircut and Team meeting are flagged
    }

    @Test
    func `Table.all pattern works correctly`() async throws {
        // Sample data already loaded by withReminderData()

        // Test the Table.all pattern from SharingGRDB
        let allReminders = try await database.read { db in
            try await Reminder.all.fetchAll(db)
        }

        let allLists = try await database.read { db in
            try await RemindersList.all.fetchAll(db)
        }

        let allTags = try await database.read { db in
            try await Tag.all.fetchAll(db)
        }

        #expect(allReminders.count == 6)
        #expect(allLists.count == 2)  // Home and Work
        #expect(allTags.count == 4)
    }

    @Test
    func `Complex queries with where clauses`() async throws {
        // Sample data already loaded by withReminderData()

        // Test complex query with where and order
        let flaggedReminders = try await database.read { db in
            try await Reminder
                .where { $0.isFlagged == true }
                .order(by: \.title)
                .asSelect()
                .fetchAll(db)
        }

        #expect(flaggedReminders.count == 2)
        #expect(flaggedReminders.first?.title == "Haircut")

        // Test query with multiple conditions
        let specificReminder = try await database.read { db in
            try await Reminder
                .where { $0.title == "Groceries" && $0.remindersListID == 1 }
                .asSelect()
                .fetchOne(db)
        }

        #expect(specificReminder != nil)
        #expect(specificReminder?.id == 1)
    }

    @Test
    func `Update and delete operations`() async throws {
        // Sample data already loaded by withReminderData()

        // Test update
        try await database.write { db in
            try await Reminder
                .where { $0.id == 1 }
                .update { $0.title = "Groceries Updated" }
                .execute(db)
        }

        let updatedReminder = try await database.read { db in
            try await Reminder
                .where { $0.id == 1 }
                .asSelect()
                .fetchOne(db)
        }

        #expect(updatedReminder?.title == "Groceries Updated")

        // Test delete
        try await database.write { db in
            try await ReminderTag
                .where { $0.reminderID == 1 && $0.tagID == 1 }
                .delete()
                .execute(db)
        }

        let tagCount = try await database.read { db in
            try await ReminderTag
                .where { $0.reminderID == 1 }
                .asSelect()
                .fetchCount(db)
        }

        #expect(tagCount == 1)  // Originally 2 tags, deleted 1
    }
}
