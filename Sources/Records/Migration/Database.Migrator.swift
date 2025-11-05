import Foundation
import IssueReporting
import StructuredQueriesPostgres

// MARK: - Database.Migrator

extension Database {
    /// Manages database schema migrations.
    ///
    /// `Database.Migrator` tracks and applies database migrations in order.
    /// Each migration is identified by a unique identifier and is executed only once.
    ///
    /// ```swift
    /// var migrator = Database.Migrator()
    ///
    /// migrator.registerMigration("Create users table") { db in
    ///     try await #sql("""
    ///         CREATE TABLE users (
    ///             id UUID PRIMARY KEY,
    ///             name TEXT NOT NULL,
    ///             email TEXT UNIQUE NOT NULL
    ///         )
    ///     """).execute(db)
    /// }
    ///
    /// migrator.registerMigration("Add created_at to users") { db in
    ///     try await #sql("""
    ///         ALTER TABLE users
    ///         ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ///     """).execute(db)
    /// }
    ///
    /// try await migrator.migrate(database)
    /// ```
    ///
    /// ## Migration Best Practices
    ///
    /// ### Organizing Migrations
    ///
    /// ```swift
    /// extension Database.Migrator {
    ///     static func appMigrations() -> Database.Migrator {
    ///         var migrator = Database.Migrator()
    ///
    ///         // Initial schema
    ///         migrator.registerMigration("001_create_users") { db in
    ///             try await db.execute("""
    ///                 CREATE TABLE users (
    ///                     id UUID PRIMARY KEY,
    ///                     email TEXT UNIQUE NOT NULL
    ///                 )
    ///             """)
    ///         }
    ///
    ///         // Add columns
    ///         migrator.registerMigration("002_add_user_timestamps") { db in
    ///             try await db.execute("""
    ///                 ALTER TABLE users
    ///                 ADD COLUMN created_at TIMESTAMP DEFAULT NOW(),
    ///                 ADD COLUMN updated_at TIMESTAMP DEFAULT NOW()
    ///             """)
    ///         }
    ///
    ///         // Add indexes
    ///         migrator.registerMigration("003_add_email_index") { db in
    ///             try await db.execute("""
    ///                 CREATE INDEX idx_users_email ON users(email)
    ///             """)
    ///         }
    ///
    ///         return migrator
    ///     }
    /// }
    /// ```
    ///
    /// ### Handling Failed Migrations
    ///
    /// ```swift
    /// do {
    ///     let migrator = Database.Migrator.appMigrations()
    ///     try await migrator.migrate(database)
    /// } catch Database.Error.migrationFailed(let id, let error) {
    ///     logger.error("Migration '\(id)' failed: \(error)")
    ///     // In development, you might want to reset:
    ///     if isDevelopment {
    ///         var migrator = Database.Migrator.appMigrations()
    ///         migrator.eraseDatabaseOnSchemaChange = true
    ///         try await migrator.migrate(database)
    ///     } else {
    ///         throw error
    ///     }
    /// }
    /// ```
    ///
    /// ### Data Migrations
    ///
    /// ```swift
    /// migrator.registerMigration("004_normalize_emails") { db in
    ///     // First add the new column
    ///     try await db.execute("""
    ///         ALTER TABLE users
    ///         ADD COLUMN email_normalized TEXT
    ///     """)
    ///
    ///     // Migrate existing data
    ///     let users = try await User.fetchAll(db)
    ///     for user in users {
    ///         let normalized = user.email.lowercased()
    ///         try await User
    ///             .filter { $0.id == user.id }
    ///             .update { $0.emailNormalized = normalized }
    ///             .execute(db)
    ///     }
    ///
    ///     // Make it required and unique
    ///     try await db.execute("""
    ///         ALTER TABLE users
    ///         ALTER COLUMN email_normalized SET NOT NULL,
    ///         ADD CONSTRAINT uk_users_email_normalized UNIQUE(email_normalized)
    ///     """)
    /// }
    /// ```
    public struct Migrator: Sendable {
        private var migrations:
            [(
                identifier: String,
                migrate: @Sendable (any Database.Connection.`Protocol`) async throws -> Void
            )] = []
        #if DEBUG
            /// If true, the migrator recreates the whole database from scratch
            /// if it detects a change in migration definitions.
            ///
            /// - warning: This flag can destroy data! Use only during development.
            public var eraseDatabaseOnSchemaChange = false
        #endif

        /// The foreign key checking strategy.
        public var foreignKeyChecks: ForeignKeyChecks = .deferred

        /// Creates a new database migrator.
        public init() {}

