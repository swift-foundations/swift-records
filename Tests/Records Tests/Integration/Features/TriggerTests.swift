import Dependencies
import Dependencies_Test_Support
import Foundation
import Records
import Records_Test_Support
import PostgreSQL_Standard
import Testing

@Suite(

    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct Test {
    @Dependency(\.defaultDatabase) var db

    // MARK: - Setup

    func setup() async throws {
        try await db.write { db in
            // Create test tables
            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS "items" (
                        "id" SERIAL PRIMARY KEY,
                        "name" TEXT NOT NULL,
                        "position" INTEGER DEFAULT 0,
                        "updateCount" INTEGER DEFAULT 0
                    )
                """
            )

            try await db.execute(
                """
                    CREATE TABLE IF NOT EXISTS "itemLogs" (
                        "id" SERIAL PRIMARY KEY,
                        "itemId" INTEGER NOT NULL,
                        "action" TEXT NOT NULL,
                        "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """
            )
        }
    }

    func cleanup() async throws {
        try await db.write { db in
            try await db.execute("DROP TABLE IF EXISTS \"itemLogs\" CASCADE")
            try await db.execute("DROP TABLE IF EXISTS \"items\" CASCADE")
        }
    }

    // MARK: - Simple Trigger Tests

    @Test
    func `Basic insert trigger sets default position`() async throws {
        try await setup()
        defer { Task { try? await cleanup() } }

        // Create a trigger that sets position on insert
        try await db.write { db in
            // Use createTrigger.Function helper for PostgreSQL-specific function
            try await db.createTriggerFunction(
                "set_default_position",
                body: """
                    IF NEW."position" = 0 THEN
                        NEW."position" = (SELECT COALESCE(MAX("position"), 0) + 1 FROM "items");
                    END IF;
                    RETURN NEW;
                    """
            )

            // Create the trigger using that function
            try await db.execute(
                """
                    CREATE TRIGGER set_position_trigger
                    BEFORE INSERT ON "items"
                    FOR EACH ROW
                    EXECUTE FUNCTION set_default_position()
                """
            )
        }

        // Insert items without setting position
        for name in ["First", "Second", "Third"] {
            try await db.write { db in
                try await Item.insert {
                    Item.Draft(name: name)
                }.execute(db)
            }
        }

        // Check that positions were set automatically
        let items = try await db.read { db in
            try await Item.all
                .order(by: \.position)
                .fetchAll(db)
        }

        #expect(items.count == 3)
        #expect(items[0].position == 1)
        #expect(items[1].position == 2)
        #expect(items[2].position == 3)
    }

    //    @Test
    //    func testUpdateTrigger() async throws {
    //        try await setup()
    //        defer { Task { try? await cleanup() } }
    //
    //        // Create trigger using swift-structured-queries syntax
    //        try await db.write { db in
    //            // This trigger increments updateCount on each update
    //            try await db.execute(
    //                Item.createTemporaryTrigger(
    //                    after: .update { old, new in
    //                        Item
    //                            .where { $0.id == new.id }
    //                            .update {
    //                                $0.updateCount = #sql("\(new.updateCount) + 1")
    //                            }
    //                    }
    //                )
    //            )
    //        }
    //
    //        // Insert an item
    //        let itemId = try await db.write { db in
    //            // Use the proper Insert API with returning
    //            let result = try await Item.insert {
    //                Item.Draft(name: "Test Item")
    //            }
    //                .returning { (id: $0.id) }
    //                .fetchOne(db)
    //            return result ?? 0
    //        }
    //
    //        // Update it multiple times
    //        for i in 1...3 {
    //            try await db.write { db in
    //                try await Item
    //                    .where { $0.id == itemId }
    //                    .update { $0.name = "Updated \(i)" }
    //                    .execute(db)
    //            }
    //        }
    //
    //        // Check the update count
    //        let item = try await db.read { db in
    //            try await Item
    //                .where { $0.id == itemId }
    //                .fetchOne(db)
    //        }
    //
    //        #expect(item?.updateCount == 3, "Should have been updated 3 times")
    //    }

    //    @Test
    //    func testDeleteTrigger() async throws {
    //        try await setup()
    //        defer { Task { try? await cleanup() } }
    //
    //        // Create a trigger that logs deletions
    //        try await db.write { db in
    //            try await db.execute(
    //                Item.createTemporaryTrigger(
    //                    after: .delete { old in
    //                        #sql("""
    //                            INSERT INTO "itemLogs" ("itemId", "action")
    //                            VALUES (\(old.id), 'DELETED: ' || \(old.name))
    //                        """)
    //                    }
    //                )
    //            )
    //        }
    //
    //        // Insert some items
    //        let itemIds = try await db.write { db in
    //            // Insert multiple items and collect their IDs
    //            let results = try await Item.insert {
    //                [
    //                    Item.Draft(name: "Item A"),
    //                    Item.Draft(name: "Item B"),
    //                    Item.Draft(name: "Item C")
    //                ]
    //            }
    //            .returning(\.id)
    //            .fetchAll(db)
    //            return results
    //        }
    //
    //        // Delete one item
    //        try await db.write { db in
    //            try await Item
    //                .where { $0.id == itemIds[0] }
    //                .delete()
    //                .execute(db)
    //        }
    //
    //        // Check the log
    //        let logs = try await db.read { db in
    //            try await ItemLog.all.fetchAll(db)
    //        }
    //
    //        #expect(logs.count == 1)
    //        #expect(logs[0].action.contains("DELETED"))
    //        #expect(logs[0].action.contains("Item A"))
    //    }
}

// MARK: - Test Models

@Table
private struct Item: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var position: Int = 0
    var updateCount: Int = 0
}

@Table
private struct ItemLog: Codable, Equatable, Identifiable {
    let id: Int
    var itemId: Int
    var action: String
    var createdAt: Date?
}
