import Foundation
import PostgresNIO
import StructuredQueriesPostgres

// MARK: - Supporting Types

/// Trigger configuration type for full-text search.
public enum SearchVectorTriggerType: Sendable {
    /// Uses PostgreSQL's built-in `tsvector_update_trigger()` function.
    /// All source columns get the same weight (D).
    case automatic

    /// Creates a custom trigger function with weighted columns.
    case custom
}

/// Weighted column configuration for custom triggers.
public struct WeightedColumn: Sendable {
    public let name: String
    public let weight: TextSearch.Weight

    public init(name: String, weight: TextSearch.Weight) {
        self.name = name
        self.weight = weight
    }
}

/// Index method for full-text search.
public enum FTSIndexMethod: Sendable {
    /// GIN index (faster searches, slower updates)
    case gin

    /// GiST index (slower searches, faster updates)
    case gist
}

// MARK: - Database Error Extension

extension Database.Error {
    /// Invalid argument provided to a function.
    public static func invalidArgument(_ message: String) -> Database.Error {
        .invalidConfiguration(message: message)
    }
}

// MARK: - Language Validation

/// Validates that a language string is safe for use in SQL.
///
/// This prevents SQL injection by ensuring the language parameter only contains
/// alphanumeric characters and underscores (valid PostgreSQL text search configuration names).
///
/// - Parameter language: The language/configuration name to validate
/// - Throws: Database.Error.invalidArgument if language contains invalid characters
private func validateLanguage(_ language: String) throws {
    let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    guard language.unicodeScalars.allSatisfy({ allowedCharacterSet.contains($0) }) else {
        throw Database.Error.invalidArgument(
            "Invalid language '\(language)': must contain only alphanumeric characters and underscores"
        )
    }
    guard !language.isEmpty else {
        throw Database.Error.invalidArgument("Language cannot be empty")
    }
}

// MARK: - Full-Text Search Database Operations

extension Database.Connection.`Protocol` {

    // MARK: - Index Creation

    /// Creates a GIN index for full-text search on a tsvector column.
    ///
    /// GIN (Generalized Inverted Index) indexes are the recommended index type for
    /// full-text search as they provide faster searches but slower updates.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.createGINIndex(
    ///         on: "articles",
    ///         column: "search_vector",
    ///         name: "articles_search_idx",
    ///         concurrently: true  // Recommended for production
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The tsvector column name
    ///   - name: The index name (defaults to "<table>_<column>_idx")
    ///   - concurrently: Create index without locking table (default: true, recommended for production)
    ///   - ifNotExists: Whether to skip if index already exists (default: true)
    /// - Throws: Database error if index creation fails
    public func createGINIndex(
        on table: String,
        column: String,
        name: String? = nil,
        concurrently: Bool = true,
        ifNotExists: Bool = true
    ) async throws {
        let indexName = name ?? "\(table)_\(column)_idx"
        let concurrentlyKeyword = concurrently ? "CONCURRENTLY " : ""
        let notExists = ifNotExists ? "IF NOT EXISTS " : ""

        let sql = """
            CREATE INDEX \(concurrentlyKeyword)\(notExists)\(indexName.quoted())
            ON \(table.quoted())
            USING GIN (\(column.quoted()))
            """
        print("🔍 Creating GIN index '\(indexName)' on table '\(table)' column '\(column)'")
        do {
            try await execute(sql)
            print("✅ Successfully created GIN index '\(indexName)'")
        } catch {
            print("❌ Failed to create GIN index: \(String(reflecting: error))")
            throw error
        }
    }

    /// Creates a GIN index on a tsvector expression (multi-column).
    ///
    /// Use this when you want to index a computed tsvector from multiple columns.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.createGINIndexOnExpression(
    ///         on: "articles",
    ///         expression: "to_tsvector('english', title || ' ' || body)",
    ///         name: "articles_fts_idx",
    ///         concurrently: true
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - expression: The SQL expression that produces a tsvector
    ///   - name: The index name
    ///   - concurrently: Create index without locking table (default: true)
    ///   - ifNotExists: Whether to skip if index already exists (default: true)
    /// - Throws: Database error if index creation fails
    public func createGINIndexOnExpression(
        on table: String,
        expression: String,
        name: String,
        concurrently: Bool = true,
        ifNotExists: Bool = true
    ) async throws {
        let concurrentlyKeyword = concurrently ? "CONCURRENTLY " : ""
        let notExists = ifNotExists ? "IF NOT EXISTS " : ""

        try await execute(
            """
            CREATE INDEX \(concurrentlyKeyword)\(notExists)\(name.quoted())
            ON \(table.quoted())
            USING GIN ((\(expression)))
            """
        )
    }

