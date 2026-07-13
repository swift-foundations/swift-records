# swift-records Testing Strategy

## Philosophy: Integration-Only Testing

**swift-records tests focus exclusively on integration with PostgreSQL, not SQL generation.**

### Why?

`swift-postgresql-standard` already validates SQL generation with 280+ tests. Duplicating those tests here would be:
- Redundant
- Expensive to maintain
- Confusing about what swift-records actually does

### What swift-records Tests

✅ **Database Integration**
- Query execution returns correct data
- Connection pooling (Reader/Writer patterns)
- Transaction & savepoint behavior
- Error propagation from PostgreSQL

✅ **Type Safety**
- Swift types ↔ PostgreSQL types encoding/decoding
- NULL handling
- Custom type conformances (JSONB, UUID, etc.)

✅ **Records-Specific Features**
- Migration system
- Draft record handling (DEFAULT keyword)
- Test isolation (schema-based)
- Concurrent access patterns

❌ **What We Don't Test**
- SQL string generation (covered by swift-postgresql-standard)
- SQL syntax validation (handled by PostgreSQL parser)
- Query builder DSL correctness (covered by swift-postgresql-standard)

## Test Organization

```
Tests/                                  (nested package — swift test runs from Tests/)
├── Package.swift                   Nested manifest per [INST-TEST]
├── Records Test Support/           Test support target (assertQuery, TestDatabase)
└── Records Tests/
├── Integration/                    PRIMARY FOCUS
│   ├── Execution/                  Query execution tests
│   │   ├── SelectExecutionTests.swift
│   │   ├── InsertExecutionTests.swift
│   │   ├── UpdateExecutionTests.swift
│   │   └── DeleteExecutionTests.swift
│   │
│   ├── Database/                   Database infrastructure
│   │   ├── DatabaseAccessTests.swift
│   │   ├── ConfigurationTests.swift
│   │   └── ConcurrencyStressTests.swift
│   │
│   ├── Transactions/               Transaction & savepoint tests
│   │   └── TransactionTests.swift
│   │
│   ├── Features/                   PostgreSQL feature integration
│   │   ├── JSONBIntegrationTests.swift
│   │   ├── PostgresJSONBTests.swift
│   │   ├── FullTextSearchIntegrationTests.swift
│   │   └── TriggerTests.swift
│   │
│   └── Errors/                     Error handling
│       └── ErrorHandlingTests.swift
│
├── Schema/                         Schema management
│   └── DraftInsertTests.swift
│
├── TestInfrastructure/             Test tooling
│   ├── BasicTests.swift
│   ├── AssertQueryValidationTests.swift
│   └── StatementExtensionTests.swift
│
├── Support/                        Test helpers
│   ├── AssertQuery.swift
│   ├── Schema.swift
│   ├── SimpleSelect.swift
│   └── support.swift
│
└── IntegrationTests.swift          High-level integration tests
```

## Test Patterns

### Execution Tests (Integration)

**Good - Tests actual database execution:**
```swift
@Test("SELECT with WHERE clause executes correctly")
func selectWithWhere() async throws {
  let completed = try await db.read { db in
    try await Reminder.where { $0.isCompleted == true }.fetchAll(db)
  }
  #expect(completed.count == 1)
  #expect(completed.first?.title == "Finish report")
}
```

**Bad - Tests SQL generation (redundant with sq-postgres):**
```swift
@Test("SELECT with WHERE clause") 
func selectWithWhere() async {
  await assertQuery(
    Reminder.where { $0.isCompleted == true }
  ) {
    """
    SELECT * FROM "reminders" WHERE ...  // ❌ Already tested by sq-postgres
    """
  }
}
```

### Type Safety Tests

```swift
@Test("JSONB encoding/decoding roundtrip")
func jsonbRoundtrip() async throws {
  let metadata = Metadata(tags: ["swift", "postgres"], count: 42)
  
  let inserted = try await db.write { db in
    try await Record.insert {
      Record.Draft(metadata: metadata)
    }.returning(\.self).fetchOne(db)
  }
  
  #expect(inserted?.metadata == metadata)
}
```

### Transaction Tests

```swift
@Test("Savepoint rollback isolation")
func savepointRollback() async throws {
  try await db.withTransaction { db in
    // Insert succeeds
    try await Account.insert { Account.Draft(balance: 1000) }.execute(db)
    
    // Savepoint fails and rolls back
    do {
      try await db.withSavepoint("test") { db in
        try await Account.insert { Account.Draft(balance: 2000) }.execute(db)
        throw TestError.intentional
      }
    } catch { }
    
    // First insert still committed
    let count = try await Account.fetchCount(db)
    #expect(count == 1)
  }
}
```

## Running Tests

```bash
# All tests
swift test

# Specific category
swift test --filter Integration.Execution
swift test --filter Integration.Transactions
swift test --filter Integration.Features

# Specific test file (still works)
swift test --filter SelectExecutionTests
```

## Test Statistics

- **Total test lines:** ~6,300 (reduced from ~8,000+)
- **Reduction:** ~22% by removing redundant SQL generation tests
- **Focus:** 100% integration and database execution
- **Coverage:** All swift-records-specific functionality

## History

**2025-10-13:** Refactored to integration-only testing
- Removed SQL generation snapshot tests (redundant with swift-postgresql-standard)
- Reorganized by integration concern (Execution, Database, Transactions, Features)
- Reduced test codebase by ~1,700 lines
- Clarified testing responsibilities between swift-records and swift-postgresql-standard
