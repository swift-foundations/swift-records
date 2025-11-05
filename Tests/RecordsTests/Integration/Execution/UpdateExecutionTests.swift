import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "UPDATE Execution Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct ExecutionUpdateTests {
    @Dependency(\.defaultDatabase) var db

    @Test("UPDATE with WHERE and RETURNING")
    func updateWithWhereAndReturning() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    isCompleted: false,
                    priority: .high,
                    remindersListID: 1,
                    title: "Update test high priority"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)

        // Update
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == id }
                .update { $0.isCompleted = true }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first?.priority == Priority.high)
        #expect(results.first?.isCompleted == true)

        // Cleanup
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }

    @Test("UPDATE with NULL values")
    func updateWithNull() async throws {
        // Insert test data with assignedUserID
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    assignedUserID: 1,
                    remindersListID: 1,
                    title: "Update null test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)
        #expect(inserted.first?.assignedUserID == 1)

        // Update to set assignedUserID to nil
        try await db.write { db in
            try await Reminder
                .where { $0.id == id }
                .update { $0.assignedUserID = nil }
                .execute(db)
        }

        // Verify with SELECT
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == id }.fetchOne(db)
        }

        #expect(reminder?.id == id)
        #expect(reminder?.assignedUserID == nil)

        // Cleanup
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }

    @Test("UPDATE multiple columns")
    func updateMultipleColumns() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    isCompleted: false,
                    notes: "Initial notes",
                    remindersListID: 1,
                    title: "Multi-column update test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)

        // Update multiple columns
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == id }
                .update { reminder in
                    reminder.isCompleted = true
                    reminder.notes = "Completed"
                }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first?.isCompleted == true)
        #expect(results.first?.notes == "Completed")

        // Cleanup
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }

    @Test("UPDATE with no matches returns empty")
    func updateNoMatches() async throws {
        // Try to update non-existent record
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == 999999 }
                .update { $0.isCompleted = true }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 0)
    }

    @Test("UPDATE with WHERE on foreign key")
    func updateWithForeignKey() async throws {
        // Insert test list
        let insertedList = try await db.write { db in
            try await RemindersList.insert {
                RemindersList(id: -1, title: "FK update test list")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let listId = try #require(insertedList.first?.id)

        // Insert reminders in this list
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(isFlagged: false, remindersListID: listId, title: "FK test 1")
                Reminder.Draft(isFlagged: false, remindersListID: listId, title: "FK test 2")
                Reminder.Draft(isFlagged: false, remindersListID: listId, title: "FK test 3")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 3)

        // Update reminders in this list
        let results = try await db.write { db in
            try await Reminder
                .where { $0.remindersListID == listId }
                .update { $0.isFlagged = true }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.isFlagged == true })

        // Cleanup (list deletion cascades to reminders)
        try await db.write { db in
            try await RemindersList.find(listId).delete().execute(db)
        }
    }

    @Test("UPDATE all rows")
    func updateAllRows() async throws {
        // Insert test reminders with unique marker
        let marker = "UpdateAll-\(UUID().uuidString.prefix(8))"
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(isFlagged: true, remindersListID: 1, title: "\(marker)-1")
                Reminder.Draft(isFlagged: true, remindersListID: 1, title: "\(marker)-2")
                Reminder.Draft(isFlagged: true, remindersListID: 1, title: "\(marker)-3")
                Reminder.Draft(isFlagged: true, remindersListID: 1, title: "\(marker)-4")
                Reminder.Draft(isFlagged: true, remindersListID: 1, title: "\(marker)-5")
                Reminder.Draft(isFlagged: true, remindersListID: 1, title: "\(marker)-6")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 6)

        // Update all test reminders
        let results = try await db.write { db in
            try await Reminder
                .where { $0.title.ilike("\(marker)-%") }
                .update { $0.isFlagged = false }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 6)
        #expect(results.allSatisfy { $0.isFlagged == false })

        // Cleanup
        try await db.write { db in
            try await Reminder.where { $0.title.ilike("\(marker)-%") }.delete().execute(db)
        }
    }

    @Test("UPDATE with boolean field")
    func updateBoolean() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    isCompleted: false,
                    remindersListID: 1,
                    title: "Boolean update test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)
        #expect(inserted.first?.isCompleted == false)

        // Update
        let updated = try await db.write { db in
            try await Reminder
                .where { $0.id == id }
                .update { $0.isCompleted = true }
                .returning(\.self)
                .fetchOne(db)
        }

        #expect(updated?.isCompleted == true)

        // Cleanup
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }

    @Test("UPDATE with text concatenation")
    func updateTextConcat() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "Original text",
                    remindersListID: 1,
                    title: "Text concat test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)

        // Update with text concatenation (SQL + operator translates to ||)
        try await db.write { db in
            try await Reminder
                .where { $0.id == id }
                .update { $0.notes = $0.notes + " - Updated" }
                .execute(db)
        }

        // Verify with SELECT
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == id }.fetchOne(db)
        }

        #expect(reminder?.id == id)
        #expect(reminder?.notes == "Original text - Updated")

        // Cleanup
        try await db.write { db in
            try await Reminder
                .find(id)
                .delete()
                .execute(db)
        }
    }
}
