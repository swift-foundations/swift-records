import Dependencies
import Records
import RecordsTestSupport
import Testing

@Suite(
    "assertQuery Validation",
    .snapshots(record: .never),
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct AssertQueryValidationTests {
    @Dependency(\.defaultDatabase) var db

    @Test func simpleSelectWithExplicitExecute() async {
        await RecordsTestSupport.assertQuery(
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
