import Dependencies
import Dependencies_Test_Support
import Foundation
import PostgresNIO
@testable import Records
import Records_Test_Support
import PostgreSQL_Standard
import Testing

// Test model similar to Repository.Traffic.Hourly.Record with UUID primary key
@Table("draft_test_records")
struct DraftTestRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let repositoryId: UUID
    let hour: Date
    let views: Int
    let uniqueVisitors: Int
    let isComplete: Bool
    let notes: String?
}

@Suite(
    "Draft Insert Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct DraftInsertTests {
    @Dependency(\.defaultDatabase) var database

    init() async throws {
        // Create test table
        try await database.write { db in
            try await db.execute(
                """
                CREATE TABLE IF NOT EXISTS draft_test_records (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    "repositoryId" UUID NOT NULL,
                    hour TIMESTAMP NOT NULL,
                    views INTEGER NOT NULL DEFAULT 0,
                    "uniqueVisitors" INTEGER NOT NULL DEFAULT 0,
                    "isComplete" BOOLEAN NOT NULL DEFAULT true,
                    notes TEXT,
                    UNIQUE("repositoryId", hour)
                )
                """
            )
        }
    }

    @Test("Draft insert without ID generates UUID automatically")
    func testDraftInsertWithoutId() async throws {
        let repositoryId = UUID()
        let hour = Date()

        // Insert using Draft without providing ID
        let insertedRecord = try await database.write { db in
            try await DraftTestRecord.insert {
                DraftTestRecord.Draft(
                    repositoryId: repositoryId,
                    hour: hour,
                    views: 10,
                    uniqueVisitors: 5,
                    isComplete: true,
                    notes: "Test note"
                )
            }
            .returning(\.self)
            .fetchOne(db)
        }

        // Verify record was inserted with auto-generated UUID
        #expect(insertedRecord != nil)
        #expect(insertedRecord?.repositoryId == repositoryId)
        #expect(insertedRecord?.views == 10)
        #expect(insertedRecord?.uniqueVisitors == 5)
        #expect(insertedRecord?.notes == "Test note")

        // The ID should have been auto-generated (not nil)
        #expect(insertedRecord?.id != nil)
    }

    @Test("Draft insert with explicit ID uses provided value")
    func testDraftInsertWithExplicitId() async throws {
        let explicitId = UUID()
        let repositoryId = UUID()
        let hour = Date()

        // Insert using Draft with explicit ID
        let insertedRecord = try await database.write { db in
            try await DraftTestRecord.insert {
                DraftTestRecord.Draft(
                    id: explicitId,
                    repositoryId: repositoryId,
                    hour: hour,
                    views: 20,
                    uniqueVisitors: 10,
                    isComplete: false,
                    notes: nil
                )
            }
            .returning(\.self)
            .fetchOne(db)
        }

        // Verify the explicit ID was used
        #expect(insertedRecord?.id == explicitId)
        #expect(insertedRecord?.views == 20)
        #expect(insertedRecord?.isComplete == false)
        #expect(insertedRecord?.notes == nil)
    }

    @Test("Draft insert with ON CONFLICT handles upserts correctly")
    func testDraftInsertWithConflictResolution() async throws {
        do {
            let repositoryId = UUID()
            let hour = Date()

            // First insert
            try await database.write { db in
                try await DraftTestRecord.insert {
                    DraftTestRecord.Draft(
                        repositoryId: repositoryId,
                        hour: hour,
                        views: 10,
                        uniqueVisitors: 5,
                        isComplete: true,
                        notes: "Initial"
                    )
                }.execute(db)
            }

            // Upsert with conflict resolution (same repositoryId and hour)
            let upsertedRecord = try await database.write { db in
                try await DraftTestRecord.insert {
                    DraftTestRecord.Draft(
                        repositoryId: repositoryId,
                        hour: hour,
                        views: 20,
                        uniqueVisitors: 8,
                        isComplete: true,
                        notes: "Updated"
                    )
                } onConflict: { columns in
                    (columns.repositoryId, columns.hour)
                } doUpdate: { row, excluded in
                    row.views = excluded.views
                    row.uniqueVisitors = excluded.uniqueVisitors
                    row.notes = excluded.notes
                }
                .returning(\.self)
                .fetchOne(db)
            }

            // Verify the update occurred
            #expect(upsertedRecord?.views == 20)
            #expect(upsertedRecord?.uniqueVisitors == 8)
            #expect(upsertedRecord?.notes == "Updated")

            // Verify only one record exists
            let count = try await database.read { db in
                try await DraftTestRecord
                    .where { $0.repositoryId.eq(repositoryId) }
                    .fetchCount(db)
            }
            #expect(count == 1)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Multiple Draft inserts without IDs")
    func testMultipleDraftInserts() async throws {
        let repositoryId = UUID()
        let baseTime = Date()

        // Insert multiple drafts at once
        let insertedRecords = try await database.write { db in
            try await DraftTestRecord.insert {
                DraftTestRecord.Draft(
                    repositoryId: repositoryId,
                    hour: baseTime,
                    views: 10,
                    uniqueVisitors: 5,
                    isComplete: true,
                    notes: "First"
                )
                DraftTestRecord.Draft(
                    repositoryId: repositoryId,
                    hour: baseTime.addingTimeInterval(3600),
                    views: 20,
                    uniqueVisitors: 10,
                    isComplete: true,
                    notes: "Second"
                )
                DraftTestRecord.Draft(
                    repositoryId: repositoryId,
                    hour: baseTime.addingTimeInterval(7200),
                    views: 30,
                    uniqueVisitors: 15,
                    isComplete: true,
                    notes: "Third"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        // Verify all records were inserted
        #expect(insertedRecords.count == 3)

        // All should have auto-generated IDs
        for record in insertedRecords {
            #expect(record.id != nil)
            #expect(record.repositoryId == repositoryId)
        }

        // Verify the values
        #expect(insertedRecords[0].views == 10)
        #expect(insertedRecords[1].views == 20)
        #expect(insertedRecords[2].views == 30)
    }

    @Test("Mixed Draft inserts with and without explicit IDs")
    func testMixedDraftInserts() async throws {
        do {
            let repositoryId = UUID()
            let explicitId = UUID()
            let baseTime = Date()

            // Insert mix of drafts - some with explicit ID, some without
            let insertedRecords = try await database.write { db in
                try await DraftTestRecord.insert {
                    // With explicit ID
                    DraftTestRecord.Draft(
                        id: explicitId,
                        repositoryId: repositoryId,
                        hour: baseTime,
                        views: 10,
                        uniqueVisitors: 5,
                        isComplete: true,
                        notes: "Explicit ID"
                    )
                    // Without ID (should auto-generate)
                    DraftTestRecord.Draft(
                        repositoryId: repositoryId,
                        hour: baseTime.addingTimeInterval(3600),
                        views: 20,
                        uniqueVisitors: 10,
                        isComplete: true,
                        notes: "Auto ID"
                    )
                }
                .returning(\.self)
                .fetchAll(db)
            }

            // Verify both records were inserted
            #expect(insertedRecords.count == 2)

            // First should have explicit ID
            #expect(insertedRecords[0].id == explicitId)
            #expect(insertedRecords[0].notes == "Explicit ID")

            // Second should have auto-generated ID (different from explicit)
            #expect(insertedRecords[1].id != explicitId)
            #expect(insertedRecords[1].notes == "Auto ID")
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Draft insert SQL does not contain NULL for omitted ID")
    func testDraftInsertSQLGeneration() async throws {
        let repositoryId = UUID()
        let hour = Date()

        // Create the insert statement
        let insertStatement = DraftTestRecord.insert {
            DraftTestRecord.Draft(
                repositoryId: repositoryId,
                hour: hour,
                views: 10,
                uniqueVisitors: 5,
                isComplete: true,
                notes: nil
            )
        }

        // Get the SQL query
        let sql = insertStatement.query.toPostgresQuery().sql

        // Verify the SQL doesn't contain NULL in VALUES for the id
        // It should either:
        // 1. Not include "id" in the column list at all (preferred for PostgreSQL)
        // 2. Use DEFAULT for the id value

        // The SQL should NOT contain the pattern: VALUES (NULL, ...)
        #expect(!sql.contains("VALUES (NULL"))

        // If using our fixed implementation, "id" shouldn't be in the column list
        // when the Draft doesn't provide an id value
        print("Generated SQL: \(sql)")
    }

    @Test("Verify NULL primary key columns are filtered out")
    func testNullPrimaryKeyFiltering() async throws {
        do {
            // This test verifies the core fix - that NULL primary keys
            // are not included in the INSERT column list

            let repositoryId = UUID()
            let hour = Date()

            // Build insert with Draft (no ID)

            // Execute and verify it works
            let result = try await database.write { db in
                try await DraftTestRecord.insert {
                    DraftTestRecord.Draft(
                        repositoryId: repositoryId,
                        hour: hour,
                        views: 100,
                        uniqueVisitors: 50,
                        isComplete: true,
                        notes: "Testing NULL filtering"
                    )
                } onConflict: { columns in
                    (columns.repositoryId, columns.hour)
                } doUpdate: { row, excluded in
                    row.views = excluded.views
                    row.uniqueVisitors = excluded.uniqueVisitors
                }
                .returning(\.self)
                .fetchOne(db)
            }

            // Should succeed without PSQLError about NULL in "id"
            #expect(result != nil)
            #expect(result?.views == 100)
            #expect(result?.notes == "Testing NULL filtering")

            // The auto-generated ID should be present
            #expect(result?.id != nil)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
}
