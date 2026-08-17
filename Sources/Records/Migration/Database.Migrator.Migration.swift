import Foundation
import PostgreSQL_Standard
private import PostgreSQL_Standard_Macros

extension Database.Migrator {
    // MARK: - Database.Migrator.Migration Table

    /// Internal table for tracking applied database migrations.
    ///
    /// This table is used by `Database.Migrator` to track which migrations
    /// have been applied to the database.
    @Table("__database_migrations")
    struct Migration {
        /// The unique identifier for the migration
        let identifier: String

        /// When the migration was applied
        let appliedAt: Date

        /// Create a new migration record
        init(identifier: String, appliedAt: Date = Date()) {
            self.identifier = identifier
            self.appliedAt = appliedAt
        }
    }
}

// MARK: - Helper Extensions

extension Database.Migrator.Migration {
    /// Fetch all applied migration identifiers
    static func fetchAppliedIdentifiers(
        _ db: some Database.Connection.`Protocol`
    ) async throws(Database.Error) -> Set<String> {
        let migrations = try await Database.Migrator.Migration.fetchAll(db)
        return Set(migrations.map { $0.identifier })
    }

    /// Record a migration as applied
    static func recordMigration(
        identifier: String,
        db: some Database.Connection.`Protocol`
    ) async throws(Database.Error) {
        try await Database.Migrator.Migration.insert {
            Database.Migrator.Migration(identifier: identifier)
        }.execute(db)
    }

    /// Check if a specific migration has been applied
    static func hasApplied(
        identifier: String,
        db: some Database.Connection.`Protocol`
    ) async throws(Database.Error) -> Bool {
        let migration = try await Database.Migrator.Migration
            .where { $0.identifier == identifier }
            .fetchOne(db)

        return migration != nil
    }
}
