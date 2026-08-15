import Foundation
import Observation

@Observable @MainActor final class ManualStore {
    private(set) var package: ManualPackage = .demo
    private(set) var metadata: ManualMetadata?
    private(set) var diagnostics: [ImportDiagnostic] = []
    private(set) var loadError: String?
    private var database: SQLiteManualDatabase?
    private var articleByID: [String: ManualArticle] = [:]
    private var articleIDByPath: [String: String] = [:]
    var articles: [ManualArticle] { package.articles }
    var sections: [ManualSection] { package.sections }

    init() { loadBundle() }

    func loadBundle() {
        loadError = nil
        if let url = Bundle.main.url(forResource: "manual", withExtension: "sqlite", subdirectory: "ManualBundle") {
            do {
                let database = try SQLiteManualDatabase(url: url)
                let summaries = try database.summaries()
                let sections = try database.sections()
                self.database = database
                package = ManualPackage(sections: sections, articles: summaries)
                articleByID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
                articleIDByPath = Dictionary(uniqueKeysWithValues: summaries.map { ($0.sourcePath, $0.id) })
                metadata = try database.metadata(ManualMetadata.self, key: "metadata")
                diagnostics = try database.metadata([ImportDiagnostic].self, key: "diagnostics") ?? []
                return
            } catch { loadError = "Не удалось открыть локальную SQLite-базу: \(error.localizedDescription)" }
        }
        loadJSONFallback()
    }

