import Dependencies
import Foundation
import Records_Test_Support
import Testing

extension SnapshotIntegrationTests.Execution.Select {
    @Suite(
        "SELECT Execution Tests",
        .dependencies {
            $0.envVars = .development
            $0.defaultDatabase = Database.TestDatabase.withReminderData()
        }
    )
    struct SelectExecutionTests {
        @Dependency(\.defaultDatabase) var db

        @Test("SELECT all records returns correct count and data")
        func selectAll() async {
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

        @Test("SELECT with WHERE clause returns correct data")
        func selectWithWhere() async {
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

        @Test("SELECT specific columns returns correct data")
        func selectColumns() async {
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

        @Test("SELECT with ORDER BY returns correctly ordered data")
        func selectWithOrderBy() async {
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

        @Test("SELECT with LIMIT returns correct number of records")
        func selectWithLimit() async {
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

        @Test("SELECT with LIMIT and OFFSET")
        func selectWithLimitOffset() async throws {
            let all = try await db.read { db in
                try await Reminder.all.order(by: \.id).fetchAll(db)
            }
            let offset = try await db.read { db in
                try await Reminder.all.order(by: \.id).limit(3, offset: 2).fetchAll(db)
            }
            #expect(offset.count == 3)
            #expect(offset.first?.id == all[2].id)
        }

        @Test("SELECT with NULL checks returns correct data")
        func selectWithNullChecks() async {
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

        @Test("SELECT with IN clause returns correct data")
        func selectWithIn() async {
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

        @Test("SELECT with LIKE pattern returns correct data")
        func selectWithLike() async {
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
        // @Test("SELECT with JOIN")
        // @Test("SELECT with GROUP BY and aggregate")
        // @Test("SELECT with HAVING clause")

        @Test("SELECT with boolean operators")
        func selectWithBooleanOperators() async throws {
            let results = try await db.read { db in
                try await Reminder
                    .where { $0.isCompleted || $0.isFlagged }
                    .fetchAll(db)
            }
            #expect(results.count == 3)
            #expect(results.allSatisfy { $0.isCompleted || $0.isFlagged })
        }

        @Test("SELECT with enum comparison")
        func selectWithEnum() async throws {
            let high = try await db.read { db in
                try await Reminder.where { $0.priority == Priority.high }.fetchAll(db)
            }
            #expect(high.count == 1)
            #expect(high.first?.priority == .high)
        }

        @Test("SELECT with DISTINCT")
        func selectDistinct() async throws {
            let distinctLists = try await db.read { db in
                try await Reminder.distinct().select { $0.remindersListID }.fetchAll(db)
            }
            #expect(distinctLists.count == 2)
        }

        @Test("SELECT with computed column")
        func selectWithComputedColumn() async throws {
            let highPriority = try await db.read { db in
                try await Reminder.where { $0.isHighPriority }.fetchAll(db)
            }
            #expect(highPriority.count == 1)
            #expect(highPriority.first?.priority == .high)
        }

        @Test("fetchOne returns correct single record")
        func fetchOne() async {
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

        @Test("fetchOne returns nil when no match")
        func fetchOneNoMatch() async throws {
            let reminder = try await db.read { db in
                try await Reminder.where { $0.id == 999 }.fetchOne(db)
            }
            #expect(reminder == nil)
        }

        @Test("SELECT with find()")
        func selectWithFind() async throws {
            let reminder = try await db.read { db in
                try await Reminder.find(1).fetchOne(db)
            }
            #expect(reminder != nil)
            #expect(reminder?.id == 1)
        }

        @Test("SELECT with find() sequence")
        func selectWithFindSequence() async throws {
            let reminders = try await db.read { db in
                try await Reminder.find([1, 2, 3]).fetchAll(db)
            }
            #expect(reminders.count == 3)
            #expect(reminders.map(\.id).sorted() == [1, 2, 3])
        }
    }
}
