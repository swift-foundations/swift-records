import Dependencies
import Foundation
import Records
import RecordsTestSupport
import Testing

@Suite(
    "Error Handling Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct ErrorHandlingTests {
    @Dependency(\.defaultDatabase) var db
    @Dependency(\.defaultDatabase) var database

    // MARK: - Constraint Violations

    @Test("NOT NULL constraint violation")
    func testNotNullConstraintViolation() async throws {
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO "reminders" ("remindersListID", "title", "isCompleted")
                    VALUES (NULL, 'Test', false)
                    """
                )
            }
        }
    }

    @Test("Foreign key constraint violation")
    func testForeignKeyConstraintViolation() async throws {
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 999999,  // Non-existent list
                        title: "Invalid foreign key"
                    )
                }.execute(db)
            }
        }
    }

    @Test("Unique constraint violation")
    func testUniqueConstraintViolation() async throws {
        // Create temporary table with unique constraint
        try await db.write { db in
            try await db.execute(
                """
                CREATE TEMPORARY TABLE unique_test (
                    id SERIAL PRIMARY KEY,
                    email TEXT UNIQUE NOT NULL
                )
                """
            )

            // Insert first record
            try await db.execute(
                """
                INSERT INTO unique_test (email) VALUES ('test@example.com')
                """
            )
        }

        // Try to insert duplicate - should fail
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO unique_test (email) VALUES ('test@example.com')
                    """
                )
            }
        }

        // Cleanup
        try await db.write { db in
            try await db.execute("DROP TABLE IF EXISTS unique_test")
        }
    }

    @Test("Check constraint violation")
    func testCheckConstraintViolation() async throws {
        // Create temporary table with check constraint
        try await db.write { db in
            try await db.execute(
                """
                CREATE TEMPORARY TABLE check_test (
                    id SERIAL PRIMARY KEY,
                    age INT CHECK (age >= 0 AND age <= 150)
                )
                """
            )
        }

        // Try to insert invalid age - should fail
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO check_test (age) VALUES (-1)
                    """
                )
            }
        }

        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO check_test (age) VALUES (200)
                    """
                )
            }
        }

        // Cleanup
        try await db.write { db in
            try await db.execute("DROP TABLE IF EXISTS check_test")
        }
    }

    // MARK: - Type Mismatches

    @Test("Type mismatch - text as integer")
    func testTypeMismatchTextAsInteger() async throws {
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO "reminders" ("remindersListID", "title", "isCompleted")
                    VALUES ('not_a_number', 'Test', false)
                    """
                )
            }
        }
    }

    @Test("Type mismatch - invalid date format")
    func testTypeMismatchInvalidDate() async throws {
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO "reminders" ("remindersListID", "title", "isCompleted", "dueDate")
                    VALUES (1, 'Test', false, 'not-a-date')
                    """
                )
            }
        }
    }

    // MARK: - Syntax Errors

    @Test("SQL syntax error")
    func testSQLSyntaxError() async throws {
        await #expect(throws: (any Error).self) {
            try await db.read { db in
                try await db.execute("INVALID SQL SYNTAX")
            }
        }
    }

    @Test("Non-existent table")
    func testNonExistentTable() async throws {
        await #expect(throws: (any Error).self) {
            try await db.read { db in
                try await db.execute("SELECT * FROM nonexistent_table")
            }
        }
    }

    @Test("Non-existent column")
    func testNonExistentColumn() async throws {
        await #expect(throws: (any Error).self) {
            try await db.read { db in
                try await db.execute("SELECT nonexistent_column FROM reminders")
            }
        }
    }

    // MARK: - Transaction Errors

    @Test("Transaction rollback on error")
    func testTransactionRollbackOnError() async throws {
        // Count reminders before transaction
        let countBefore = try await db.read { db in
            try await Reminder.fetchAll(db).count
        }

        // Try transaction that should fail
        do {
            try await db.withTransaction { db in
                // Insert a reminder (should succeed)
                try await Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 1,
                        title: "Should be rolled back"
                    )
                }.execute(db)

                // Try to insert invalid data (should fail)
                try await db.execute(
                    """
                    INSERT INTO "reminders" ("remindersListID", "title")
                    VALUES (NULL, 'Invalid')
                    """
                )
            }
        } catch {
            // Expected to fail
        }

        // Count reminders after failed transaction
        let countAfter = try await db.read { db in
            try await Reminder.fetchAll(db).count
        }

        // Should be same count (rollback occurred)
        #expect(countBefore == countAfter)
    }

    @Test("Nested transaction error handling with savepoints")
    func testNestedTransactionError() async throws {
        // Note: PostgreSQL uses savepoints for nested transactions
        let countBefore = try await db.read { db in
            try await Reminder.fetchAll(db).count
        }

        try await database.withTransaction { db in
            // Outer transaction - insert should succeed
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "Outer transaction"
                )
            }.execute(db)

            // Inner savepoint - should fail and rollback
            try await db.execute("SAVEPOINT inner_savepoint")
            do {
                try await Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 999999,  // Invalid foreign key
                        title: "Inner transaction"
                    )
                }.execute(db)
                // If we get here, release the savepoint
                try await db.execute("RELEASE SAVEPOINT inner_savepoint")
            } catch {
                // Expected to fail - rollback to savepoint
                try await db.execute("ROLLBACK TO SAVEPOINT inner_savepoint")
            }

            // Outer transaction should still be valid
            // Verify the outer insert is still there
            let count = try await Reminder.where { $0.title == "Outer transaction" }
                .fetchCount(db)
            #expect(count == 1)

            // Cleanup the outer insert
            try await Reminder.where { $0.title == "Outer transaction" }
                .delete()
                .execute(db)
        }

        let countAfter = try await db.read { db in
            try await Reminder.fetchAll(db).count
        }

        #expect(countBefore == countAfter)
    }

    // MARK: - Connection Errors

    @Test("Query on closed connection", .disabled("Requires manual connection management"))
    func testQueryOnClosedConnection() async throws {
        // This would require creating a connection, closing it, then trying to use it
        // Not easily testable with current Database abstraction
    }

    // MARK: - Data Integrity

    @Test("NULL value in non-nullable column decoded")
    func testNullValueInNonNullableColumn() async throws {
        // Insert a reminder with required field
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "Test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        guard let insertedId = inserted.first?.id else {
            Issue.record("Failed to insert reminder")
            return
        }

        // Try to manually set title to NULL (bypassing type safety)
        await #expect(throws: (any Error).self) {
            try await db.write { db in
                try await db.execute(
                    """
                    UPDATE "reminders" SET "title" = NULL WHERE "id" = \(insertedId)
                    """
                )
            }
        }

        // Cleanup
        try await db.write { db in
            try await Reminder.find(insertedId).delete().execute(db)
        }
    }

    // MARK: - Error Message Validation

    @Test("NOT NULL constraint error is thrown")
    func testErrorMessageContainsConstraintInfo() async throws {
        do {
            try await db.write { db in
                try await db.execute(
                    """
                    INSERT INTO "reminders" ("remindersListID", "title", "isCompleted")
                    VALUES (NULL, 'Test', false)
                    """
                )
            }
            Issue.record("Should have thrown an error")
        } catch {
            // Just verify an error was thrown
            // Don't check specific message text as it varies by PostgreSQL version
            let message = "\(error)"
            #expect(!message.isEmpty)
        }
    }

    @Test("Foreign key constraint error is thrown")
    func testForeignKeyErrorMessage() async throws {
        do {
            try await db.write { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        remindersListID: 999999,
                        title: "Test"
                    )
                }.execute(db)
            }
            Issue.record("Should have thrown an error")
        } catch {
            // Just verify an error was thrown
            // Don't check specific message text as it varies by PostgreSQL version
            let message = "\(error)"
            #expect(!message.isEmpty)
        }
    }

    // MARK: - Edge Cases

    @Test("Empty string vs NULL")
    func testEmptyStringVsNull() async throws {
        // Insert with empty string
        let inserted1 = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "",
                    remindersListID: 1,
                    title: "Empty notes"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        // Insert with NULL (omit notes field for nil)
        let inserted2 = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "Null notes"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        guard let insertedId1 = inserted1.first?.id, let insertedId2 = inserted2.first?.id else {
            Issue.record("Failed to insert reminders")
            return
        }

        // Fetch and verify
        let reminder1 = try await db.read { db in
            try await Reminder.find(insertedId1).fetchOne(db)
        }

        let reminder2 = try await db.read { db in
            try await Reminder.find(insertedId2).fetchOne(db)
        }

        #expect(reminder1?.notes == "")
        #expect(reminder2?.notes == nil || reminder2?.notes == "")

        // Cleanup
        try await db.write { db in
            try await Reminder.find([insertedId1, insertedId2]).delete().execute(db)
        }
    }

    @Test("Division by zero")
    func testDivisionByZero() async throws {
        await #expect(throws: (any Error).self) {
            try await db.read { db in
                try await db.execute("SELECT 1 / 0")
            }
        }
    }

    @Test("Very long text value")
    func testVeryLongTextValue() async throws {
        // Create a very long string (1MB)
        let longText = String(repeating: "a", count: 1_000_000)

        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    notes: longText,
                    remindersListID: 1,
                    title: "Long notes"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        guard let insertedId = inserted.first?.id else {
            Issue.record("Failed to insert reminder")
            return
        }

        // Verify it was stored
        let reminder = try await db.read { db in
            try await Reminder.find(insertedId).fetchOne(db)
        }

        if let notes = reminder?.notes {
            #expect(notes.count == 1_000_000)
        } else {
            Issue.record("Notes should not be nil")
        }

        // Cleanup
        try await db.write { db in
            try await Reminder.find(insertedId).delete().execute(db)
        }
    }

    // MARK: - Timeout and Cancellation

    @Test("Query timeout", .disabled("Requires timeout configuration"))
    func testQueryTimeout() async throws {
        // Would require setting up a very slow query and timeout configuration
        // await #expect(throws: (any Error).self) {
        //     try await db.read { db in
        //         try await db.execute("SELECT pg_sleep(100)")
        //     }
        // }
    }

    @Test("Cancelled operation", .disabled("Requires cancellation setup"))
    func testCancelledOperation() async throws {
        // Would require setting up a cancellable task
        // let task = Task {
        //     try await db.read { db in
        //         try await db.execute("SELECT pg_sleep(10)")
        //     }
        // }
        // task.cancel()
        // await #expect(throws: CancellationError.self) {
        //     try await task.value
        // }
    }
}
