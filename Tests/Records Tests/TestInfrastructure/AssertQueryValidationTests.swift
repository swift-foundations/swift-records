import Dependencies
import Records
import Records_Test_Support
import Testing
import Tests_Apple_Testing_Bridge

@Suite(

    .snapshots(record: .never),
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct Test {
    @Dependency(\.defaultDatabase) var db

    @Test func simpleSelectWithExplicitExecute() async {
        await Records_Test_Support.assertQuery(
            Reminder.select { $0.title }.order(by: \.title).limit(3),
            execute: { statement in
                try await db.read { db async throws(Database.Error) in
                    try await db.fetchAll(statement)
                }
            },
            sql: {
                """
                SELECT "reminders"."title"
                FROM "reminders"
                ORDER BY "reminders"."title"
                LIMIT 3
                """
            },
            results: {
                """
                ┌─────────────────┐
                │ "Finish report" │
                │ "Groceries"     │
                │ "Haircut"       │
                └─────────────────┘
                """
            }
        )
    }

    @Test func simpleSelectWithConvenienceWrapper() async {
        await assertQuery(
            Reminder.select { $0.title }.order(by: \.title).limit(3)
        ) {
            """
            SELECT "reminders"."title"
            FROM "reminders"
            ORDER BY "reminders"."title"
            LIMIT 3
            """
        } results: {
            """
            ┌─────────────────┐
            │ "Finish report" │
            │ "Groceries"     │
            │ "Haircut"       │
            └─────────────────┘
            """
        }
    }
}
