import Foundation
import PostgreSQL_Standard
import PostgreSQL_Standard_Test_Support
import Records
import Tests_Inline_Snapshot

/// An end-to-end async snapshot testing helper for PostgreSQL statements.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// await assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// ) {
///   try await db.read { try await $0.fetchAll($1) }
/// } sql: {
///   """
///   SELECT "reminders"."title" FROM "reminders"
///   ORDER BY "reminders"."title"
///   """
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// Ported off pointfreeco InlineSnapshotTesting onto the institute
/// `Tests Inline Snapshot` surface. The institute rewriter targets call sites by
/// (file, line, column) and has no trailing-closure descriptor, so when BOTH the
/// `sql:` and `results:` snapshots of one call need re-recording the writes collide —
/// record one at a time in that case. Matching (non-recording) runs are unaffected.
///
/// - Parameters:
///   - query: A statement.
///   - execute: An async closure responsible for executing the query and returning the results.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - snapshotTrailingClosureOffset: Retained for call-site compatibility with the
///     pointfree-era signature; the institute rewriter does not consume it.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
@_disfavoredOverload
public func assertQuery<each V: QueryRepresentable, S: Statement<(repeat each V)>>(
    _ query: S,
    execute: @Sendable (S) async throws -> [(repeat (each V).QueryOutput)],
    sql: (() -> String)? = nil,
    results: (() -> String)? = nil,
    snapshotTrailingClosureOffset: Int = 1,
    fileID: String = #fileID,
    filePath: String = #filePath,
    function: String = #function,
    line: Int = #line,
    column: Int = #column
) async where repeat each V: Sendable, repeat (each V).QueryOutput: Sendable, S: Sendable {
    // SQL snapshot (synchronous - query building is sync)
    assertInlineSnapshot(
        of: query,
        as: .sql,
        message: "Query did not match",
        matches: sql,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
    )

    // Execute query asynchronously
    do {
        let rows = try await execute(query)
        var table = ""
        printTable(rows, to: &table)

        // Results snapshot (synchronous - formatting is sync)
        if !table.isEmpty || results != nil {
            assertInlineSnapshot(
                of: table,
                as: .lines,
                message: table.isEmpty ? "Results expected to be empty" : "Results did not match",
                matches: results,
                fileID: fileID,
                file: filePath,
                function: function,
                line: line,
                column: column
            )
        }
    } catch {
        // Error snapshot
        assertInlineSnapshot(
            of: error.localizedDescription,
            as: .lines,
            message: "Results did not match",
            matches: results,
            fileID: fileID,
            file: filePath,
            function: function,
            line: line,
            column: column
        )
    }
}

/// An end-to-end async snapshot testing helper for PostgreSQL statements.
///
/// See the primary overload above; this variant covers select statements with joins.
public func assertQuery<S: SelectStatement, each J: Table>(
    _ query: S,
    execute:
        @Sendable (Select<(S.From, repeat each J), S.From, (repeat each J)>) async throws -> [(
            S.From.QueryOutput, repeat (each J).QueryOutput
        )],
    sql: (() -> String)? = nil,
    results: (() -> String)? = nil,
    snapshotTrailingClosureOffset: Int = 1,
    fileID: String = #fileID,
    filePath: String = #filePath,
    function: String = #function,
    line: Int = #line,
    column: Int = #column
) async
where
    S.QueryValue == (), S.Joins == (repeat each J), S.From: Sendable, S.From.QueryOutput: Sendable,
    repeat each J: Sendable, repeat (each J).QueryOutput: Sendable
{
    await assertQuery(
        query.selectStar(),
        execute: execute,
        sql: sql,
        results: results,
        snapshotTrailingClosureOffset: snapshotTrailingClosureOffset,
        fileID: fileID,
        filePath: filePath,
        function: function,
        line: line,
        column: column
    )
}

public func printTable<each C>(_ rows: [(repeat each C)], to output: inout some TextOutputStream) {
    var maxColumnSpan: [Int] = []
    var hasMultiLineRows = false
    for _ in repeat (each C).self {
        maxColumnSpan.append(0)
    }
    var table: [([[Substring]], maxRowSpan: Int)] = []
    for row in rows {
        var columns: [[Substring]] = []
        var index = 0
        var maxRowSpan = 0
        for column in repeat each row {
            defer { index += 1 }
            let cell = renderCell(column)
            let lines: [Substring] = cell.split(separator: "\n")
            hasMultiLineRows = hasMultiLineRows || lines.count > 1
            maxRowSpan = max(maxRowSpan, lines.count)
            maxColumnSpan[index] = max(maxColumnSpan[index], lines.map(\.count).max() ?? 0)
            columns.append(lines)
        }
        table.append((columns, maxRowSpan))
    }
    guard !table.isEmpty else { return }
    output.write("┌─")
    output.write(
        maxColumnSpan
            .map { String(repeating: "─", count: $0) }
            .joined(separator: "─┬─")
    )
    output.write("─┐\n")
    for (offset, rowAndMaxRowSpan) in table.enumerated() {
        let (row, maxRowSpan) = rowAndMaxRowSpan
        for rowOffset in 0..<maxRowSpan {
            output.write("│ ")
            var line: [String] = []
            for (columns, maxColumnSpan) in zip(row, maxColumnSpan) {
                if columns.count <= rowOffset {
                    line.append(String(repeating: " ", count: maxColumnSpan))
                } else {
                    line.append(
                        columns[rowOffset]
                            + String(
                                repeating: " ",
                                count: maxColumnSpan - columns[rowOffset].count
                            )
                    )
                }
            }
            output.write(line.joined(separator: " │ "))
            output.write(" │\n")
        }
        if hasMultiLineRows, offset != table.count - 1 {
            output.write("├─")
            output.write(
                maxColumnSpan
                    .map { String(repeating: "─", count: $0) }
                    .joined(separator: "─┼─")
            )
            output.write("─┤\n")
        }
    }
    output.write("└─")
    output.write(
        maxColumnSpan
            .map { String(repeating: "─", count: $0) }
            .joined(separator: "─┴─")
    )
    output.write("─┘")
}

/// Renders a single table cell.
///
/// Replicates the pointfree `customDump` scalar rendering the recorded snapshots
/// were produced with: optionals unwrap transparently (`nil` for none), strings
/// render quoted via `debugDescription`, everything else via `String(describing:)`.
private func renderCell(_ value: some Any) -> String {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first else { return "nil" }
        return renderCell(child.value)
    }
    if let string = value as? String {
        return string.debugDescription
    }
    if mirror.displayStyle == .enum {
        return ".\(value)"
    }
    return String(describing: value)
}
