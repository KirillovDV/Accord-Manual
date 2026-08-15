import Foundation
import SQLite3

final class SQLiteManualDatabase: @unchecked Sendable {
    private let database: OpaquePointer
    private let queue = DispatchQueue(label: "AccordManual.SQLite", qos: .userInitiated)

    init(url: URL) throws {
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw DatabaseError.open(status)
        }
        database = connection
    }

    deinit { sqlite3_close(database) }

    func sections() throws -> [ManualSection] {
        try queue.sync { try rows(sql: "SELECT json FROM sections ORDER BY sort_order") { statement in try decode(ManualSection.self, blob: statement, column: 0) } }
    }

    func summaries() throws -> [ManualArticle] {
        try queue.sync {
            try rows(sql: "SELECT id,title,source_path,section_id,esm_key,applicability,has_images FROM articles WHERE is_service=0 ORDER BY rowid") { statement in
                let applicability = try decode(Applicability.self, blob: statement, column: 5)
                let section = text(statement, 3)?.split(separator: "/").map(String.init) ?? ["Руководство"]
                let hasImages = sqlite3_column_int(statement, 6) != 0
                let placeholder = hasImages ? [ManualImage(id: "summary", localRelativePath: "", caption: nil, altText: nil, width: nil, height: nil, articleID: text(statement, 0) ?? "")] : []
                return ManualArticle(id: text(statement, 0) ?? "", esmKey: text(statement, 4), title: text(statement, 1) ?? "Материал руководства", breadcrumbs: section, sourcePath: text(statement, 2) ?? "", blocks: [], plainText: "", links: [], images: placeholder, applicability: applicability, relatedArticleIDs: [])
            }
        }
    }

    func article(id: String) throws -> ManualArticle? {
        try queue.sync { try first(sql: "SELECT article_json FROM articles WHERE id=?", bindings: [id]) { try decode(ManualArticle.self, blob: $0, column: 0) } }
    }

    func article(path: String) throws -> ManualArticle? {
        try queue.sync { try first(sql: "SELECT article_json FROM articles WHERE source_path=?", bindings: [path]) { try decode(ManualArticle.self, blob: $0, column: 0) } }
    }

    func metadata<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try queue.sync { try first(sql: "SELECT value FROM metadata WHERE key=?", bindings: [key]) { try decode(type, blob: $0, column: 0) } }
    }

    func search(query: String, filters: SearchFilters, savedIDs: Set<String>) throws -> [SearchResult] {
        let expression = query.split(whereSeparator: { $0.isWhitespace }).map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }.joined(separator: " AND ")
        guard !expression.isEmpty else { return [] }
        return try queue.sync {
            let sql = """
            SELECT a.article_json,
                   snippet(article_fts, 2, '⟦', '⟧', ' … ', 28),
                   bm25(article_fts, 8.0, 2.0, 1.0)
              FROM article_fts
              JOIN articles a ON a.id=article_fts.article_id
             WHERE article_fts MATCH ?
             ORDER BY bm25(article_fts, 8.0, 2.0, 1.0)
             LIMIT 400
            """
            return try rows(sql: sql, bindings: [expression]) { statement -> SearchResult? in
                let article = try decode(ManualArticle.self, blob: statement, column: 0)
                guard ManualStore.matches(article, filters: filters, savedIDs: savedIDs) else { return nil }
                let excerpt = text(statement, 1) ?? String(article.plainText.prefix(180))
                let normalizedQuery = ManualStore.normalized(query)
                let normalizedTitle = ManualStore.normalized(article.title)
                let group: SearchResult.SearchGroup
                if normalizedTitle.contains(normalizedQuery) { group = .titles }
                else if query.range(of: "^[PCBU]?[0-9]{2,4}$", options: [.regularExpression, .caseInsensitive]) != nil || article.title.localizedCaseInsensitiveContains("DTC") { group = .diagnostic }
                else if article.blocks.contains(where: { $0.kind == .specification && ManualStore.normalized($0.text).contains(normalizedQuery) }) { group = .specifications }
                else { group = .text }
                return SearchResult(article: article, group: group, excerpt: excerpt, matchedText: query)
            }.compactMap { $0 }
        }
    }

    private enum DatabaseError: LocalizedError { case open(Int32); case query(String); var errorDescription: String? { switch self { case .open(let code): "Не удалось открыть SQLite (\(code))."; case .query(let message): message } } }
    private func rows<T>(sql: String, bindings: [String] = [], transform: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DatabaseError.query(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { values.append(try transform(statement)) }
        return values
    }
    private func first<T>(sql: String, bindings: [String], transform: (OpaquePointer) throws -> T) throws -> T? { try rows(sql: sql, bindings: bindings, transform: transform).first }
    private func bind(_ values: [String], to statement: OpaquePointer) { let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self); for (index, value) in values.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) } }
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }
    private func decode<T: Decodable>(_ type: T.Type, blob statement: OpaquePointer, column: Int32) throws -> T { let count = Int(sqlite3_column_bytes(statement, column)); guard let bytes = sqlite3_column_blob(statement, column) else { throw DatabaseError.query("Пустая запись базы.") }; return try JSONDecoder().decode(type, from: Data(bytes: bytes, count: count)) }
    private var errorMessage: String { sqlite3_errmsg(database).map { String(cString: $0) } ?? "Ошибка SQLite" }
}
