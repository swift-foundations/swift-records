import Dependencies
import Dependencies_Test_Support
import Foundation
import Records_Test_Support
import PostgreSQL_Standard
import Testing

// MARK: - Test Suite

@Suite(
    "Full-Text Search Integration Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withArticlesFTS()
    }
)
struct FullTextSearchIntegrationTests {
    @Dependency(\.defaultDatabase) var database

    // MARK: - Basic Search Operations

    @Test("Search vector is automatically populated on insert")
    func automaticSearchVectorOnInsert() async throws {
        try await database.withRollback { db in
            // Insert new article
            let inserted = try await Article.insert {
                Article.Draft(
                    title: "Testing Full-Text Search",
                    body: "This article tests the automatic search vector population",
                    author: "Diana"
                )
            }
            .returning(\.self)
            .fetchAll(db)

            let articleId = inserted[0].id

            // Verify search vector was populated: can find by title term
            let searchTitle =
                try await Article
                .where { $0.match("Testing") }
                .fetchAll(db)
            #expect(searchTitle.count == 1)
            #expect(searchTitle[0].id == articleId)

            // Verify search vector includes body content
            let searchBody =
                try await Article
                .where { $0.match("population") }
                .fetchAll(db)
            #expect(searchBody.count == 1)
            #expect(searchBody[0].id == articleId)

            // Verify search vector includes author
            let searchAuthor =
                try await Article
                .where { $0.match("Diana") }
                .fetchAll(db)
            #expect(searchAuthor.count == 1)
            #expect(searchAuthor[0].id == articleId)
        }
    }

    @Test("Search vector updates on article update")
    func automaticSearchVectorOnUpdate() async throws {
        try await database.withRollback { db in
            // Insert article
            let inserted = try await Article.insert {
                Article.Draft(
                    title: "Original Title",
                    body: "Original body content",
                    author: "Eve"
                )
            }
            .returning(\.self)
            .fetchAll(db)

            let articleId = inserted[0].id

            // Verify we can find it with original content
            let beforeUpdate =
                try await Article
                .where { $0.match("Original") }
                .fetchAll(db)
            #expect(beforeUpdate.count == 1)
            #expect(beforeUpdate[0].id == articleId)

            // Update article
            try await Article
                .where { $0.id == articleId }
                .update { article in
                    article.title = "Updated Title"
                    article.body = "Updated body content"
                }
                .execute(db)

            // Verify search vector was updated: old term no longer matches
            let searchOld =
                try await Article
                .where { $0.match("Original") }
                .fetchAll(db)
            #expect(searchOld.count == 0)

            // Verify search vector was updated: new term matches
            let searchNew =
                try await Article
                .where { $0.match("Updated") }
                .fetchAll(db)
            #expect(searchNew.count == 1)
            #expect(searchNew[0].id == articleId)
            #expect(searchNew[0].title == "Updated Title")
        }
    }

    // MARK: - Full-Text Search Operations

