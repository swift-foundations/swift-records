# Records SQL Integration

`Records SQL Integration` is an additive, provider-neutral adapter from Records' established
`Database.Writer` and `Database.Connection.Protocol` interfaces to the engine-free `SQL` surface.
Import it only in the application layer that composes Records with a concrete SQL provider.

```swift
import Records_SQL_Integration
import SQL

let records = Database.SQL.Writer(
    database: sqlDatabase,
    close: {
        try await provider.close()
    }
)
```

The adapter enters one SQL scope for each Records `read` or `write` operation and forwards the
scoped connection without opening another database scope. A returned Records cursor wraps the
provider-neutral `SQL.Cursor` and streams values one at a time; it does not collect rows before
returning.

The `close` operation is injected because lifecycle belongs to the provider integration. Records
does not assume that an SQL database is a pool, a socket, or a particular database engine.

## Errors

SQL operations retain the typed `SQL.Error` domain. A caller error crossing the older untyped
Records callback boundary is represented as `SQL.Error.execution`, preserving the SQL scope's
typed error contract rather than erasing it to `any Error`.