    /// Checks the open bundled package, local SQLite file, media directory, and
    /// importer diagnostics without accessing the network or changing navigation state.
    func runLocalDiagnostics() -> LocalDiagnosticReport {
        let databaseURL = Bundle.main.url(forResource: "manual", withExtension: "sqlite", subdirectory: "ManualBundle")
        let packageSize = databaseURL.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init)
        let mediaDirectory = Bundle.main.resourceURL?.appendingPathComponent("ManualBundle/media", isDirectory: true)
        let mediaFiles = mediaDirectory.flatMap { directory in
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])?
                .compactMap { $0 as? URL }
                .filter { url in (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .count
        } ?? 0

        var runtimeIssues: [String] = []
        if databaseURL == nil { runtimeIssues.append("Не найден файл локальной SQLite-базы.") }
        if mediaDirectory == nil { runtimeIssues.append("Не найдена папка локальных медиафайлов.") }
        if let loadError { runtimeIssues.append(loadError) }
        let status: String
        if database != nil { status = "SQLite-база открыта" }
        else if loadError == nil { status = "Загружен резервный демонстрационный набор" }
        else { status = "Не удалось открыть пакет" }

        return LocalDiagnosticReport(
            generatedAt: Date(),
            packageStatus: status,
            packageSize: packageSize,
            metadata: metadata,
            catalogueArticleCount: articles.count,
            sectionCount: sections.count,
            mediaFileCount: mediaFiles,
            diagnostics: diagnostics,
            runtimeIssues: runtimeIssues
        )
    }

    func article(id: String) -> ManualArticle? { articleByID[id] }

    func loadArticle(id: String) async -> ManualArticle? {
        if let cached = articleByID[id], !cached.blocks.isEmpty { return cached }
        guard let database else { return articleByID[id] }
        let loaded = try? await Task.detached(priority: .userInitiated) { try database.article(id: id) }.value
        if let loaded { articleByID[id] = loaded }
        return loaded ?? articleByID[id]
    }

    func summary(id: String) -> ManualArticle? { articleByID[id] }
    func article(path: String) -> ManualArticle? {
        if let cached = articleIDByPath[path].flatMap({ articleByID[$0] }) { return cached }
        guard let database, let loaded = try? database.article(path: path) else { return nil }
        articleByID[loaded.id] = loaded
        articleIDByPath[path] = loaded.id
        return loaded
    }
    func children(of parentID: String?) -> [ManualSection] { package.sections.filter { $0.parentID == parentID }.sorted { $0.sortOrder < $1.sortOrder } }

    func search(_ query: String, filters: SearchFilters = .init(), savedIDs: Set<String> = []) async -> [SearchResult] {
        guard Self.normalized(query).count > 1 else { return [] }
        if let database { return (try? await Task.detached(priority: .userInitiated) { try database.search(query: query, filters: filters, savedIDs: savedIDs) }.value) ?? [] }
        return articles.compactMap { article in
            let title = Self.normalized(article.title), body = Self.normalized(article.plainText)
            guard Self.matches(article, filters: filters, savedIDs: savedIDs), title.contains(Self.normalized(query)) || body.contains(Self.normalized(query)) else { return nil }
            return SearchResult(article: article, group: title.contains(Self.normalized(query)) ? .titles : .text, excerpt: Self.excerpt(article.plainText, needle: query), matchedText: query)
        }
    }

    nonisolated static func normalized(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")).lowercased() }
    nonisolated static func matches(_ article: ManualArticle, filters: SearchFilters, savedIDs: Set<String>) -> Bool {
        let matchesType: Bool
        switch filters.manualType {
        case "diagnostic": matchesType = article.title.localizedCaseInsensitiveContains("DTC") || article.title.localizedCaseInsensitiveContains("диагност") || article.plainText.range(of: "\\b[PCBU][0-9]{4}\\b", options: [.regularExpression, .caseInsensitive]) != nil
        case "procedure": matchesType = article.blocks.contains { $0.kind == .numberedSteps }
        case "specification": matchesType = article.blocks.contains { $0.kind == .specification || $0.kind == .table }
        default: matchesType = true
        }
        return matchesType && (!filters.imagesOnly || !article.images.isEmpty) && (!filters.savedOnly || savedIDs.contains(article.id)) && (filters.sectionID == nil || article.sectionID.hasPrefix(filters.sectionID ?? "")) && (filters.year == nil || article.applicability.years.isEmpty || article.applicability.years.contains(filters.year ?? 0)) && (filters.bodyCode == nil || article.applicability.bodyCodes.isEmpty || article.applicability.bodyCodes.contains(filters.bodyCode ?? "")) && (filters.engineCode == nil || article.applicability.engineCodes.isEmpty || article.applicability.engineCodes.contains(filters.engineCode ?? "")) && (filters.transmission == nil || article.applicability.transmissions.isEmpty || article.applicability.transmissions.contains(filters.transmission ?? ""))
    }
    nonisolated static func compatibilityScore(_ article: ManualArticle, preference: SearchFilters) -> Int {
        var score = 0
        func apply<T: Equatable>(_ selected: T?, values: [T]) {
            guard let selected, !values.isEmpty else { return }
            score += values.contains(selected) ? 2 : -1
        }
        apply(preference.year, values: article.applicability.years)
        apply(preference.bodyCode, values: article.applicability.bodyCodes)
        apply(preference.engineCode, values: article.applicability.engineCodes)
        apply(preference.transmission, values: article.applicability.transmissions)
        return score
    }
    nonisolated static func excerpt(_ text: String, needle: String) -> String { guard let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(text.prefix(180)) }; let start = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex; let end = text.index(range.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex; return "…" + String(text[start..<end]) + "…" }

    private func loadJSONFallback() {
        guard let url = Bundle.main.url(forResource: "manual", withExtension: "json", subdirectory: "ManualBundle") ?? Bundle.main.url(forResource: "manual", withExtension: "json") else { return }
        do {
            package = try JSONDecoder().decode(ManualPackage.self, from: Data(contentsOf: url))
            articleByID = Dictionary(uniqueKeysWithValues: package.articles.map { ($0.id, $0) })
            articleIDByPath = Dictionary(uniqueKeysWithValues: package.articles.map { ($0.sourcePath, $0.id) })
            metadata = loadJSON(ManualMetadata.self, named: "metadata")
            diagnostics = loadJSON([ImportDiagnostic].self, named: "diagnostics") ?? []
        } catch { loadError = "Не удалось открыть локальный пакет: \(error.localizedDescription)" }
    }
    private func loadJSON<T: Decodable>(_ type: T.Type, named: String) -> T? { guard let url = Bundle.main.url(forResource: named, withExtension: "json", subdirectory: "ManualBundle") else { return nil }; return try? JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
}

extension ManualPackage { static let demo = ManualPackage(sections: [ManualSection(id: "Руководство", title: "Руководство", parentID: nil, sortOrder: 0, breadcrumbPath: ["Руководство"], applicability: .init(years: [], bodyCodes: [], engineCodes: [], transmissions: []))], articles: []) }