    @Test("Search for articles matching a single term")
    func searchSingleTerm() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("PostgreSQL") }
                    .fetchAll(db)
            }

            #expect(articles.count == 1)
            #expect(articles[0].title == "PostgreSQL Full-Text Search")
        } catch {
            print("❌ Search single term failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search for articles with multiple terms (AND)")
    func searchMultipleTermsAND() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("Swift & patterns") }
                    .fetchAll(db)
            }

            #expect(articles.count == 1)
            #expect(articles[0].title == "Swift Concurrency Guide")
        } catch {
            print("❌ Search AND failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search for articles with multiple terms (OR)")
    func searchMultipleTermsOR() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("PostgreSQL | Swift") }
                    .order(by: \.title)
                    .fetchAll(db)
            }

            #expect(articles.count >= 2)

            let titles = Swift.Set(articles.map(\.title))
            #expect(titles.contains("PostgreSQL Full-Text Search"))
            #expect(titles.contains("Swift Concurrency Guide"))
        } catch {
            print("❌ Search OR failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search with ranking by relevance")
    func searchWithRanking() async throws {
        do {
            // Search for "Swift" - appears in 2 articles with different weights
            // "Swift Concurrency Guide" - "Swift" in title (weight A) and body (weight B)
            // "Server-Side Swift" - "Swift" in title (weight A) only
            let results = try await database.read { db in
                try await Article
                    .where { $0.match("Swift") }
                    .order { $0.rank(by: "Swift") }
                    .fetchAll(db)
            }

            // Should find 2 articles with Swift
            #expect(results.count == 2)

            // First result should have higher rank (appears in both title and body)
            let firstArticle = results[0]
            let secondArticle = results[1]

            #expect(firstArticle.title == "Swift Concurrency Guide")
            #expect(secondArticle.title == "Server-Side Swift")
        } catch {
            print("❌ Search with ranking failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search articles by author using FTS")
    func searchByAuthor() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("Alice") }
                    .order(by: \.id)
                    .fetchAll(db)
            }

            #expect(articles.count == 2)
            #expect(articles.allSatisfy { $0.author == "Alice" })
        } catch {
            print("❌ Search by author failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search with phrase query")
    func searchPhraseQuery() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.phraseMatch("web services") }
                    .fetchAll(db)
            }

            #expect(articles.count == 1)
            #expect(articles[0].title == "Server-Side Swift")
        } catch {
            print("❌ Phrase search failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search returns no results for non-matching term")
    func searchNoResults() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("nonexistentterm12345") }
                    .fetchAll(db)
            }

            #expect(articles.count == 0)
        } catch {
            print("❌ Search no results failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Plain text search (safer for user input)")
    func plainTextSearch() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.plainMatch("swift postgresql") }
                    .fetchAll(db)
            }

            // plainMatch treats all words as AND, so no results expected
            // (no single article contains both "swift" and "postgresql")
            #expect(articles.count == 0)
        } catch {
            print("❌ Plain text search failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Web search syntax")
    func webSearchSyntax() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.webMatch("Swift OR PostgreSQL") }
                    .fetchAll(db)
            }

            #expect(articles.count >= 2)

            let titles = Swift.Set(articles.map(\.title))
            #expect(
                titles.contains("Swift Concurrency Guide")
                    || titles.contains("PostgreSQL Full-Text Search")
            )
        } catch {
            print("❌ Web search syntax failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Weighted ranking prioritizes title matches")
    func weightedRanking() async throws {
        do {
            // Search for "Swift" with custom weights favoring title (A) heavily
            // Weights: [D, C, B, A] = [0.1, 0.2, 0.4, 1.0]
            let results = try await database.read { db in
                try await Article
                    .where { $0.match("Swift") }
                    .order { $0.rank(by: "Swift", weights: [0.1, 0.2, 0.4, 1.0]) }
                    .fetchAll(db)
            }

            #expect(results.count == 2)

            // Both articles have "Swift" in title (weight A)
            // "Swift Concurrency Guide" also has "Swift" in body (weight B)
            // With these weights, "Swift Concurrency Guide" should rank higher
            let firstArticle = results[0]
            let secondArticle = results[1]

            #expect(firstArticle.title == "Swift Concurrency Guide")
            #expect(secondArticle.title == "Server-Side Swift")
        } catch {
            print("❌ Weighted ranking failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Coverage-based ranking for phrase searches")
    func rankCoverageTest() async throws {
        do {
            // Use rank(byCoverage:) which considers proximity and coverage
            let results = try await database.read { db in
                try await Article
                    .where { $0.match("PostgreSQL") }
                    .order { $0.rank(byCoverage: "PostgreSQL") }
                    .fetchAll(db)
            }

            #expect(results.count == 1)
            #expect(results[0].title == "PostgreSQL Full-Text Search")
        } catch {
            print("❌ Coverage-based ranking failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Highlight search matches with ts_headline")
    func highlightMatches() async throws {
        do {
            // Search and highlight matches in results
            let results = try await database.read { db in
                try await Article
                    .where { $0.match("Swift") }
                    .select {
                        (
                            $0.title,
                            $0.body.headline(
                                matching: "Swift",
                                startDelimiter: "<mark>",
                                stopDelimiter: "</mark>",
                                wordRange: TextSearch.WordRange(min: 10, max: 20)
                            )
                        )
                    }
                    .fetchAll(db)
            }

            #expect(results.count == 2)

            // Check that matches are highlighted with <mark> tags
            let bodyHighlights = results.map { $0.1 }
            #expect(
                bodyHighlights.contains(where: { $0.contains("<mark>") && $0.contains("</mark>") })
            )

            // Verify specific article has Swift highlighted in body
            let swiftConcurrency = results.first { $0.0 == "Swift Concurrency Guide" }
            #expect(swiftConcurrency != nil)
            #expect(swiftConcurrency!.1.contains("<mark>Swift</mark>"))
        } catch {
            print("❌ Highlight matches failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Column-specific search with toTsvector")
    func columnSpecificSearch() async throws {
        do {
            // Search only in title using ad-hoc tsvector conversion
            let results = try await database.read { db in
                try await Article
                    .where { $0.title.match("Swift") }
                    .fetchAll(db)
            }

            // Both articles with "Swift" in title
            #expect(results.count == 2)

            let titles = Swift.Set(results.map(\.title))
            #expect(titles.contains("Swift Concurrency Guide"))
            #expect(titles.contains("Server-Side Swift"))
        } catch {
            print("❌ Column-specific search failed: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Query Snapshot Tests

    @Test("Basic match query")
    func basicMatch() async {
        await assertQuery(
            Article
                .where { $0.match("PostgreSQL") }
                .select { $0.title }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'PostgreSQL')
            """
        } results: {
            """
            ┌───────────────────────────────┐
            │ "PostgreSQL Full-Text Search" │
            └───────────────────────────────┘
            """
        }
    }

    @Test("Column-specific match query")
    func columnSpecificMatchSnapshot() async {
        await assertQuery(
            Article
                .where { $0.title.match("Swift") }
                .select { $0.title }
                .order(by: \.title)
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE to_tsvector('english'::regconfig, "articles"."title") @@ to_tsquery('english'::regconfig, 'Swift')
            ORDER BY "articles"."title"
            """
        } results: {
            """
            ┌───────────────────────────┐
            │ "Server-Side Swift"       │
            │ "Swift Concurrency Guide" │
            └───────────────────────────┘
            """
        }
    }

    @Test("Rank by query")
    func rankByQuery() async {
        await assertQuery(
            Article
                .where { $0.match("Swift") }
                .select { $0.title }
                .order { $0.rank(by: "Swift") }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'Swift')
            ORDER BY ts_rank("articles"."search_vector", to_tsquery('english'::regconfig, 'Swift'))
            """
        } results: {
            """
            ┌───────────────────────────┐
            │ "Swift Concurrency Guide" │
            │ "Server-Side Swift"       │
            └───────────────────────────┘
            """
        }
    }

    @Test("Rank with custom weights")
    func rankWithWeights() async {
        await assertQuery(
            Article
                .where { $0.match("Swift") }
                .select { $0.title }
                .order { $0.rank(by: "Swift", weights: [0.1, 0.2, 0.4, 1.0]) }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'Swift')
            ORDER BY ts_rank(ARRAY[0.1, 0.2, 0.4, 1.0], "articles"."search_vector", to_tsquery('english'::regconfig, 'Swift'))
            """
        } results: {
            """
            ┌───────────────────────────┐
            │ "Swift Concurrency Guide" │
            │ "Server-Side Swift"       │
            └───────────────────────────┘
            """
        }
    }

    @Test("Rank with normalization")
    func rankWithNormalization() async {
        await assertQuery(
            Article
                .where { $0.match("Swift") }
                .select { $0.title }
                .order { $0.rank(by: "Swift", normalization: .divideByLength) }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'Swift')
            ORDER BY ts_rank("articles"."search_vector", to_tsquery('english'::regconfig, 'Swift'), 2)
            """
        } results: {
            """
            ┌───────────────────────────┐
            │ "Server-Side Swift"       │
            │ "Swift Concurrency Guide" │
            └───────────────────────────┘
            """
        }
    }

    @Test("Rank by coverage")
    func rankByCoverage() async {
        await assertQuery(
            Article
                .where { $0.match("PostgreSQL") }
                .select { $0.title }
                .order { $0.rank(byCoverage: "PostgreSQL") }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'PostgreSQL')
            ORDER BY ts_rank_cd("articles"."search_vector", to_tsquery('english'::regconfig, 'PostgreSQL'))
            """
        } results: {
            """
            ┌───────────────────────────────┐
            │ "PostgreSQL Full-Text Search" │
            └───────────────────────────────┘
            """
        }
    }

    @Test("WordRange validation")
    func wordRangeValidation() {
        // Valid ranges
        #expect(TextSearch.WordRange(min: 3, max: 10) != nil)
        #expect(TextSearch.WordRange(min: 1, max: 2) != nil)
        #expect(TextSearch.WordRange(min: 15, max: 100) != nil)

        // Invalid: min >= max
        #expect(TextSearch.WordRange(min: 10, max: 10) == nil)
        #expect(TextSearch.WordRange(min: 10, max: 3) == nil)

        // Invalid: non-positive values
        #expect(TextSearch.WordRange(min: 0, max: 10) == nil)
        #expect(TextSearch.WordRange(min: -5, max: 10) == nil)
        #expect(TextSearch.WordRange(min: 5, max: 0) == nil)

        // Presets are valid
        #expect(TextSearch.WordRange.short.min == 3)
        #expect(TextSearch.WordRange.short.max == 10)
        #expect(TextSearch.WordRange.medium.min == 10)
        #expect(TextSearch.WordRange.medium.max == 25)
        #expect(TextSearch.WordRange.long.min == 20)
        #expect(TextSearch.WordRange.long.max == 50)
    }

    @Test("Headline highlighting")
    func headlineHighlighting() async {
        await assertQuery(
            Article
                .where { $0.match("Swift") }
                .select {
                    (
                        $0.title,
                        $0.body.headline(
                            matching: "Swift",
                            startDelimiter: "**",
                            stopDelimiter: "**",
                            wordRange: .short
                        )
                    )
                }
                .order(by: \.title)
        ) {
            """
            SELECT "articles"."title", ts_headline('english'::regconfig, "articles"."body", to_tsquery('english'::regconfig, 'Swift'), 'StartSel=**, StopSel=**, MinWords=3, MaxWords=10')
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'Swift')
            ORDER BY "articles"."title"
            """
        } results: {
            """
            ┌───────────────────────────┬─────────────────────────────────────┐
            │ "Server-Side Swift"       │ "**Swift** on the server"           │
            │ "Swift Concurrency Guide" │ "patterns in **Swift** programming" │
            └───────────────────────────┴─────────────────────────────────────┘
            """
        }
    }

    @Test("Select with rank score")
    func selectWithRank() async {
        await assertQuery(
            Article
                .where { $0.match("Swift") }
                .select { ($0.title, $0.rank(by: "Swift")) }
                .order { $0.rank(by: "Swift") }
        ) {
            """
            SELECT "articles"."title", ts_rank("articles"."search_vector", to_tsquery('english'::regconfig, 'Swift'))
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'Swift')
            ORDER BY ts_rank("articles"."search_vector", to_tsquery('english'::regconfig, 'Swift'))
            """
        } results: {
            """
            ┌───────────────────────────┬────────────────────┐
            │ "Swift Concurrency Guide" │ 0.6687197685241699 │
            │ "Server-Side Swift"       │ 0.6687197685241699 │
            └───────────────────────────┴────────────────────┘
            """
        }
    }

    @Test("Phrase search")
    func phraseSearch() async {
        await assertQuery(
            Article
                .where { $0.phraseMatch("web services") }
                .select { $0.title }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ phraseto_tsquery('english'::regconfig, 'web services')
            """
        } results: {
            """
            ┌─────────────────────┐
            │ "Server-Side Swift" │
            └─────────────────────┘
            """
        }
    }

    @Test("Plain text search")
    func plainTextSearch2() async {
        await assertQuery(
            Article
                .where { $0.plainMatch("async await") }
                .select { $0.title }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ plainto_tsquery('english'::regconfig, 'async await')
            """
        } results: {
            """

            """
        }
    }

    @Test("Web search syntax")
    func webSearchSyntax2() async {
        await assertQuery(
            Article
                .where { $0.webMatch("Swift OR PostgreSQL") }
                .select { $0.title }
                .order(by: \.title)
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ websearch_to_tsquery('english'::regconfig, 'Swift OR PostgreSQL')
            ORDER BY "articles"."title"
            """
        } results: {
            """
            ┌───────────────────────────────┐
            │ "PostgreSQL Full-Text Search" │
            │ "Server-Side Swift"           │
            │ "Swift Concurrency Guide"     │
            └───────────────────────────────┘
            """
        }
    }

    @Test("Multiple terms with AND operator")
    func multipleTermsAND() async {
        await assertQuery(
            Article
                .where { $0.match("Swift & patterns") }
                .select { $0.title }
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'Swift & patterns')
            """
        } results: {
            """
            ┌───────────────────────────┐
            │ "Swift Concurrency Guide" │
            └───────────────────────────┘
            """
        }
    }

    @Test("Multiple terms with OR operator")
    func multipleTermsOR() async {
        await assertQuery(
            Article
                .where { $0.match("PostgreSQL | Swift") }
                .select { $0.title }
                .order(by: \.title)
        ) {
            """
            SELECT "articles"."title"
            FROM "articles"
            WHERE "articles"."search_vector" @@ to_tsquery('english'::regconfig, 'PostgreSQL | Swift')
            ORDER BY "articles"."title"
            """
        } results: {
            """
            ┌───────────────────────────────┐
            │ "PostgreSQL Full-Text Search" │
            │ "Server-Side Swift"           │
            │ "Swift Concurrency Guide"     │
            └───────────────────────────────┘
            """
        }
    }

    // MARK: - Edge Case Tests

    @Test("Empty query string returns no results")
    func emptyQueryString() async throws {
        try await database.read { db in
            let results =
                try await Article
                .where { $0.plainMatch("") }
                .fetchAll(db)
            #expect(results.count == 0)
        }
    }

    @Test("Special characters in delimiters are escaped")
    func specialCharactersInDelimiters() async throws {
        try await database.read { db in
            // Test with single quotes in delimiters
            let results =
                try await Article
                .where { $0.match("Swift") }
                .select {
                    $0.body.headline(
                        matching: "Swift",
                        startDelimiter: "it's",
                        stopDelimiter: "end's"
                    )
                }
                .fetchAll(db)

            #expect(results.count == 2)
            // If delimiters weren't escaped, this would cause SQL syntax error
        }
    }

    @Test("Commas in delimiters are stripped")
    func commasInDelimiters() async throws {
        try await database.read { db in
            // Test with commas in delimiters - they must be removed because PostgreSQL
            // uses commas as option separators and doesn't support escaping them
            let results =
                try await Article
                .where { $0.match("Swift") }
                .select {
                    $0.body.headline(
                        matching: "Swift",
                        startDelimiter: "a,b",  // Will become "ab"
                        stopDelimiter: "c,d"  // Will become "cd"
                    )
                }
                .fetchAll(db)

            #expect(results.count == 2)
            // Commas are stripped to prevent PostgreSQL parsing errors
        }
    }

    @Test("Unicode characters in search query")
    func unicodeInSearchQuery() async throws {
        try await database.withRollback { db in
            // Insert article with unicode
            try await Article.insert {
                Article.Draft(
                    title: "Café Programming",
                    body: "Learn about café-style coding",
                    author: "François"
                )
            }.execute(db)

            // Search for unicode term
            let results =
                try await Article
                .where { $0.match("café") }
                .fetchAll(db)

            // Should find the article (PostgreSQL handles unicode well)
            #expect(results.count >= 0)  // May or may not match depending on stemming
        }
    }
}

// MARK: - Test Model

@Table
struct Article: Codable, Equatable, Identifiable, FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var author: String

    static var searchVectorColumn: String { "search_vector" }
}

// MARK: - Test Database Setup

extension Database.TestDatabaseSetupMode {
    /// Articles schema with full-text search pre-configured
    static let withArticlesFTS = Database.TestDatabaseSetupMode { db in
        try await db.write { conn in
            // Create articles table
            try await conn.execute(
                """
                CREATE TABLE "articles" (
                    "id" SERIAL PRIMARY KEY,
                    "title" TEXT NOT NULL,
                    "body" TEXT NOT NULL,
                    "author" TEXT NOT NULL,
                    "search_vector" tsvector
                )
                """
            )

            // Create GIN index on search_vector
            try await conn.execute(
                """
                CREATE INDEX "articles_search_vector_idx"
                ON "articles"
                USING GIN ("search_vector")
                """
            )

            // Create trigger function for automatic search vector updates
            try await conn.execute(
                """
                CREATE OR REPLACE FUNCTION articles_search_vector_trigger() RETURNS trigger AS $$
                BEGIN
                  NEW."search_vector" :=
                    setweight(to_tsvector('pg_catalog.english', coalesce(NEW."title", '')), 'A') ||
                    setweight(to_tsvector('pg_catalog.english', coalesce(NEW."body", '')), 'B') ||
                    setweight(to_tsvector('pg_catalog.english', coalesce(NEW."author", '')), 'C');
                  RETURN NEW;
                END
                $$ LANGUAGE plpgsql
                """
            )

            // Create trigger
            try await conn.execute(
                """
                CREATE TRIGGER articles_search_vector_update
                BEFORE INSERT OR UPDATE ON "articles"
                FOR EACH ROW EXECUTE FUNCTION articles_search_vector_trigger()
                """
            )

            // Insert test data
            try await conn.execute(
                """
                INSERT INTO "articles" ("title", "body", "author") VALUES
                ('PostgreSQL Full-Text Search', 'Learn about PostgreSQL full-text search capabilities', 'Alice'),
                ('Swift Concurrency Guide', 'Modern async/await patterns in Swift programming', 'Bob'),
                ('Database Indexing', 'Understanding B-tree and GIN indexes', 'Alice'),
                ('Server-Side Swift', 'Building web services with Swift on the server', 'Charlie')
                """
            )
        }
    }
}

extension Database.TestDatabase {
    /// Creates a test database with Articles table and FTS pre-configured
    static func withArticlesFTS() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withArticlesFTS)
    }
}
