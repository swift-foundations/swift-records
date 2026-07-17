import Dependencies
import Foundation
import Records_Test_Support
import Testing

extension SnapshotIntegrationTests.Execution.Select {
    @Suite(

        .dependencies {
            $0.envVars = .development
            $0.defaultDatabase = Database.TestDatabase.withReminderData()
        }
    )
    struct Test {
        @Dependency(\.defaultDatabase) var db

        @Test
        func `SELECT all records returns correct count and data`() async {
            await assertQuery(
                Reminder.all.select { ($0.id, $0.title) }.order(by: \.id),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title"
                    FROM "reminders"
                    ORDER BY "reminders"."id"
                    """
                },
                results: {
                    """
                    ┌───┬───────────────────┐
                    │ 1 │ "Groceries"       │
                    │ 2 │ "Haircut"         │
                    │ 3 │ "Vet appointment" │
                    │ 4 │ "Finish report"   │
                    │ 5 │ "Team meeting"    │
                    │ 6 │ "Review PR"       │
                    └───┴───────────────────┘
                    """
                }
            )
        }

        @Test
        func `SELECT with WHERE clause returns correct data`() async {
            await assertQuery(
                Reminder.where { $0.isCompleted }.select { ($0.id, $0.title, $0.isCompleted) }
                    .order(
                        by: \.id
                    ),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title", "reminders"."isCompleted"
                    FROM "reminders"
                    WHERE "reminders"."isCompleted"
                    ORDER BY "reminders"."id"
                    """
                },
                results: {
                    """
                    ┌───┬─────────────────┬──────┐
                    │ 4 │ "Finish report" │ true │
                    └───┴─────────────────┴──────┘
                    """
                }
            )
        }

        @Test
        func `SELECT specific columns returns correct data`() async {
            await assertQuery(
                Reminder.select { $0.title }.order(by: \.title),
                sql: {
                    """
                    SELECT "reminders"."title"
                    FROM "reminders"
                    ORDER BY "reminders"."title"
                    """
                },
                results: {
                    """
                    ┌───────────────────┐
                    │ "Finish report"   │
                    │ "Groceries"       │
                    │ "Haircut"         │
                    │ "Review PR"       │
                    │ "Team meeting"    │
                    │ "Vet appointment" │
                    └───────────────────┘
                    """
                }
            )
        }

