import Foundation

/// PostgreSQL transaction isolation levels.
///
/// Controls the level of isolation between concurrent transactions.
/// Higher isolation levels provide better data consistency but may
/// reduce concurrency and increase the chance of serialization conflicts.
///
/// ## Isolation Levels
///
/// ### Read Uncommitted
/// The lowest isolation level. Allows dirty reads (reading uncommitted changes
/// from other transactions). In PostgreSQL, this behaves the same as Read Committed.
///
/// ### Read Committed (Default)
/// Each query sees a snapshot of the database as of the start of the query.
/// Prevents dirty reads but allows non-repeatable reads and phantom reads.
/// This is PostgreSQL's default and is suitable for most applications.
///
/// ### Repeatable Read
/// Each query in a transaction sees a snapshot as of the start of the transaction.
/// Prevents dirty reads and non-repeatable reads, but allows phantom reads.
/// May cause serialization errors that require retry logic.
///
/// ### Serializable
/// The highest isolation level. Provides complete isolation between transactions
/// as if they were executed serially. May cause more serialization errors.
///
/// ## Example
///
/// ```swift
/// // Use default isolation (READ COMMITTED)
/// try await db.withTransaction { db in
///     // Your operations
/// }
///
/// // Use serializable for critical operations
/// try await db.withTransaction(isolation: .serializable) { db in
///     let balance = try await Account
///         .filter { $0.id == accountId }
///         .fetchOne(db)
///
///     guard let balance, balance.amount >= withdrawAmount else {
///         throw InsufficientFunds()
///     }
///
///     try await Account
///         .filter { $0.id == accountId }
///         .update { $0.amount -= withdrawAmount }
///         .execute(db)
/// }
/// ```
///
/// ## Choosing an Isolation Level
///
/// - Use `.readCommitted` (default) for most operations
/// - Use `.repeatableRead` when you need consistent reads within a transaction
/// - Use `.serializable` for critical operations that require complete isolation
/// - Be prepared to handle serialization errors with retry logic for higher levels
public enum TransactionIsolationLevel: String, Sendable, CaseIterable {
    /// Allows dirty reads, non-repeatable reads, and phantom reads.
    /// In PostgreSQL, behaves the same as `.readCommitted`.
    case readUncommitted = "READ UNCOMMITTED"

    /// Prevents dirty reads but allows non-repeatable reads and phantom reads.
    /// This is PostgreSQL's default isolation level.
    case readCommitted = "READ COMMITTED"

    /// Prevents dirty reads and non-repeatable reads but allows phantom reads.
    /// May cause serialization errors requiring retry.
    case repeatableRead = "REPEATABLE READ"

    /// Prevents dirty reads, non-repeatable reads, and phantom reads.
    /// Highest isolation but may cause more serialization errors.
    case serializable = "SERIALIZABLE"
}
