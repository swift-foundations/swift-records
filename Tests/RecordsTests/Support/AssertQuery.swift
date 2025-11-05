import Dependencies
import Records
import RecordsTestSupport
import StructuredQueriesPostgres

/// Convenience wrapper for assertQuery that auto-injects database dependency.
///
/// This wrapper automatically provides the database connection, allowing for cleaner test code.
///
/// ```swift
/// @Suite(
///   "My Tests",
///   .dependencies {
///     $0.defaultDatabase = try await Database.TestDatabase.withReminderData()
///   }
/// )
/// struct MyTests {
///   @Test func findByID() async {
///     await assertQuery(
///       Reminder.find(1).select { ($0.id, $0.title) }
///     ) {
///       """
///       SELECT "reminders"."id", "reminders"."title"
///       FROM "reminders"
///       WHERE ("reminders"."id") IN ((1))
///       """
///     } results: {
///       """
///       ┌───┬─────────────┐
///       │ 1 │ "Groceries" │
///       └───┴─────────────┘
///       """
///     }
///   }
/// }
/// ```
func assertQuery<each V: QueryRepresentable, S: Statement<(repeat each V)>>(
    _ query: S,
    sql: (() -> String)? = nil,
    results: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column
) async where repeat each V: Sendable, repeat (each V).QueryOutput: Sendable, S: Sendable {
    @Dependency(\.defaultDatabase) var database

    await RecordsTestSupport.assertQuery(
        query,
        execute: { statement in
            do {
                return try await database.read { db in
                    return try await db.fetchAll(statement)
                }
            } catch {
                Swift.print(String(reflecting: error))
                throw error
            }
        },
        sql: sql,
        results: results,
        snapshotTrailingClosureOffset: 0,
        fileID: fileID,
        filePath: filePath,
        function: function,
        line: line,
        column: column
    )
}
