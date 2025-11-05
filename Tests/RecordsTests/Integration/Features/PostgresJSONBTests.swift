import Dependencies
import Foundation
import Records
import RecordsTestSupport
import StructuredQueriesPostgres
import Testing

/// Integration tests for JSONB with database execution
/// Tests round-trip encoding/decoding through PostgreSQL
@Suite(
    "JSONB Integration Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct JSONBTests {

    @Dependency(\.defaultDatabase) var db

    @Test("Insert and retrieve JSONB data")
    func testInsertAndRetrieveJSONB() async throws {
        try await db.write { db in
            // Create the test table
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS test_jsonb (
                        id INTEGER PRIMARY KEY,
                        features JSONB,
                        metadata JSONB
                    )
                """
            )

            // Insert data with JSONB columns
            try await TestTable.insert {
                TestTable(
                    id: 1,
                    features: ["feature1", "feature2", "feature3"],
                    metadata: ["environment": "test", "version": "1.0.0"]
                )
            }.execute(db)

            // Retrieve the data
            let results =
                try await TestTable
                .where { $0.id == 1 }
                .fetchAll(db)

            #expect(results.count == 1)
            let record = results[0]
            #expect(record.features.count == 3)
            #expect(record.features.contains("feature1"))
            #expect(record.features.contains("feature2"))
            #expect(record.features.contains("feature3"))
            #expect(record.metadata["environment"] == "test")
            #expect(record.metadata["version"] == "1.0.0")

            // Clean up
            try await db.execute("DROP TABLE IF EXISTS test_jsonb")
        }
    }

    @Test("Update JSONB columns")
    func testUpdateJSONB() async throws {
        do {
            try await db.write { db in
                // Create the test table
                try await db.execute(
                    """
                        CREATE TABLE IF NOT EXISTS test_jsonb (
                            id INTEGER PRIMARY KEY,
                            features JSONB,
                            metadata JSONB
                        )
                    """
                )

                // Insert initial data
                try await TestTable.insert {
                    TestTable(
                        id: 2,
                        features: ["old_feature"],
                        metadata: ["status": "draft"]
                    )
                }.execute(db)

                // Update the JSONB columns
                try await TestTable
                    .where { $0.id == 2 }
                    .update {
                        $0.features = ["new_feature1", "new_feature2"]
                        $0.metadata = ["status": "published", "updated": "true"]
                    }
                    .execute(db)

                // Retrieve and verify the updated data
                let updated =
                    try await TestTable
                    .where { $0.id == 2 }
                    .fetchOne(db)

                #expect(updated?.features.count == 2)
                #expect(updated?.features.contains("new_feature1") == true)
                #expect(updated?.features.contains("new_feature2") == true)
                #expect(updated?.metadata["status"] == "published")
                #expect(updated?.metadata["updated"] == "true")

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS test_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("JSONB with empty arrays and dictionaries")
    func testEmptyJSONB() async throws {
        do {
            try await db.write { db in
                // Create the test table
                try await db.execute(
                    """
                        CREATE TABLE IF NOT EXISTS test_jsonb (
                            id INTEGER PRIMARY KEY,
                            features JSONB,
                            metadata JSONB
                        )
                    """
                )

                // Insert empty arrays and dictionaries
                try await TestTable.insert {
                    TestTable(
                        id: 3,
                        features: [],
                        metadata: [:]
                    )
                }.execute(db)

                // Retrieve and verify
                let result =
                    try await TestTable
                    .where { $0.id == 3 }
                    .fetchOne(db)

                #expect(result?.features.isEmpty == true)
                #expect(result?.metadata.isEmpty == true)

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS test_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("JSONB with special characters")
    func testJSONBSpecialCharacters() async throws {
        do {
            try await db.write { db in
                // Create the test table
                try await db.execute(
                    """
                        CREATE TABLE IF NOT EXISTS test_jsonb (
                            id INTEGER PRIMARY KEY,
                            features JSONB,
                            metadata JSONB
                        )
                    """
                )

                // Insert data with special characters
                try await TestTable.insert {
                    TestTable(
                        id: 4,
                        features: [
                            "feature\"with\"quotes", "feature'with'apostrophes",
                            "feature\\with\\backslashes",
                        ],
                        metadata: ["key\"1": "value\"1", "key'2": "value'2", "key\\3": "value\\3"]
                    )
                }.execute(db)

                // Retrieve and verify
                let result =
                    try await TestTable
                    .where { $0.id == 4 }
                    .fetchOne(db)

                #expect(result?.features.contains("feature\"with\"quotes") == true)
                #expect(result?.features.contains("feature'with'apostrophes") == true)
                #expect(result?.features.contains("feature\\with\\backslashes") == true)
                #expect(result?.metadata["key\"1"] == "value\"1")
                #expect(result?.metadata["key'2"] == "value'2")
                #expect(result?.metadata["key\\3"] == "value\\3")

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS test_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("JSONB with optional columns")
    func testOptionalJSONB() async throws {
        do {
            try await db.write { db in
                // Create the table
                try await db.execute(
                    """
                        CREATE TABLE IF NOT EXISTS optional_jsonb (
                            id INTEGER PRIMARY KEY,
                            "optionalFeatures" JSONB,
                            "optionalMetadata" JSONB
                        )
                    """
                )

                // Insert with nil values
                try await OptionalTable.insert {
                    OptionalTable(
                        id: 1,
                        optionalFeatures: nil,
                        optionalMetadata: nil
                    )
                }.execute(db)

                // Insert with actual values
                try await OptionalTable.insert {
                    OptionalTable(
                        id: 2,
                        optionalFeatures: ["feature"],
                        optionalMetadata: ["key": "value"]
                    )
                }.execute(db)

                // Retrieve and verify
                let nilRecord =
                    try await OptionalTable
                    .where { $0.id == 1 }
                    .fetchOne(db)

                #expect(nilRecord?.optionalFeatures == nil)
                #expect(nilRecord?.optionalMetadata == nil)

                let valueRecord =
                    try await OptionalTable
                    .where { $0.id == 2 }
                    .fetchOne(db)

                #expect(valueRecord?.optionalFeatures?.count == 1)
                #expect(valueRecord?.optionalMetadata?["key"] == "value")

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS optional_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
}

// Test table definitions
@Table("test_jsonb")
private struct TestTable {
    let id: Int
    @Column(as: [String].JSONB.self)
    let features: [String]
    @Column(as: [String: String].JSONB.self)
    let metadata: [String: String]
}

@Table("optional_jsonb")
private struct OptionalTable {
    let id: Int
    @Column(as: [String].JSONB?.self)
    let optionalFeatures: [String]?
    @Column(as: [String: String].JSONB?.self)
    let optionalMetadata: [String: String]?
}