    /// Creates a GiST index for full-text search on a tsvector column.
    ///
    /// GiST (Generalized Search Tree) indexes are slower for searches but faster
    /// for updates. Use GiST if your data changes frequently.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.createGiSTIndex(
    ///         on: "articles",
    ///         column: "search_vector",
    ///         concurrently: true
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The tsvector column name
    ///   - name: The index name (defaults to "<table>_<column>_gist_idx")
    ///   - concurrently: Create index without locking table (default: true)
    ///   - ifNotExists: Whether to skip if index already exists (default: true)
    /// - Throws: Database error if index creation fails
    public func createGiSTIndex(
        on table: String,
        column: String,
        name: String? = nil,
        concurrently: Bool = true,
        ifNotExists: Bool = true
    ) async throws {
        let indexName = name ?? "\(table)_\(column)_gist_idx"
        let concurrentlyKeyword = concurrently ? "CONCURRENTLY " : ""
        let notExists = ifNotExists ? "IF NOT EXISTS " : ""

        let sql = """
            CREATE INDEX \(concurrentlyKeyword)\(notExists)\(indexName.quoted())
            ON \(table.quoted())
            USING GIST (\(column.quoted()))
            """
        print("🔍 Creating GiST index '\(indexName)' on table '\(table)' column '\(column)'")
        do {
            try await execute(sql)
            print("✅ Successfully created GiST index '\(indexName)'")
        } catch {
            print("❌ Failed to create GiST index: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Column Management

    /// Adds a tsvector column to an existing table.
    ///
    /// This function adds a new tsvector column but does not populate it or create
    /// indexes/triggers. Use `setupFullTextSearch()` for complete setup.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.addSearchVectorColumn(
    ///         to: "articles",
    ///         column: "search_vector"
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The column name (default: "search_vector")
    ///   - ifNotExists: Whether to skip if column already exists (default: true)
    /// - Throws: Database error if column creation fails
    public func addSearchVectorColumn(
        to table: String,
        column: String = "search_vector",
        ifNotExists: Bool = true
    ) async throws {
        if ifNotExists {
            // Check if column exists using information_schema
            // Note: information_schema stores unquoted lowercase names
            let sql = """
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1
                        FROM information_schema.columns
                        WHERE table_name = '\(table)' AND column_name = '\(column)'
                    ) THEN
                        ALTER TABLE "\(table)" ADD COLUMN "\(column)" tsvector;
                    END IF;
                END $$;
                """
            print("🔍 Adding column '\(column)' to table '\(table)' with SQL:\n\(sql)")
            do {
                try await execute(sql)
                print("✅ Successfully added column '\(column)' to table '\(table)'")
            } catch {
                print("❌ Failed to add column '\(column)': \(String(reflecting: error))")
                throw error
            }
        } else {
            try await execute(
                """
                ALTER TABLE "\(table)"
                ADD COLUMN "\(column)" tsvector
                """
            )
        }
    }

    /// Removes a tsvector column and its associated triggers/indexes.
    ///
    /// This function drops the column, its trigger, and its index. Use with caution
    /// as this operation cannot be undone.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.removeSearchVectorColumn(
    ///         from: "articles",
    ///         column: "search_vector"
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The column name
    /// - Throws: Database error if removal fails
    public func removeSearchVectorColumn(
        from table: String,
        column: String
    ) async throws {
        // Drop trigger first (if exists)
        let triggerName = "\(table)_\(column)_update"
        try await execute(
            """
            DROP TRIGGER IF EXISTS \(triggerName.quoted()) ON \(table.quoted())
            """
        )

        // Drop function (if exists)
        let functionName = "\(table)_\(column)_trigger"
        try await execute(
            """
            DROP FUNCTION IF EXISTS \(functionName.quoted())()
            """
        )

        // Drop column (index is automatically dropped with column)
        try await execute(
            """
            ALTER TABLE \(table.quoted())
            DROP COLUMN IF EXISTS \(column.quoted())
            """
        )
    }

    // MARK: - Trigger Creation

    /// Creates a trigger to automatically update a tsvector column.
    ///
    /// The trigger fires on INSERT and UPDATE to keep the search vector synchronized
    /// with the source text columns.
    ///
    /// ```swift
    /// // Automatic trigger (all columns same weight)
    /// try await db.write { db in
    ///     try await db.createSearchVectorTrigger(
    ///         on: "articles",
    ///         column: "search_vector",
    ///         sourceColumns: ["title", "body"],
    ///         language: "english",
    ///         type: .automatic
    ///     )
    /// }
    ///
    /// // Custom weighted trigger (different weights per column)
    /// try await db.write { db in
    ///     try await db.createSearchVectorTrigger(
    ///         on: "articles",
    ///         column: "search_vector",
    ///         weightedColumns: [
    ///             .init(name: "title", weight: .A),
    ///             .init(name: "body", weight: .B)
    ///         ],
    ///         language: "english",
    ///         type: .custom
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The tsvector column name
    ///   - sourceColumns: Source text columns (for automatic trigger)
    ///   - weightedColumns: Weighted source columns (for custom trigger)
    ///   - language: Text search configuration (default: "english")
    ///   - type: Trigger type (.automatic or .custom)
    /// - Throws: Database error if trigger creation fails
    public func createSearchVectorTrigger(
        on table: String,
        column: String,
        sourceColumns: [String]? = nil,
        weightedColumns: [WeightedColumn]? = nil,
        language: String = "english",
        type: SearchVectorTriggerType
    ) async throws {
        try validateLanguage(language)
        let triggerName = "\(table)_\(column)_update"

        switch type {
        case .automatic:
            guard let sources = sourceColumns, !sources.isEmpty else {
                throw Database.Error.invalidArgument("sourceColumns required for automatic trigger")
            }

            let columnList = sources.map { "'\($0)'" }.joined(separator: ", ")

            try await execute(
                """
                CREATE TRIGGER \(triggerName.quoted())
                BEFORE INSERT OR UPDATE ON \(table.quoted())
                FOR EACH ROW EXECUTE FUNCTION
                tsvector_update_trigger(\(column.quoted()), 'pg_catalog.\(language)', \(columnList))
                """
            )

        case .custom:
            guard let weighted = weightedColumns, !weighted.isEmpty else {
                throw Database.Error.invalidArgument("weightedColumns required for custom trigger")
            }

            let functionName = "\(table)_\(column)_trigger"

            // Build weighted tsvector expression
            let vectorExpression = weighted.map { col in
                "setweight(to_tsvector('pg_catalog.\(language)', coalesce(NEW.\(col.name.quoted()), '')), \(col.weight.rawValue.quoted(.text)))"
            }.joined(separator: " || ")

            // Create trigger function
            try await execute(
                """
                CREATE OR REPLACE FUNCTION \(functionName.quoted())() RETURNS trigger AS $$
                BEGIN
                  NEW.\(column.quoted()) := \(vectorExpression);
                  RETURN NEW;
                END
                $$ LANGUAGE plpgsql
                """
            )

            // Drop trigger if exists (separate statement)
            try await execute(
                """
                DROP TRIGGER IF EXISTS \(triggerName.quoted()) ON \(table.quoted())
                """
            )

            // Create trigger (separate statement)
            try await execute(
                """
                CREATE TRIGGER \(triggerName.quoted())
                BEFORE INSERT OR UPDATE ON \(table.quoted())
                FOR EACH ROW EXECUTE FUNCTION \(functionName.quoted())()
                """
            )
        }
    }

    // MARK: - Backfill Operations

    /// Backfills a tsvector column with values from source columns.
    ///
    /// Use this after adding a search vector column to populate it for existing rows.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.backfillSearchVector(
    ///         table: "articles",
    ///         column: "search_vector",
    ///         weightedColumns: [
    ///             .init(name: "title", weight: .A),
    ///             .init(name: "body", weight: .B)
    ///         ]
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The tsvector column name
    ///   - weightedColumns: Source columns with weights
    ///   - language: Text search configuration (default: "english")
    /// - Throws: Database error if backfill fails
    public func backfillSearchVector(
        table: String,
        column: String,
        weightedColumns: [WeightedColumn],
        language: String = "english"
    ) async throws {
        try validateLanguage(language)
        let vectorExpression = weightedColumns.map { col in
            "setweight(to_tsvector(\(language.quoted(.text)), coalesce(\(col.name.quoted()), '')), \(col.weight.rawValue.quoted(.text)))"
        }.joined(separator: " || ")

        let sql = """
            UPDATE \(table.quoted())
            SET \(column.quoted()) = \(vectorExpression)
            """
        print("🔍 Backfilling search vector column '\(column)' in table '\(table)'")
        do {
            try await execute(sql)
            print("✅ Successfully backfilled search vector")
        } catch {
            print("❌ Failed to backfill search vector: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Complete Setup Helper

    /// Complete full-text search setup for a table.
    ///
    /// This convenience function performs all necessary steps to set up full-text
    /// search on a table:
    /// 1. Adds tsvector column
    /// 2. Creates weighted trigger for automatic updates
    /// 3. Backfills existing rows
    /// 4. Creates index (GIN or GiST)
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.setupFullTextSearch(
    ///         on: "articles",
    ///         weightedColumns: [
    ///             .init(name: "title", weight: .A),
    ///             .init(name: "body", weight: .B)
    ///         ],
    ///         language: "english",
    ///         indexMethod: .gin
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The tsvector column name (default: "search_vector")
    ///   - weightedColumns: Source columns with weights
    ///   - language: Text search configuration (default: "english")
    ///   - indexMethod: Index type to create (default: .gin)
    /// - Throws: Database error if setup fails
    public func setupFullTextSearch(
        on table: String,
        column: String = "search_vector",
        weightedColumns: [WeightedColumn],
        language: String = "english",
        indexMethod: FTSIndexMethod = .gin
    ) async throws {
        // 1. Add column (if not exists)
        try await addSearchVectorColumn(to: table, column: column)

        // 2. Create trigger
        try await createSearchVectorTrigger(
            on: table,
            column: column,
            weightedColumns: weightedColumns,
            language: language,
            type: .custom
        )

        // 3. Backfill existing rows
        try await backfillSearchVector(
            table: table,
            column: column,
            weightedColumns: weightedColumns,
            language: language
        )

        // 4. Create index
        switch indexMethod {
        case .gin:
            try await createGINIndex(on: table, column: column)
        case .gist:
            try await createGiSTIndex(on: table, column: column)
        }
    }
}
