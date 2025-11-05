import Foundation
import PostgresNIO
import Records
import StructuredQueriesPostgres

extension Database {
    /// A test database wrapper that provides schema isolation for tests
    public final class TestDatabase: Writer, NotificationCapable, @unchecked Sendable {
        private let wrapped: any Writer
        private let schemaName: String

        /// Exposes the underlying PostgresClient if available (for notification support)
        public var postgresClient: PostgresClient? {
            if let testConn = wrapped as? TestConnection {
                return testConn.postgresClient
            }
            return wrapped as? PostgresClient
        }

        init(wrapped: any Writer, schemaName: String) {
            self.wrapped = wrapped
            self.schemaName = schemaName
        }

        deinit {
            // Schema will persist for process lifetime (acceptable for tests)
            // No cleanup to prevent hangs during process exit
        }

        public func read<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await wrapped.read { db in
                // Ensure schema is set for this connection
                try await db.execute("SET search_path TO \(schemaName)")
                return try await block(db)
            }
        }

        public func write<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await wrapped.write { db in
                // Ensure schema is set for this connection
                try await db.execute("SET search_path TO \(schemaName)")
                return try await block(db)
            }
        }

        public func close() async throws {
            // No-op: Schemas persist for process lifetime (intentional for tests)
            // Cleanup would cause hangs during process exit
        }
    }
}

// MARK: - Setup Mode

extension Database {
    /// Setup mode for test databases
    ///
    /// A flexible, extensible way to configure test database initialization.
    /// Users can create custom setup modes by extending this struct with static properties.
    ///
    /// ## Built-in Mode
    /// - `.withReminderData`: Reminder schema with sample data (default for all tests)
    ///
    /// ## Upstream Compatibility
    /// This schema matches Point-Free's test patterns:
    /// - pointfreeco/swift-structured-queries
    /// - pointfreeco/sqlite-data
    ///
    /// ## Custom Modes
    /// ```swift
    /// extension Database.TestDatabaseSetupMode {
    ///     static let withMyData = TestDatabaseSetupMode { db in
    ///         try await db.createReminderSchema()
    ///         try await db.write { conn in
    ///             try await conn.execute("INSERT INTO ...")
    ///         }
    ///     }
    /// }
    /// ```
    public struct TestDatabaseSetupMode: Sendable {
        let setup: @Sendable (any Database.Writer) async throws -> Void

        /// Create a custom setup mode
        ///
        /// - Parameter setup: Async closure that configures the database
        public init(setup: @escaping @Sendable (any Database.Writer) async throws -> Void) {
            self.setup = setup
        }

        /// Reminder schema with sample data (upstream compatibility)
        ///
        /// Creates reminders schema matching swift-structured-queries upstream tests.
        /// Inserts sample reminders, lists, users, and tags.
        ///
        /// This is the standard test schema for all swift-records tests.
        public static let withReminderData = TestDatabaseSetupMode { db in
            try await db.createReminderSchema()
            try await db.insertReminderSampleData()
        }
    }
}

// MARK: - Factory Methods

extension Database {
    /// Creates a test database with an isolated schema
    ///
    /// Each call creates a new schema with a unique name, providing complete isolation
    /// for test suites. The schema is automatically set as the search path.
    ///
    /// - Parameters:
    ///   - configuration: Optional database configuration. Uses environment if not provided.
    ///   - prefix: Optional prefix for the schema name (default: "test")
    /// - Returns: A test database with isolated schema
    public static func testDatabase(
        configuration: PostgresClient.Configuration? = nil,
        prefix: String = "test"
    ) async throws -> TestDatabase {
        // Generate unique schema name
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let schemaName = "\(prefix)_\(uuid)"

        // Create direct connection without background tasks
        // This prevents hanging on test exit
        let config = try configuration ?? PostgresClient.Configuration.fromEnvironment()
        let database = await TestConnection(configuration: config)

        // Create and use test schema
        try await database.write { db in
            try await db.execute("CREATE SCHEMA \(schemaName)")
            try await db.execute("SET search_path TO \(schemaName)")
        }

        return TestDatabase(
            wrapped: database,
            schemaName: schemaName
        )
    }

    /// Creates a test database pool with an isolated schema
    public static func testDatabasePool(
        configuration: PostgresClient.Configuration? = nil,
        minConnections: Int = 2,
        maxConnections: Int = 5,
        prefix: String = "test"
    ) async throws -> TestDatabase {
        // Generate unique schema name
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let schemaName = "\(prefix)_\(uuid)"

        // For test pool, just create multiple single connections
        // This prevents hanging on test exit from background tasks
        let config = try configuration ?? PostgresClient.Configuration.fromEnvironment()

        // For simplicity in tests, use a single connection even for "pool"
        // Real pooling not needed for tests
        let pool = await TestConnection(configuration: config)

        // Create and use test schema
        try await pool.write { db in
            try await db.execute("CREATE SCHEMA \(schemaName)")
            try await db.execute("SET search_path TO \(schemaName)")
        }

        return TestDatabase(
            wrapped: pool,
            schemaName: schemaName
        )
    }
}

// MARK: - Convenience

extension Database {
    /// Executes a block with a test database
    ///
    /// Note: Schema persists for process lifetime (acceptable for tests)
    public static func withTestDatabase<T>(
        configuration: PostgresClient.Configuration? = nil,
        prefix: String = "test",
        _ block: (TestDatabase) async throws -> T
    ) async throws -> T {
        let database = try await testDatabase(
            configuration: configuration,
            prefix: prefix
        )
        return try await block(database)
    }
}
