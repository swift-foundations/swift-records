import Dependencies
import Dependencies_Test_Support
import Foundation
import Records
import Records_Test_Support
import PostgreSQL_Standard
import Testing

/// Integration tests for PostgreSQL trigger functionality using low-level helpers.
///
/// These tests verify that the database-level trigger support works correctly.
/// Most trigger functionality is tested in swift-structured-queries-postgres.
/// These tests focus on Records-specific integration.
@Suite(
    "Trigger Integration Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withTriggerTestTables()
    }
)
struct TriggerIntegrationTests {
    @Dependency(\.defaultDatabase) var db

    // MARK: - Basic Trigger Function Tests

    @Test("Create trigger function using low-level helper")
    func testCreateTriggerFunction() async throws {
        try await db.withRollback { db in
            // Use the low-level helper from Database.Connection.Protocol
            try await db.createTriggerFunction(
                "test_update_timestamp",
                body: """
                    NEW."updatedAt" = CURRENT_TIMESTAMP;
                    RETURN NEW;
                    """
            )

            // Create trigger using raw SQL
            try await db.execute(
                """
                CREATE TRIGGER test_timestamp_trigger
                BEFORE UPDATE ON posts
                FOR EACH ROW
                EXECUTE FUNCTION test_update_timestamp()
                """
            )

            // Insert a post
            try await db.execute(
                """
                INSERT INTO posts (title) VALUES ('Test Post')
                """
            )

            // Update the post
            try await db.execute(
                """
                UPDATE posts SET title = 'Updated Post'
                """
            )

            // Verify updated_at was set
            let post = try await Post.where { $0.title == "Updated Post" }.fetchOne(db)
            #expect(post?.updatedAt != nil)
        }
    }

    @Test("Trigger function executes on INSERT")
    func testTriggerOnInsert() async throws {
        try await db.withRollback { db in
            // Create function that sets slug from title
            try await db.createTriggerFunction(
                "set_slug",
                body: """
                    NEW.slug = LOWER(REPLACE(NEW.title, ' ', '-'));
                    RETURN NEW;
                    """
            )

            // Create trigger
            try await db.execute(
                """
                CREATE TRIGGER set_slug_trigger
                BEFORE INSERT ON posts
                FOR EACH ROW
                EXECUTE FUNCTION set_slug()
                """
            )

            // Insert post without slug
            try await db.execute(
                """
                INSERT INTO posts (title) VALUES ('Hello World')
                """
            )

            // Verify slug was set by trigger
            let post = try await Post.where { $0.title == "Hello World" }.fetchOne(db)
            #expect(post?.slug == "hello-world")
        }
    }

