import Dependencies
import Foundation
import RecordsTestSupport
import Testing

extension SnapshotIntegrationTests.Execution.Insert {
    @Suite(
        "INSERT Execution Tests",
        .dependencies {
            $0.envVars = .development
            $0.defaultDatabase = Database.TestDatabase.withReminderData()
        }
    )
    struct InsertExecutionTests {
        @Dependency(\.defaultDatabase) var db

        @Test("INSERT basic Draft returns correct data")
        func insertBasicDraft() async {
            await assertQuery(
                Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 1,
                        title: "New task"
                    )
                }.returning { ($0.title, $0.remindersListID, $0.isCompleted) },
                sql: {
                    """
                    INSERT INTO "reminders"
                    ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
                    VALUES
                    (DEFAULT, NULL, NULL, false, false, '', NULL, 1, 'New task', '2040-02-14 23:31:30.000')
                    RETURNING "title", "remindersListID", "isCompleted"
                    """
                },
                results: {
                    """
                    ┌────────────┬───┬───────┐
                    │ "New task" │ 1 │ false │
                    └────────────┴───┴───────┘
                    """
                }
            )
        }

        @Test("INSERT with all fields specified")
        func insertWithAllFields() async throws {
            let now = Date()
            let inserted = try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        assignedUserID: 1,
                        dueDate: now,
                        isCompleted: false,
                        isFlagged: true,
                        notes: "Important task",
                        priority: .high,
                        remindersListID: 2,
                        title: "Complete project",
                        updatedAt: now
                    )
                }
                .returning(\.self)
                .fetchAll(db)
            }

            #expect(inserted.count == 1)
            let reminder = try #require(inserted.first)
            #expect(reminder.title == "Complete project")
            #expect(reminder.assignedUserID == 1)
            #expect(reminder.priority == .high)
            #expect(reminder.isFlagged == true)
            #expect(reminder.notes == "Important task")

            // Cleanup
            try await db.write { db in
                try await Reminder
                    .find(reminder.id)
                    .delete()
                    .execute(db)
            }
        }

        @Test("INSERT multiple Drafts returns correct data")
        func insertMultipleDrafts() async {
            await assertQuery(
                Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 1,
                        title: "First task"
                    )
                    Reminder.Draft(
                        remindersListID: 1,
                        title: "Second task"
                    )
                    Reminder.Draft(
                        remindersListID: 2,
                        title: "Third task"
                    )
                }.returning { ($0.title, $0.remindersListID) },
                sql: {
                    """
                    INSERT INTO "reminders"
                    ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
                    VALUES
                    (DEFAULT, NULL, NULL, false, false, '', NULL, 1, 'First task', '2040-02-14 23:31:30.000'), (DEFAULT, NULL, NULL, false, false, '', NULL, 1, 'Second task', '2040-02-14 23:31:30.000'), (DEFAULT, NULL, NULL, false, false, '', NULL, 2, 'Third task', '2040-02-14 23:31:30.000')
                    RETURNING "title", "remindersListID"
                    """
                },
                results: {
                    """
                    ┌───────────────┬───┐
                    │ "First task"  │ 1 │
                    │ "Second task" │ 1 │
                    │ "Third task"  │ 2 │
                    └───────────────┴───┘
                    """
                }
            )
        }

        @Test("INSERT with NULL optional fields")
        func insertWithNullFields() async throws {
            let inserted = try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        assignedUserID: nil,
                        priority: nil,
                        remindersListID: 1,
                        title: "Unassigned task"
                    )
                }
                .returning(\.self)
                .fetchAll(db)
            }

            #expect(inserted.count == 1)
            let reminder = try #require(inserted.first)
            #expect(reminder.assignedUserID == nil)
            #expect(reminder.priority == nil)
            #expect(reminder.dueDate == nil)

            // Cleanup
            try await db.write { db in
                try await Reminder
                    .find(reminder.id)
                    .delete()
                    .execute(db)
            }
        }

        @Test("INSERT with priority levels returns correct data")
        func insertWithPriorities() async {
            await assertQuery(
                Reminder.insert {
                    Reminder.Draft(
                        priority: .low,
                        remindersListID: 1,
                        title: "Low priority"
                    )
                    Reminder.Draft(
                        priority: .medium,
                        remindersListID: 1,
                        title: "Medium priority"
                    )
                    Reminder.Draft(
                        priority: .high,
                        remindersListID: 1,
                        title: "High priority"
                    )
                }.returning { ($0.title, $0.priority) },
                sql: {
                    """
                    INSERT INTO "reminders"
                    ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
                    VALUES
                    (DEFAULT, NULL, NULL, false, false, '', 1, 1, 'Low priority', '2040-02-14 23:31:30.000'), (DEFAULT, NULL, NULL, false, false, '', 2, 1, 'Medium priority', '2040-02-14 23:31:30.000'), (DEFAULT, NULL, NULL, false, false, '', 3, 1, 'High priority', '2040-02-14 23:31:30.000')
                    RETURNING "title", "priority"
                    """
                },
                results: {
                    """
                    ┌───────────────────┬─────────┐
                    │ "Low priority"    │ .low    │
                    │ "Medium priority" │ .medium │
                    │ "High priority"   │ .high   │
                    └───────────────────┴─────────┘
                    """
                }
            )
        }

        @Test("INSERT and verify with SELECT")
        func insertAndVerify() async throws {
            // Insert new reminder
            let inserted = try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        notes: "Test notes",
                        remindersListID: 1,
                        title: "Verify test"
                    )
                }
                .returning(\.self)
                .fetchAll(db)
            }

            let insertedId = try #require(inserted.first?.id)

            // Verify with SELECT
            let fetched = try await db.read { db in
                try await Reminder.where { $0.id == insertedId }.fetchOne(db)
            }

            #expect(fetched != nil)
            #expect(fetched?.title == "Verify test")
            #expect(fetched?.notes == "Test notes")

            // Cleanup
            try await db.write { db in
                try await Reminder
                    .find(insertedId)
                    .delete()
                    .execute(db)
            }
        }

        @Test("INSERT with boolean flags returns correct data")
        func insertWithBooleanFlags() async {
            await assertQuery(
                Reminder.insert {
                    Reminder.Draft(
                        isCompleted: true,
                        isFlagged: true,
                        remindersListID: 1,
                        title: "Flagged and completed"
                    )
                    Reminder.Draft(
                        isCompleted: false,
                        isFlagged: false,
                        remindersListID: 1,
                        title: "Not flagged or completed"
                    )
                }.returning { ($0.title, $0.isCompleted, $0.isFlagged) },
                sql: {
                    """
                    INSERT INTO "reminders"
                    ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
                    VALUES
                    (DEFAULT, NULL, NULL, true, true, '', NULL, 1, 'Flagged and completed', '2040-02-14 23:31:30.000'), (DEFAULT, NULL, NULL, false, false, '', NULL, 1, 'Not flagged or completed', '2040-02-14 23:31:30.000')
                    RETURNING "title", "isCompleted", "isFlagged"
                    """
                },
                results: {
                    """
                    ┌────────────────────────────┬───────┬───────┐
                    │ "Flagged and completed"    │ true  │ true  │
                    │ "Not flagged or completed" │ false │ false │
                    └────────────────────────────┴───────┴───────┘
                    """
                }
            )
        }

        @Test("INSERT into different lists")
        func insertIntoDifferentLists() async throws {
            let inserted = try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(remindersListID: 1, title: "Home task")
                    Reminder.Draft(remindersListID: 2, title: "Work task")
                }
                .returning(\.self)
                .fetchAll(db)
            }

            #expect(inserted.count == 2)
            #expect(inserted[0].remindersListID == 1)
            #expect(inserted[1].remindersListID == 2)

            // Cleanup
            let ids = inserted.map { $0.id }
            try await db.write { db in
                try await Reminder
                    .find(ids)
                    .delete()
                    .execute(db)
            }
        }

        @Test("INSERT with date fields")
        func insertWithDates() async throws {
            let futureDate = Date().addingTimeInterval(86400)  // Tomorrow
            let inserted = try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        dueDate: futureDate,
                        remindersListID: 1,
                        title: "Future task"
                    )
                }
                .returning(\.self)
                .fetchAll(db)
            }

            #expect(inserted.count == 1)
            let reminder = try #require(inserted.first)
            #expect(reminder.dueDate != nil)

            // PostgreSQL DATE type only stores date (not time), so compare calendar dates
            if let dueDate = reminder.dueDate {
                let calendar = Calendar.current
                let insertedComponents = calendar.dateComponents(
                    [.year, .month, .day],
                    from: futureDate
                )
                let retrievedComponents = calendar.dateComponents(
                    [.year, .month, .day],
                    from: dueDate
                )
                #expect(insertedComponents == retrievedComponents)
            }

            // Cleanup
            try await db.write { db in
                try await Reminder
                    .find(reminder.id)
                    .delete()
                    .execute(db)
            }
        }

        @Test("INSERT without RETURNING")
        func insertWithoutReturning() async throws {
            // Use unique title for cleanup
            let uniqueTitle = "No return test \(UUID())"

            // Insert without RETURNING - just verify it doesn't throw
            try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 1,
                        title: uniqueTitle
                    )
                }
                .execute(db)
            }

            // Verify it was inserted by counting
            let count = try await db.read { db in
                try await Reminder.where { $0.title == uniqueTitle }.fetchAll(db)
            }

            #expect(count.count >= 1)

            // Cleanup
            try await db.write { db in
                try await Reminder
                    .where { $0.title == uniqueTitle }
                    .delete()
                    .execute(db)
            }
        }
    }
}
