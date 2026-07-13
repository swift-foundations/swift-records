import Dependencies
import Foundation
import PostgresNIO
import Records
import PostgreSQL_Standard
import Testing

// MARK: - Test Database Setup (Reminder Schema - Upstream Compatible)
//
// This schema matches upstream Point-Free packages:
// - pointfreeco/swift-structured-queries
// - pointfreeco/sqlite-data
//
// Provides test isolation and consistency with the ecosystem

extension Database.Writer {
    /// Creates the Reminder test schema (matches upstream swift-structured-queries)
    package func createReminderSchema() async throws {
        try await self.write { db in
            // Create remindersLists table
            try await db.execute(
                """
                    CREATE TABLE "remindersLists" (
                        "id" SERIAL PRIMARY KEY,
                        "color" INTEGER NOT NULL DEFAULT 4889071,
                        "title" TEXT NOT NULL DEFAULT '',
                        "position" INTEGER NOT NULL DEFAULT 0
                    )
                """
            )

            // Create unique index on title
            try await db.execute(
                """
                    CREATE UNIQUE INDEX "remindersLists_title" ON "remindersLists"("title")
                """
            )

            // Create reminders table
            try await db.execute(
                """
                    CREATE TABLE "reminders" (
                        "id" SERIAL PRIMARY KEY,
                        "assignedUserID" INTEGER,
                        "dueDate" DATE,
                        "isCompleted" BOOLEAN NOT NULL DEFAULT false,
                        "isFlagged" BOOLEAN NOT NULL DEFAULT false,
                        "notes" TEXT NOT NULL DEFAULT '',
                        "priority" INTEGER,
                        "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE,
                        "title" TEXT NOT NULL DEFAULT '',
                        "updatedAt" TIMESTAMP NOT NULL DEFAULT '2040-02-14 23:31:30'
                    )
                """
            )

            // Create users table (simple version for reminders)
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS "users" (
                        "id" SERIAL PRIMARY KEY,
                        "name" TEXT NOT NULL DEFAULT ''
                    )
                """
            )

            // Create index on remindersListID
            try await db.execute(
                """
                    CREATE INDEX "index_reminders_on_remindersListID"
                    ON "reminders"("remindersListID")
                """
            )

            // Create tags table
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS "tags" (
                        "id" SERIAL PRIMARY KEY,
                        "title" TEXT NOT NULL UNIQUE
                    )
                """
            )

            // Create remindersTags junction table
            try await db.execute(
                """
                    CREATE TABLE "remindersTags" (
                        "reminderID" INTEGER NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                        "tagID" INTEGER NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE,
                        PRIMARY KEY ("reminderID", "tagID")
                    )
                """
            )
        }
    }

    /// Inserts Reminder sample data (matches upstream test data)
    package func insertReminderSampleData() async throws {
        try await self.write { db in
            // Insert reminders lists
            try await db.execute(
                """
                    INSERT INTO "remindersLists" ("id", "color", "title", "position") VALUES
                    (1, 4889071, 'Home', 0),
                    (2, 16744448, 'Work', 1)
                """
            )

            // Insert users
            try await db.execute(
                """
                    INSERT INTO "users" ("id", "name") VALUES
                    (1, 'Alice'),
                    (2, 'Bob')
                """
            )

            // Insert reminders
            try await db.execute(
                """
                    INSERT INTO "reminders"
                    ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
                    VALUES
                    (1, 1, '2001-01-01', false, false, 'Milk, Eggs, Apples', NULL, 1, 'Groceries', '2040-02-14 23:31:30'),
                    (2, NULL, '2000-12-30', false, true, '', NULL, 1, 'Haircut', '2040-02-14 23:31:30'),
                    (3, NULL, '2001-01-01', false, false, 'Ask about diet', 3, 1, 'Vet appointment', '2040-02-14 23:31:30'),
                    (4, 2, '2001-01-02', true, false, '', 1, 2, 'Finish report', '2040-02-14 23:31:30'),
                    (5, NULL, '2001-01-03', false, true, 'Prepare slides', 1, 2, 'Team meeting', '2040-02-14 23:31:30'),
                    (6, 1, '2001-01-04', false, false, '', 2, 2, 'Review PR', '2040-02-14 23:31:30')
                """
            )

            // Insert tags
            try await db.execute(
                """
                    INSERT INTO "tags" ("id", "title") VALUES
                    (1, 'car'),
                    (2, 'kids'),
                    (3, 'someday'),
                    (4, 'optional')
                """
            )

            // Insert reminder-tag relationships
            try await db.execute(
                """
                    INSERT INTO "remindersTags" ("reminderID", "tagID") VALUES
                    (1, 1),
                    (1, 2),
                    (2, 1),
                    (3, 4)
                """
            )

            // Reset sequences to correct values after explicit inserts
            // Note: PostgreSQL creates sequences with quoted table names as "tableName_columnName_seq"
            try await db.execute(
                """
                    SELECT setval(pg_get_serial_sequence('"remindersLists"', 'id'), (SELECT MAX(id) FROM "remindersLists"))
                """
            )

            try await db.execute(
                """
                    SELECT setval(pg_get_serial_sequence('"reminders"', 'id'), (SELECT MAX(id) FROM "reminders"))
                """
            )

            try await db.execute(
                """
                    SELECT setval(pg_get_serial_sequence('"users"', 'id'), (SELECT MAX(id) FROM "users"))
                """
            )

            try await db.execute(
                """
                    SELECT setval(pg_get_serial_sequence('"tags"', 'id'), (SELECT MAX(id) FROM "tags"))
                """
            )
        }
    }
}