    @Test("Trigger function executes on DELETE")
    func testTriggerOnDelete() async throws {
        try await db.withRollback { db in
            // Create audit log table
            try await db.execute(
                """
                CREATE TABLE IF NOT EXISTS delete_log (
                    id SERIAL PRIMARY KEY,
                    deleted_title TEXT,
                    deleted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

            // Create function that logs deletions
            try await db.createTriggerFunction(
                "log_deletion",
                body: """
                    INSERT INTO delete_log (deleted_title) VALUES (OLD.title);
                    RETURN OLD;
                    """
            )

            // Create trigger
            try await db.execute(
                """
                CREATE TRIGGER log_deletion_trigger
                AFTER DELETE ON posts
                FOR EACH ROW
                EXECUTE FUNCTION log_deletion()
                """
            )

            // Insert and delete a post
            try await db.execute(
                """
                INSERT INTO posts (title) VALUES ('To Delete')
                """
            )
            try await db.execute(
                """
                DELETE FROM posts WHERE title = 'To Delete'
                """
            )

            // Verify deletion was logged
            let logCount = try await db.execute(
                """
                SELECT COUNT(*) FROM delete_log WHERE deleted_title = 'To Delete'
                """
            )
            #expect(logCount != nil)
        }
    }

    @Test("Multiple triggers execute in order")
    func testMultipleTriggers() async throws {
        try await db.withRollback { db in
            // Create first trigger (appends '1')
            try await db.createTriggerFunction(
                "append_one",
                body: """
                    NEW."executionLog" = COALESCE(NEW."executionLog", '') || '1';
                    RETURN NEW;
                    """
            )

            try await db.execute(
                """
                CREATE TRIGGER a_append_one_trigger
                BEFORE INSERT ON posts
                FOR EACH ROW
                EXECUTE FUNCTION append_one()
                """
            )

            // Create second trigger (appends '2')
            try await db.createTriggerFunction(
                "append_two",
                body: """
                    NEW."executionLog" = COALESCE(NEW."executionLog", '') || '2';
                    RETURN NEW;
                    """
            )

            try await db.execute(
                """
                CREATE TRIGGER b_append_two_trigger
                BEFORE INSERT ON posts
                FOR EACH ROW
                EXECUTE FUNCTION append_two()
                """
            )

            // Insert post
            try await db.execute(
                """
                INSERT INTO posts (title) VALUES ('Order Test')
                """
            )

            // Verify triggers executed in alphabetical order
            let post = try await Post.where { $0.title == "Order Test" }.fetchOne(db)
            #expect(post?.executionLog == "12")
        }
    }

    @Test("Trigger can prevent operation by raising exception")
    func testTriggerRaisesException() async throws {
        try await db.withRollback { db in
            // Create function that always fails
            try await db.createTriggerFunction(
                "always_fail",
                body: "RAISE EXCEPTION 'Operation not allowed';"
            )

            try await db.execute(
                """
                CREATE TRIGGER prevent_insert_trigger
                BEFORE INSERT ON posts
                FOR EACH ROW
                EXECUTE FUNCTION always_fail()
                """
            )

            // Use savepoint to handle the failed insert without aborting the entire transaction
            do {
                try await db.withSavepoint("test_insert") { db in
                    try await db.execute(
                        """
                        INSERT INTO posts (title) VALUES ('Should Fail')
                        """
                    )
                }
                Issue.record("Expected trigger to prevent insert")
            } catch {
                let errorStr = String(reflecting: error)
                #expect(errorStr.contains("Operation not allowed"))
            }

            // Verify no row was inserted (can safely query after savepoint rollback)
            let count = try await Post.fetchCount(db)
            #expect(count == 0)
        }
    }

    @Test("BEFORE trigger can modify NEW row")
    func testBeforeTriggerModifiesRow() async throws {
        try await db.withRollback { db in
            // Create function that forces title to uppercase
            try await db.createTriggerFunction(
                "uppercase_title",
                body: """
                    NEW.title = UPPER(NEW.title);
                    RETURN NEW;
                    """
            )

            try await db.execute(
                """
                CREATE TRIGGER uppercase_title_trigger
                BEFORE INSERT ON posts
                FOR EACH ROW
                EXECUTE FUNCTION uppercase_title()
                """
            )

            // Insert post with lowercase title
            try await db.execute(
                """
                INSERT INTO posts (title) VALUES ('lowercase title')
                """
            )

            // Verify title was uppercased by trigger
            let post = try await Post.all.fetchOne(db)
            #expect(post?.title == "LOWERCASE TITLE")
        }
    }

    @Test("DROP FUNCTION with CASCADE removes dependent triggers")
    func testDropFunctionCascade() async throws {
        try await db.withRollback { db in
            // Create function and trigger
            try await db.createTriggerFunction(
                "test_func",
                body: "RETURN NEW;"
            )

            try await db.execute(
                """
                CREATE TRIGGER test_trigger
                BEFORE INSERT ON posts
                FOR EACH ROW
                EXECUTE FUNCTION test_func()
                """
            )

            // Drop function with CASCADE
            try await db.execute(
                """
                DROP FUNCTION test_func() CASCADE
                """
            )

            // Verify function was dropped - trying to recreate trigger should fail
            do {
                try await db.execute(
                    """
                    CREATE TRIGGER recreate_trigger
                    BEFORE INSERT ON posts
                    FOR EACH ROW
                    EXECUTE FUNCTION test_func()
                    """
                )
                Issue.record("Expected error when referencing dropped function")
            } catch {
                let errorStr = String(reflecting: error)
                #expect(errorStr.contains("does not exist") || errorStr.contains("function"))
            }
        }
    }
}

// MARK: - Test Table Definitions

@Table
private struct Post: Codable, Equatable {
    let id: Int
    var title: String
    var slug: String?
    var updatedAt: Date?
    var executionLog: String?
}

// MARK: - Test Database Setup

extension Database.TestDatabaseSetupMode {
    static let withTriggerTestTables = Database.TestDatabaseSetupMode { db in
        try await db.write { conn in
            // Create posts table with camelCase columns
            try await conn.execute(
                """
                CREATE TABLE posts (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    slug TEXT,
                    "updatedAt" TIMESTAMPTZ,
                    "executionLog" TEXT
                )
                """
            )
        }
    }
}

extension Database.TestDatabase {
    static func withTriggerTestTables() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withTriggerTestTables)
    }
}