        @Test
        func `SELECT with ORDER BY returns correctly ordered data`() async {
            await assertQuery(
                Reminder.all.select { ($0.id, $0.title) }.order(by: \.title),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title"
                    FROM "reminders"
                    ORDER BY "reminders"."title"
                    """
                },
                results: {
                    """
                    ┌───┬───────────────────┐
                    │ 4 │ "Finish report"   │
                    │ 1 │ "Groceries"       │
                    │ 2 │ "Haircut"         │
                    │ 6 │ "Review PR"       │
                    │ 5 │ "Team meeting"    │
                    │ 3 │ "Vet appointment" │
                    └───┴───────────────────┘
                    """
                }
            )
        }

        @Test
        func `SELECT with LIMIT returns correct number of records`() async {
            await assertQuery(
                Reminder.all.select { ($0.id, $0.title) }.order(by: \.id).limit(3),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title"
                    FROM "reminders"
                    ORDER BY "reminders"."id"
                    LIMIT 3
                    """
                },
                results: {
                    """
                    ┌───┬───────────────────┐
                    │ 1 │ "Groceries"       │
                    │ 2 │ "Haircut"         │
                    │ 3 │ "Vet appointment" │
                    └───┴───────────────────┘
                    """
                }
            )
        }

        @Test
        func `SELECT with LIMIT and OFFSET`() async throws {
            let all = try await db.read { db in
                try await Reminder.all.order(by: \.id).fetchAll(db)
            }
            let offset = try await db.read { db in
                try await Reminder.all.order(by: \.id).limit(3, offset: 2).fetchAll(db)
            }
            #expect(offset.count == 3)
            #expect(offset.first?.id == all[2].id)
        }

        @Test
        func `SELECT with NULL checks returns correct data`() async {
            await assertQuery(
                Reminder.where { $0.assignedUserID == nil }.select {
                    ($0.id, $0.title, $0.assignedUserID)
                }
                .order(by: \.id),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title", "reminders"."assignedUserID"
                    FROM "reminders"
                    WHERE ("reminders"."assignedUserID") IS NOT DISTINCT FROM (NULL)
                    ORDER BY "reminders"."id"
                    """
                },
                results: {
                    """
                    ┌───┬───────────────────┬─────┐
                    │ 2 │ "Haircut"         │ nil │
                    │ 3 │ "Vet appointment" │ nil │
                    │ 5 │ "Team meeting"    │ nil │
                    └───┴───────────────────┴─────┘
                    """
                }
            )
        }

        @Test
        func `SELECT with IN clause returns correct data`() async {
            let priorities: [Priority?] = [.low, .high]
            await assertQuery(
                Reminder.where { $0.priority.in(priorities) }.select {
                    ($0.id, $0.title, $0.priority)
                }
                .order(by: \.id),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title", "reminders"."priority"
                    FROM "reminders"
                    WHERE ("reminders"."priority") IN (1, 3)
                    ORDER BY "reminders"."id"
                    """
                },
                results: {
                    """
                    ┌───┬───────────────────┬───────┐
                    │ 3 │ "Vet appointment" │ .high │
                    │ 4 │ "Finish report"   │ .low  │
                    │ 5 │ "Team meeting"    │ .low  │
                    └───┴───────────────────┴───────┘
                    """
                }
            )
        }

        @Test
        func `SELECT with LIKE pattern returns correct data`() async {
            await assertQuery(
                Reminder.where { $0.title.ilike("%e%") }.select { ($0.id, $0.title) }.order(
                    by: \.id
                ),
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title"
                    FROM "reminders"
                    WHERE ("reminders"."title" ILIKE '%e%')
                    ORDER BY "reminders"."id"
                    """
                },
                results: {
                    """
                    ┌───┬───────────────────┐
                    │ 1 │ "Groceries"       │
                    │ 3 │ "Vet appointment" │
                    │ 4 │ "Finish report"   │
                    │ 5 │ "Team meeting"    │
                    │ 6 │ "Review PR"       │
                    └───┴───────────────────┘
                    """
                }
            )
        }

        // TODO: Tuple selection not yet supported - need to rewrite using proper result type
        // @Test
        // @Test
        // @Test

        @Test
        func `SELECT with boolean operators`() async throws {
            let results = try await db.read { db in
                try await Reminder
                    .where { $0.isCompleted || $0.isFlagged }
                    .fetchAll(db)
            }
            #expect(results.count == 3)
            #expect(results.allSatisfy { $0.isCompleted || $0.isFlagged })
        }

        @Test
        func `SELECT with enum comparison`() async throws {
            let high = try await db.read { db in
                try await Reminder.where { $0.priority == Priority.high }.fetchAll(db)
            }
            #expect(high.count == 1)
            #expect(high.first?.priority == .high)
        }

        @Test
        func `SELECT with DISTINCT`() async throws {
            let distinctLists = try await db.read { db in
                try await Reminder.distinct().select { $0.remindersListID }.fetchAll(db)
            }
            #expect(distinctLists.count == 2)
        }

        @Test
        func `SELECT with computed column`() async throws {
            let highPriority = try await db.read { db in
                try await Reminder.where { $0.isHighPriority }.fetchAll(db)
            }
            #expect(highPriority.count == 1)
            #expect(highPriority.first?.priority == .high)
        }

        @Test
        func `Fetch One returns correct single record`() async {
            await assertQuery(
                Reminder.where { $0.id == 1 }.select { ($0.id, $0.title) },
                sql: {
                    """
                    SELECT "reminders"."id", "reminders"."title"
                    FROM "reminders"
                    WHERE ("reminders"."id") = (1)
                    """
                },
                results: {
                    """
                    ┌───┬─────────────┐
                    │ 1 │ "Groceries" │
                    └───┴─────────────┘
                    """
                }
            )
        }

        @Test
        func `Fetch One returns nil when no match`() async throws {
            let reminder = try await db.read { db in
                try await Reminder.where { $0.id == 999 }.fetchOne(db)
            }
            #expect(reminder == nil)
        }

        @Test
        func `SELECT with find()`() async throws {
            let reminder = try await db.read { db in
                try await Reminder.find(1).fetchOne(db)
            }
            #expect(reminder != nil)
            #expect(reminder?.id == 1)
        }

        @Test
        func `SELECT with find() sequence`() async throws {
            let reminders = try await db.read { db in
                try await Reminder.find([1, 2, 3]).fetchAll(db)
            }
            #expect(reminders.count == 3)
            #expect(reminders.map(\.id).sorted() == [1, 2, 3])
        }
    }
}