// MARK: - Test Database Storage

/// Global storage for test databases - prevents deallocation forever
/// This is intentionally a global variable (not in an actor) to survive process exit
/// Marked nonisolated(unsafe) because it's only appended to, never read, and
/// concurrent appends are acceptable (we don't care about order or duplicates)
private nonisolated(unsafe) var _testDatabaseStorage: [Database.TestDatabase] = []

/// Storage function - appends database to global storage to prevent deallocation
private func storeTestDatabase(_ database: Database.TestDatabase) {
    _testDatabaseStorage.append(database)
}

/// A simple lazy wrapper for test databases
///
/// **Design Decision**: Global variable storage prevents deallocation
///
/// ## Approach
/// - Each test suite gets its OWN isolated database
/// - All databases stored in global array - NEVER deallocated
/// - Global variable survives process exit cleanup
/// - This prevents ClientRunner deinit from running during shutdown
/// - Simple lazy property with Task-based synchronization
///
/// ## Why This Works
/// - Tests execute successfully ✅
/// - xcodebuild completes without hanging ✅
/// - No ClientRunner deinit = no async cleanup during exit ✅
/// - Each test suite isolated from others ✅
///
/// Each test suite gets its own isolated database for data isolation.
public final class LazyTestDatabase: Database.Writer, NotificationCapable, @unchecked Sendable {
    private let setupMode: Database.TestDatabaseSetupMode

    // Lazy database creation with Task-based synchronization
    private var _database: Database.TestDatabase?
    private var _creationTask: Task<Database.TestDatabase, Error>?

    /// Exposes the underlying PostgresClient if available (for notification support)
    public var postgresClient: PostgresClient? {
        get async throws {
            let db = try await getOrCreateDatabase()
            return db.postgresClient
        }
    }

    private func getOrCreateDatabase() async throws -> Database.TestDatabase {
        // Check if already created
        if let existing = _database {
            return existing
        }

        // Check if creation is in progress
        if let task = _creationTask {
            return try await task.value
        }

        // Create new task for database creation
        let task = Task<Database.TestDatabase, Error> {
            // Create database with single connection
            let db = try await Database.testDatabase(
                configuration: nil,
                prefix: "test"
            )

            // Run setup mode configuration
            try await self.setupMode.setup(db)

            // Store in global variable to prevent deallocation
            storeTestDatabase(db)

            return db
        }

        _creationTask = task
        let db = try await task.value
        _database = db
        _creationTask = nil

        return db
    }

    /// Initialize a lazy test database (synchronous - no async needed!)
    ///
    /// - Parameters:
    ///   - setupMode: Schema and data setup mode
    public init(setupMode: Database.TestDatabaseSetupMode) {
        self.setupMode = setupMode
    }

    public func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let db = try await getOrCreateDatabase()
        return try await db.read(block)
    }

    public func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let db = try await getOrCreateDatabase()
        return try await db.write(block)
    }

    public func close() async throws {
        // No-op: databases stored in global actor are never cleaned up
        // This prevents ClientRunner deinit hangs
    }

    // NO deinit - we don't own the database, global actor does
}

// MARK: - Convenience Factory Method

extension Database.TestDatabase {
    /// Creates a test database with Reminder schema and sample data (lazy initialization)
    ///
    /// This is the standard test database setup matching upstream Point-Free patterns.
    /// All tests should use this setup for consistency with the ecosystem.
    public static func withReminderData() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withReminderData)
    }
}
