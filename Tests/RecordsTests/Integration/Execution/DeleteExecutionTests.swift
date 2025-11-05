import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "DELETE Execution Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct DeleteExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("DELETE with WHERE clause")
    func deleteWithWhere() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(remindersListID: 1, title: "Delete test \(UUID())")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)

        // Verify record exists
        let before = try await db.read { db in
            try await Reminder.where { $0.id == id }.fetchOne(db)
        }
        #expect(before != nil)

        // Delete
        try await db.write { db in
            try await Reminder.where { $0.id == id }.delete().execute(db)
        }

        // Verify deleted
        let after = try await db.read { db in
            try await Reminder.where { $0.id == id }.fetchOne(db)
        }
        #expect(after == nil)
    }

    @Test("DELETE with RETURNING")
    func deleteWithReturning() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(remindersListID: 1, title: "Haircut test")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)

        // Delete with RETURNING
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.id == id }
                .delete()
                .returning(\.self)
                .fetchOne(db)
        }

        #expect(deleted?.id == id)
        #expect(deleted?.title == "Haircut test")

        // Verify deletion
        let count = try await db.read { db in
            try await Reminder.where { $0.id == id }.fetchAll(db).count
        }
        #expect(count == 0)
    }

    @Test("DELETE with complex WHERE")
    func deleteWithComplexWhere() async throws {
        // Insert test data with specific criteria
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    isCompleted: true,
                    priority: .high,
                    remindersListID: 1,
                    title: "Complex delete test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 1)

        // Delete with complex WHERE
        let deleted = try await db.write { db in
            try await Reminder
                .where {
                    $0.isCompleted && $0.priority == Priority.high
                        && $0.title == "Complex delete test"
                }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 1)
    }

    @Test("DELETE with no matches")
    func deleteNoMatches() async throws {
        // Try to delete non-existent record
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.id == 999999 }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 0)
    }

    @Test("DELETE with foreign key (cascades)")
    func deleteWithCascade() async throws {
        // Insert a new list
        let insertedList = try await db.write { db in
            try await RemindersList.insert {
                RemindersList(id: -1, title: "Cascade test list")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let listId = try #require(insertedList.first?.id)

        // Insert reminders in this list
        let insertedReminders = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(remindersListID: listId, title: "Cascade test 1")
                Reminder.Draft(remindersListID: listId, title: "Cascade test 2")
                Reminder.Draft(remindersListID: listId, title: "Cascade test 3")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(insertedReminders.count == 3)

        // Delete the list (should cascade to reminders)
        try await db.write { db in
            try await RemindersList.where { $0.id == listId }.delete().execute(db)
        }

        // Verify list is deleted
        let list = try await db.read { db in
            try await RemindersList.where { $0.id == listId }.fetchOne(db)
        }
        #expect(list == nil)

        // Verify reminders are deleted (CASCADE)
        let remindersAfter = try await db.read { db in
            try await Reminder.where { $0.remindersListID == listId }.fetchAll(db)
        }
        #expect(remindersAfter.count == 0)
    }

    @Test("DELETE all records")
    func deleteAll() async throws {
        // Insert test tags with unique titles
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let inserted = try await db.write { db in
            try await Tag.insert {
                Tag(id: -1, title: "Test1-\(uniqueSuffix)")
                Tag(id: -2, title: "Test2-\(uniqueSuffix)")
                Tag(id: -3, title: "Test3-\(uniqueSuffix)")
                Tag(id: -4, title: "Test4-\(uniqueSuffix)")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 4)

        // Delete all test tags
        let deleted = try await db.write { db in
            try await Tag.where { $0.title.ilike("Test%-\(uniqueSuffix)") }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 4)

        // Verify all deleted
        let remaining = try await db.read { db in
            try await Tag.where { $0.title.ilike("Test%-\(uniqueSuffix)") }.fetchAll(db)
        }
        #expect(remaining.count == 0)
    }

    // Note: PostgreSQL DELETE doesn't support ORDER BY/LIMIT directly
    // Would need: DELETE FROM reminders WHERE id IN (SELECT id FROM reminders ORDER BY id LIMIT 1)
    // Skipping this test as it's not a standard DELETE pattern

    @Test("DELETE with enum value")
    func deleteWithEnum() async throws {
        // Insert test data with low priority
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    priority: .low,
                    remindersListID: 1,
                    title: "Low priority delete test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 1)

        // Delete by enum value
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.priority == Priority.low && $0.title == "Low priority delete test" }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 1)
    }

    @Test("DELETE using find()")
    func deleteWithFind() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(remindersListID: 1, title: "Find delete test")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let id = try #require(inserted.first?.id)

        // Delete using find()
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }

        // Verify deleted
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == id }.fetchOne(db)
        }

        #expect(reminder == nil)
    }

    @Test("DELETE using find() with sequence")
    func deleteWithFindSequence() async throws {
        // Insert test data
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(remindersListID: 1, title: "Sequence delete 1")
                Reminder.Draft(remindersListID: 1, title: "Sequence delete 2")
                Reminder.Draft(remindersListID: 1, title: "Sequence delete 3")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 3)
        let ids = inserted.map(\.id)

        // Delete using find() with sequence
        let deleted = try await db.write { db in
            try await Reminder
                .find(ids)
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 3)
        #expect(Set(deleted.map(\.id)) == Set(ids))

        // Verify all deleted
        let remaining = try await db.read { db in
            try await Reminder.find(ids).fetchAll(db)
        }
        #expect(remaining.count == 0)
    }
}