        /// Registers a migration.
        ///
        /// - Parameters:
        ///   - identifier: A unique identifier for this migration.
        ///   - foreignKeyChecks: How to handle foreign key constraints.
        ///   - migrate: The migration to execute.
        public mutating func registerMigration(
            _ identifier: String,
            foreignKeyChecks: ForeignKeyChecks? = nil,
            migrate: @escaping @Sendable (any Database.Connection.`Protocol`) async throws -> Void
        ) {
            // Check for duplicate identifiers
            if migrations.contains(where: { $0.identifier == identifier }) {
                reportIssue("Migration with identifier '\(identifier)' is already registered")
                return
            }

            migrations.append((identifier, migrate))
        }

        /// Migrates the database.
        ///
        /// - Parameter writer: The database to migrate.
        public func migrate(_ writer: any Writer) async throws {
            try await writer.write { db in
                // Create migration tracking table if it doesn't exist
                try await createMigrationTable(db)

                // Get applied migrations
                let appliedIdentifiers = try await fetchAppliedIdentifiers(db)
                #if DEBUG
                    // Check for schema changes if needed
                    if eraseDatabaseOnSchemaChange {
                        let hasChanges = try await hasSchemaChanges(
                            db,
                            appliedIdentifiers: appliedIdentifiers
                        )
                        if hasChanges {
                            try await eraseDatabaseContent(db)
                            try await createMigrationTable(db)
                        }
                    }
                #endif

                // Apply pending migrations
                for (identifier, migrate) in migrations {
                    if !appliedIdentifiers.contains(identifier) {
                        try await applyMigration(identifier: identifier, migrate: migrate, db: db)
                    }
                }
            }
        }

        /// Returns the identifiers of applied migrations.
        ///
        /// - Parameter db: A database connection.
        /// - Returns: A set of applied migration identifiers.
        public func appliedIdentifiers(_ db: any Database.Connection.`Protocol`) async throws
            -> Set<
                String
            >
        {
            try await fetchAppliedIdentifiers(db)
        }

        /// Returns true if the database has completed all registered migrations.
        ///
        /// - Parameter writer: The database to check.
        /// - Returns: True if all migrations have been applied.
        public func hasCompletedMigrations(_ writer: any Writer) async throws -> Bool {
            try await writer.read { db in
                let appliedIdentifiers = try await fetchAppliedIdentifiers(db)
                return migrations.allSatisfy { appliedIdentifiers.contains($0.identifier) }
            }
        }

        // MARK: - Private Methods

        private func createMigrationTable(_ db: any Database.Connection.`Protocol`) async throws {
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS __database_migrations (
                        identifier TEXT PRIMARY KEY,
                        "appliedAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """
            )
        }

        private func fetchAppliedIdentifiers(_ db: any Database.Connection.`Protocol`) async throws
            -> Set<String>
        {
            // Ensure migration table exists (for backward compatibility)
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS __database_migrations (
                        identifier TEXT PRIMARY KEY,
                        "appliedAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """
            )

            // Fetch applied migrations using the Database.Migrator.Migration table
            return try await Database.Migrator.Migration.fetchAppliedIdentifiers(db)
        }

        private func applyMigration(
            identifier: String,
            migrate: @Sendable (any Database.Connection.`Protocol`) async throws -> Void,
            db: any Database.Connection.`Protocol`
        ) async throws {
            // Handle foreign key checks
            let restoreForeignKeys = foreignKeyChecks == .deferred

            if restoreForeignKeys {
                try await db.execute("SET session_replication_role = 'replica'")
            }

            do {
                // Run the migration
                try await migrate(db)

                // Record the migration using structured insert
                try await Database.Migrator.Migration.recordMigration(
                    identifier: identifier,
                    db: db
                )

                if restoreForeignKeys {
                    try await db.execute("SET session_replication_role = 'origin'")
                }
            } catch {
                if restoreForeignKeys {
                    try? await db.execute("SET session_replication_role = 'origin'")
                }
                throw error
            }
        }

        private func hasSchemaChanges(
            _ db: any Database.Connection.`Protocol`,
            appliedIdentifiers: Set<String>
        ) async throws -> Bool {
            // Check if migrations have been removed or renamed
            let registeredIdentifiers = Set(migrations.map(\.identifier))
            return !appliedIdentifiers.isSubset(of: registeredIdentifiers)
        }
        #if DEBUG
            private func eraseDatabaseContent(_ db: any Database.Connection.`Protocol`) async throws
            {
                // Drop all tables in the public schema
                try await db.execute(
                    """
                        DO $$
                        DECLARE
                            r RECORD;
                        BEGIN
                            FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
                                EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
                            END LOOP;
                        END $$;
                    """
                )
            }
        #endif
    }
}

// MARK: - Database.Migrator.ForeignKeyChecks

extension Database.Migrator {
    /// Controls how migrations handle foreign key constraints.
    public enum ForeignKeyChecks: Sendable {
        /// Foreign keys are checked after the migration completes.
        case deferred
        /// Foreign keys are checked immediately.
        case immediate
    }
}
