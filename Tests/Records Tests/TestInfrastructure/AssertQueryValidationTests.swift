import Dependencies
import Records
import Records_Test_Support
import Tests_Apple_Testing_Bridge
import Testing

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
                try await db.read { db in
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
