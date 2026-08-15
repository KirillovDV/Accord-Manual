import Foundation
import SQLite3

public struct SearchDocument: Codable, Sendable {
    public var articleID: String
    public var normalizedTitle: String
    public var normalizedText: String
    public var tags: [String]
    public var dtcCodes: [String]
    public var engineCodes: [String]
}
public struct ImportDiagnostic: Codable, Sendable { public var severity: String; public var path: String; public var message: String }
public struct ImportMetadata: Codable, Sendable { public var formatVersion: Int; public var importedAt: String; public var sourceTitle: String?; public var pageCount: Int; public var imageCount: Int; public var sectionCount: Int; public var indexedTokenCount: Int }
public struct ManualPackage: Codable, Sendable { public var sections: [ImportedSection]; public var articles: [ImportedArticle] }
public struct ImportReport: Sendable { public var metadata: ImportMetadata; public var diagnostics: [ImportDiagnostic] }

public final class ESMImporter: Sendable {
    public init() {}
    @discardableResult public func importManual(input: URL, output: URL, copyMedia: Bool = true) throws -> ImportReport {
        let root = input.standardizedFileURL
        let manager = FileManager.default
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try enumerateFiles(at: root)
        let catalogue = contentCatalogue(at: root)
        let modelApplicability = modelApplicabilityByDGC(at: root)
        let htmlFiles = files.filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
        var actualPathByLowercase: [String: String] = [:]
        for file in files {
            let relative = relativePath(file, root: root)
            actualPathByLowercase[relative.lowercased()] = relative
        }
        let knownPaths = actualPathByLowercase
        let imagePathResolver: @Sendable (String) -> String = { path in
            let normalized = knownPaths[path.lowercased()] ?? path
            guard normalized.lowercased().hasPrefix("ru/tn/") else { return normalized }
            let basename = URL(fileURLWithPath: normalized).lastPathComponent
            return knownPaths["ru/img/\(basename)".lowercased()] ?? normalized
        }
        var articles: [ImportedArticle] = []
        var diagnostics: [ImportDiagnostic] = []
        for file in htmlFiles {
            let relative = relativePath(file, root: root)
            do {
                let data = try Data(contentsOf: file)
                let html = expandLegacyImageScripts(in: decodeHTML(data), sourcePath: relative, root: root)
                let fallback = catalogue[pageKey(relative)]
                let rawTitle = htmlTitle(html)
                let visibleTitle = visibleTopicTitle(html)
                let title: String
                if let fallback { title = fallback.title }
                else if usefulTitle(visibleTitle) { title = visibleTitle }
                else { title = usefulTitle(rawTitle) ? rawTitle : "" }
                var article = try HTMLArticleParser.parse(html: html, id: stableID(relative), title: title, breadcrumbs: fallback?.breadcrumbs ?? breadcrumb(for: relative, title: title), sourcePath: relative, imagePathResolver: imagePathResolver)
                article.title = xmlDecode(article.title)
                if !usefulTitle(article.title) { article.title = readableFallbackTitle(for: relative) }
                article.blocks = article.blocks.enumerated().map { offset, block in
                    guard block.id.isEmpty else { return block }
                    var identified = block
                    identified.id = "\(article.id)-block-\(offset)"
                    return identified
                }
                article.applicability = applicability(
                    for: relative,
                    text: article.title + " " + article.plainText,
                    catalogueDGC: fallback?.dgc,
                    modelApplicability: modelApplicability
                )
                if fallback == nil,
                   let esmKeyBreadcrumbs = breadcrumbsFromESMKey(
                    article.esmKey ?? rawTitle,
                    sectionNames: catalogue.sectionNames,
                    componentNames: catalogue.componentNames,
                    systemNames: catalogue.systemNames
                   ) {
                    article.breadcrumbs = esmKeyBreadcrumbs
                }
                articles.append(article)
            } catch { diagnostics.append(ImportDiagnostic(severity: "error", path: relative, message: error.localizedDescription)) }
        }
        contextualizeTitles(&articles, cataloguedKeys: Set(catalogue.entries.keys))
        let existingPaths = Set(files.map { relativePath($0, root: root) })
        let canonicalPaths = Set(articles.filter { !isTechnicalPresentation($0.sourcePath) }.map(\.sourcePath))
        let articleIDByPath = Dictionary(uniqueKeysWithValues: articles
            .filter { canonicalPaths.contains($0.sourcePath) }
            .map { ($0.sourcePath, $0.id) })
        let anchorsByPath = Dictionary(uniqueKeysWithValues: articles.map { article in
            (article.sourcePath, Set(article.blocks.compactMap { $0.kind == .anchor ? $0.anchor : nil }))
        })
        for index in articles.indices {
            var related: [String] = []
            for block in articles[index].blocks where block.kind == .link {
                guard let target = block.target else { continue }
                let components = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                let path = String(components[0])
                if let targetID = articleIDByPath[path], targetID != articles[index].id, !related.contains(targetID) { related.append(targetID) }
                if components.count == 2 {
                    let anchor = String(components[1])
                    if !["000", "i000"].contains(anchor), anchorsByPath[path]?.contains(anchor) != true {
                        diagnostics.append(.init(severity: "warning", path: articles[index].sourcePath, message: "Missing target anchor: \(target)"))
                    }
                }
            }
            articles[index].relatedArticleIDs = related
            for link in articles[index].links where !existingPaths.contains(link) {
                diagnostics.append(ImportDiagnostic(severity: "warning", path: articles[index].sourcePath, message: "Broken internal link: \(link)"))
            }
        }
        let canonicalArticles = articles.filter { canonicalPaths.contains($0.sourcePath) }
        let sections = buildSections(from: canonicalArticles)
        let index = canonicalArticles.map(searchDocument)
        let sourceTitle = projectTitle(at: root)
        let metadata = ImportMetadata(formatVersion: 1, importedAt: ISO8601DateFormatter().string(from: Date()), sourceTitle: sourceTitle, pageCount: canonicalArticles.count, imageCount: canonicalArticles.reduce(0) { $0 + $1.images.count }, sectionCount: sections.count, indexedTokenCount: Set(index.flatMap(\.tags)).count)
        let package = ManualPackage(sections: sections, articles: articles)
        if copyMedia {
            let media = output.appendingPathComponent("media", isDirectory: true)
            try? manager.removeItem(at: media)
            try manager.createDirectory(at: media, withIntermediateDirectories: true)
            var copied = Set<String>()
            for image in articles.flatMap(\.images) where copied.insert(image.localRelativePath).inserted {
                copyMediaFile(image.localRelativePath, root: root, output: output, diagnostics: &diagnostics)
            }
        }
        try? manager.removeItem(at: output.appendingPathComponent("manual.json"))
        try? manager.removeItem(at: output.appendingPathComponent("search-index.json"))
        try write(metadata, name: "metadata.json", to: output)
        try write(diagnostics, name: "diagnostics.json", to: output)
        try writeSQLite(package: package, metadata: metadata, diagnostics: diagnostics, to: output.appendingPathComponent("manual.sqlite"))
        return ImportReport(metadata: metadata, diagnostics: diagnostics)
    }
    private func enumerateFiles(at root: URL) throws -> [URL] { try FileManager.default.subpathsOfDirectory(atPath: root.path).map { root.appendingPathComponent($0) }.filter { !$0.hasDirectoryPath } }
    private func decodeHTML(_ data: Data) -> String { String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? String(decoding: data, as: UTF8.self) }
    /// Honda ESM renders diagrams and their positioned labels through document.write().
    /// Decode the emitted markup without executing JavaScript so the native importer can
    /// retain the source image, canvas and annotation coordinates.
    private func expandLegacyImageScripts(in html: String, sourcePath: String, root: URL) -> String {
        let pattern = "(?is)<script\\b[^>]*\\bsrc\\s*=\\s*(['\\\"])(.*?)\\1[^>]*>.*?</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var expanded = html
        for match in matches.reversed() {
            guard let range = Range(match.range, in: expanded),
                  let sourceRange = Range(match.range(at: 2), in: html) else { continue }
            let scriptSource = String(html[sourceRange])
            guard let relative = LinkNormalizer.normalized(scriptSource, from: sourcePath) else { continue }
            let scriptURL = root.appendingPathComponent(relative).standardizedFileURL
            guard scriptURL.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: scriptURL) else { continue }
            let markup = documentWriteMarkup(in: decodeHTML(data))
            guard markup.range(of: "<img", options: .caseInsensitive) != nil else { continue }
            expanded.replaceSubrange(range, with: markup)
        }
        return expanded
    }

    private func documentWriteMarkup(in script: String) -> String {
        let patterns = [#"(?m)^\s*(?:document\.)?write\("(.*)"\);\s*$"#, #"(?m)^\s*(?:document\.)?write\('(.*)'\);\s*$"#]
        let fragments = patterns.flatMap { pattern -> [(Int, String)] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: script, range: NSRange(script.startIndex..., in: script)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: script) else { return nil }
                return (match.range.location, String(script[range]))
            }
        }
        return fragments.sorted { $0.0 < $1.0 }.map { _, fragment in
            fragment
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\'", with: "'")
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "\\n", with: "\n")
        }.joined(separator: "\n")
    }
    private func htmlTitle(_ html: String) -> String { HTMLArticleParser.parseTitle(html) }
    private func visibleTopicTitle(_ html: String) -> String {
        let pattern = "(?is)<(?:div|span)\\b[^>]*class\\s*=\\s*(['\\\"])[^'\\\"]*\\b(?:top_title|topic_title)\\b[^'\\\"]*\\1[^>]*>(.*?)</(?:div|span)>"
        guard let values = regexMatches(pattern, in: html).first, values.count > 2 else { return "" }
        return values[2]
            .replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func usefulTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !["Увеличенная схема", "Справочная иллюстрация", "Материал руководства"].contains(trimmed),
              trimmed.range(of: "^\\d+(?:_\\d+)?$", options: .regularExpression) == nil,
              trimmed.range(of: "^(?:ZOOM|SEA)[A-Z0-9_]+$", options: [.regularExpression, .caseInsensitive]) == nil else { return false }
        return trimmed.range(of: "^[A-Z][A-Z0-9_-]{10,}$", options: .regularExpression) == nil
    }
    private func pageKey(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.split(separator: "_").first.map(String.init) ?? "" }
    private func relativePath(_ url: URL, root: URL) -> String { url.path.replacingOccurrences(of: root.path + "/", with: "") }
    private func stableID(_ path: String) -> String { var value: UInt64 = 1469598103934665603; for byte in path.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }; return String(format: "%016llx", value) }
    private func breadcrumb(for path: String, title: String) -> [String] { let lower = "\(title) \(path)".lowercased(); let category: String; if lower.contains("тормоз") || lower.contains("abs") { category = "Тормоза" } else if lower.contains("двиг") || lower.contains("engine") { category = "Двигатель" } else if lower.contains("trans") || lower.contains("короб") { category = "Трансмиссия" } else if lower.contains("элект") || lower.contains("dtc") || lower.contains("diagn") { category = "Электрика и диагностика" } else if lower.contains("кузов") || lower.contains("body") { category = "Кузов" } else if lower.contains("подвес") || lower.contains("рулев") { category = "Подвеска и рулевое управление" } else { category = "Общее" }; return ["Руководство", category] }
    private func readableFallbackTitle(for path: String) -> String {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.uppercased()
        if name.hasPrefix("ZOOM") { return "Увеличенная схема" }
        if name.hasPrefix("SEA") { return "Справочная иллюстрация" }
        return "Материал руководства"
    }

    /// ZOOM and SEA pages are legacy print/expanded views invoked from a
    /// canonical ESM article. Retain them in SQLite so their original links
    /// still resolve, but keep them out of reader-facing catalogue/search.
    private func isTechnicalPresentation(_ sourcePath: String) -> Bool {
        let name = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent.uppercased()
        return name.hasPrefix("ZOOM") || name.hasPrefix("SEA")
            || name.range(of: "(?:_PR[12]?$|^ESMSELCT)", options: .regularExpression) != nil
    }
    private func contextualizeTitles(_ articles: inout [ImportedArticle], cataloguedKeys: Set<String>) {
        var indexByPath = Dictionary(uniqueKeysWithValues: articles.indices.map { (articles[$0].sourcePath, $0) })
        for _ in 0..<4 {
            var updates: [(Int, String, [String])] = []
            var updatedPaths = Set<String>()
            for source in articles where usefulTitle(source.title) {
                for block in source.blocks where block.kind == .link {
                    guard let target = block.target?.split(separator: "#", maxSplits: 1).first.map(String.init),
                          let targetIndex = indexByPath[target],
                          !cataloguedKeys.contains(pageKey(target)),
                          updatedPaths.insert(target).inserted else { continue }
                    let isIllustration = target.uppercased().contains("ZOOM") || target.uppercased().contains("SEA")
                    let linkTitle = xmlDecode(block.text).trimmingCharacters(in: .whitespacesAndNewlines)
                    let contextualTitle: String
                    if usefulTitle(articles[targetIndex].title) {
                        contextualTitle = articles[targetIndex].title
                    } else if isIllustration && usefulTitle(linkTitle) && linkTitle.count <= 140 {
                        contextualTitle = linkTitle
                    } else {
                        contextualTitle = source.title + (isIllustration ? " — схема" : "")
                    }
                    updates.append((targetIndex, contextualTitle, source.breadcrumbs))
                }
            }
            if updates.isEmpty { break }
            for (index, title, breadcrumbs) in updates {
                articles[index].title = title
                articles[index].breadcrumbs = breadcrumbs
            }
            indexByPath = Dictionary(uniqueKeysWithValues: articles.indices.map { (articles[$0].sourcePath, $0) })
        }
        let catalogueBreadcrumbsByTitle = Dictionary(grouping: articles.indices.filter {
            cataloguedKeys.contains(pageKey(articles[$0].sourcePath))
        }) { normalizedTitle(articles[$0].title) }.compactMapValues { indices -> [String]? in
            let paths = Set(indices.map { articles[$0].breadcrumbs })
            return paths.count == 1 ? paths.first : nil
        }
        for index in articles.indices where !cataloguedKeys.contains(pageKey(articles[index].sourcePath)) {
            if let breadcrumbs = catalogueBreadcrumbsByTitle[normalizedTitle(articles[index].title)] {
                articles[index].breadcrumbs = breadcrumbs
            }
        }
        for index in articles.indices where !usefulTitle(articles[index].title) {
            let filename = URL(fileURLWithPath: articles[index].sourcePath).deletingPathExtension().lastPathComponent
            if filename.range(of: "^(?:SML|SMT|BRL|BRT)_", options: [.regularExpression, .caseInsensitive]) != nil {
                articles[index].title = "Навигация исходного руководства"
            } else if let firstMeaningful = articles[index].blocks.first(where: { [.heading, .paragraph].contains($0.kind) && usefulTitle($0.text) })?.text {
                articles[index].title = String(firstMeaningful.prefix(140))
            } else if filename.uppercased().hasPrefix("ZOOM") {
                articles[index].title = "Увеличенная схема"
            } else if filename.uppercased().hasPrefix("SEA") {
                articles[index].title = "Справочная иллюстрация"
            } else {
                articles[index].title = "Материал руководства"
            }
        }
        disambiguateRepeatedTitles(&articles)
    }

    /// Honda's viewer pages frequently use a deliberately generic container title
    /// (for example, every wiring sheet is named "Схема электропроводки").  The
    /// sheet itself carries its subject as visible text.  Keep the original title
    /// as the prefix and add only text or model metadata actually present in ESM.
    private func disambiguateRepeatedTitles(_ articles: inout [ImportedArticle]) {
        // ZOOM/SEA are presentational copies of an ESM page.  They must not force
        // a canonical reader-facing article to acquire an artificial qualifier
        // (for example, "— лист 000…") merely because the copy has the same title.
        let canonicalIndices = articles.indices.filter { !isTechnicalPresentation(articles[$0].sourcePath) }
        let groups = Dictionary(grouping: canonicalIndices) { index in
            articles[index].breadcrumbs.joined(separator: "\u{1F}") + "\u{1E}" + normalizedTitle(articles[index].title)
        }
        for indices in groups.values where indices.count > 1 {
            var proposed: [Int: String] = [:]
            for index in indices {
                let base = articles[index].title
                let qualifier = titleQualifier(for: articles[index])
                proposed[index] = qualifier.map { base + " — " + $0 } ?? base + " — " + sourceSheetLabel(articles[index])
            }

            // A common subject may legitimately occur on more than one model.
            // Add exact applicability only when the content-derived qualifier is
            // still ambiguous; it is never guessed from the filename.
            let collisions = Dictionary(grouping: indices) { proposed[$0] ?? articles[$0].title }
            for duplicate in collisions.values where duplicate.count > 1 {
                for index in duplicate {
                    let model = applicabilityLabel(articles[index].applicability)
                    if !model.isEmpty { proposed[index] = (proposed[index] ?? articles[index].title) + " — " + model }
                }
            }

            // Page identifiers are native ESM identifiers. They are used only as
            // a final, factual distinction when neither content nor model data
            // differentiates two separate source sheets.
            let remaining = Dictionary(grouping: indices) { proposed[$0] ?? articles[$0].title }
            for duplicate in remaining.values where duplicate.count > 1 {
                for index in duplicate {
                    proposed[index] = (proposed[index] ?? articles[index].title) + " — " + sourceSheetLabel(articles[index])
                }
            }
            for index in indices { articles[index].title = proposed[index] ?? articles[index].title }
        }
    }

    private func titleQualifier(for article: ImportedArticle) -> String? {
        let base = normalizedTitle(article.title)
        let text = article.blocks
            .filter { [.heading, .paragraph, .specification, .note, .warning].contains($0.kind) }
            .map(\.text)
            .joined(separator: "\n")
        let candidates = titleSubjectCandidates(in: text)
        if let candidate = candidates.first(where: { normalizedTitle($0) != base }) { return candidate }
        let fallback = article.blocks
            .filter { [.heading, .paragraph, .specification].contains($0.kind) }
            .map(\.text)
            .map(cleanTitleFragment)
            .first { value in
                guard value.count >= 5, value.count <= 90, normalizedTitle(value) != base else { return false }
                return value.range(of: "^(?:[A-Z]|[0-9]|[A-Z0-9/−-]){1,3}(?:\\s|$)", options: .regularExpression) == nil
            }
        return fallback
    }

    private func titleSubjectCandidates(in text: String) -> [String] {
        let pattern = #"(?iu)\b(?:система|цепь|контур|блок|датчик|выключатель|переключатель|фара|фонарь|стеклоочиститель|обогреватель|генератор|стартер|компрессор|вентилятор|навигация|аудиосистема|круиз-контроль|замок|подушка безопасности)[ \t]+[\p{L}\p{N}/()−-]+(?:[ \t]+[\p{L}\p{N}/()−-]+){0,6}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            var value = cleanTitleFragment(String(text[range]))
            if let lineBreak = value.firstIndex(where: { $0.isNewline }) { value = String(value[..<lineBreak]) }
            guard value.count >= 5, value.count <= 90, seen.insert(normalizedTitle(value)).inserted else { return nil }
            return value
        }
    }

    private func cleanTitleFragment(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func applicabilityLabel(_ applicability: Applicability) -> String {
        var parts = applicability.bodyCodes
        if !applicability.years.isEmpty {
            let years = applicability.years.sorted()
            parts.append(years.count == 1 ? String(years[0]) : "\(years.first ?? 0)–\(years.last ?? 0)")
        }
        if !applicability.engineCodes.isEmpty { parts.append(applicability.engineCodes.joined(separator: "/")) }
        if !applicability.transmissions.isEmpty { parts.append(applicability.transmissions.joined(separator: "/")) }
        return parts.joined(separator: ", ")
    }

    private func sourceSheetLabel(_ article: ImportedArticle) -> String {
        let url = URL(fileURLWithPath: article.sourcePath)
        let name = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent().lastPathComponent
        return directory.lowercased() == "html" ? "лист \(name)" : "лист \(directory)/\(name)"
    }
    private func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private struct CatalogueEntry { let title: String; let breadcrumbs: [String]; let dgc: String? }
    private struct ContentCatalogue {
        var entries: [String: CatalogueEntry] = [:]
        var sectionNames: [String: String] = [:]
        var componentNames: [String: String] = [:]
        var systemNames: [String: String] = [:]
        subscript(key: String) -> CatalogueEntry? { entries[key] }
    }
    private func contentCatalogue(at root: URL) -> ContentCatalogue {
        let info = root.appendingPathComponent("ru/info")
        guard let contents = try? String(contentsOf: info.appendingPathComponent("contents_list.xml")), let sections = try? String(contentsOf: info.appendingPathComponent("sct_sc_name_list.xml")) else { return ContentCatalogue() }
        let systems = (try? String(contentsOf: info.appendingPathComponent("sys_name_list.xml"))) ?? ""
        var sectionNames: [String: String] = [:], componentNames: [String: String] = [:], systemNames: [String: String] = [:]
        let sectionPattern = "<sct_name\\s+code=\\\"([^\\\"]+)\\\"\\s+name=\\\"([^\\\"]+)\\\"[^>]*>(.*?)</sct_name>"
        for match in regexMatches(sectionPattern, in: sections) { sectionNames[match[1]] = xmlDecode(match[2]); for child in regexMatches("<sc_name\\s+code=\\\"([^\\\"]+)\\\"\\s+name=\\\"([^\\\"]+)\\\"", in: match[3]) { componentNames["\(match[1])/\(child[1])"] = xmlDecode(child[2]) } }
        for match in regexMatches("<sys_name\\s+code=\\\"([^\\\"]+)\\\"\\s+name=\\\"([^\\\"]+)\\\"", in: systems) {
            systemNames[match[1]] = xmlDecode(match[2])
        }
        var result: [String: CatalogueEntry] = [:]
        let pattern = "<contents\\s+key=\\\"([^\\\"]+)\\\"[^>]*title=\\\"([^\\\"]+)\\\"[^>]*>(.*?)</contents>"
        for match in regexMatches(pattern, in: contents) {
            let sct = regexMatches("<sct>([^<]+)</sct>", in: match[3]).first?.dropFirst().first ?? ""
            let sc = regexMatches("<sc>([^<]+)</sc>", in: match[3]).first?.dropFirst().first ?? ""
            let sys = regexMatches("<sys>([^<]+)</sys>", in: match[3]).first?.dropFirst().first ?? ""
            let comp = regexMatches("<comp>([^<]+)</comp>", in: match[3]).first?.dropFirst().first ?? ""
            let sitq = regexMatches("<sitq>([^<]+)</sitq>", in: match[3]).first?.dropFirst().first ?? ""
            let supp = regexMatches("<supp>([^<]+)</supp>", in: match[3]).first?.dropFirst().first ?? ""
            let breadcrumbs = originalNavigationBreadcrumbs(
                sct: sct,
                sc: sc,
                sys: sys,
                comp: comp,
                sitq: sitq,
                supp: supp,
                sectionNames: sectionNames,
                componentNames: componentNames,
                systemNames: systemNames
            )
            let parentTitle = xmlDecode(match[2])
            let dgc = regexMatches("<dgc>([^<]+)</dgc>", in: match[3]).first.flatMap { $0.count > 1 ? $0[1] : nil }
            result[match[1]] = CatalogueEntry(title: parentTitle, breadcrumbs: breadcrumbs, dgc: dgc)
            for child in regexMatches("<sub_contents\\s+key=\\\"([^\\\"]+)\\\"[^>]*title=\\\"([^\\\"]+)\\\"", in: match[3]) {
                result[child[1]] = CatalogueEntry(title: xmlDecode(child[2]), breadcrumbs: breadcrumbs + [parentTitle], dgc: dgc)
            }
        }
        return ContentCatalogue(entries: result, sectionNames: sectionNames, componentNames: componentNames, systemNames: systemNames)
    }

    private func breadcrumbsFromESMKey(
        _ rawKey: String,
        sectionNames: [String: String],
        componentNames: [String: String],
        systemNames: [String: String]
    ) -> [String]? {
        let compact = rawKey.replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression).uppercased()
        guard let range = compact.range(of: "[A-Z0-9]{7}[A-Z0-9][A-Z0-9]{3}[A-Z0-9]{3}[A-Z0-9]{5}[A-Z]{2}[A-Z0-9][A-Z0-9]{3}", options: .regularExpression) else { return nil }
        let key = String(compact[range])
        guard key.count >= 21 else { return nil }
        func slice(_ lower: Int, _ upper: Int) -> String {
            String(key[key.index(key.startIndex, offsetBy: lower)..<key.index(key.startIndex, offsetBy: upper)])
        }
        return originalNavigationBreadcrumbs(
            sct: slice(7, 8),
            sc: slice(8, 11),
            sys: slice(11, 14),
            comp: slice(14, 19),
            sitq: slice(19, 21),
            supp: key.count >= 25 ? slice(22, 25) : "",
            sectionNames: sectionNames,
            componentNames: componentNames,
            systemNames: systemNames
        )
    }

    /// Reproduces the categories and hierarchy declared by the legacy Honda ESM
    /// `SMT_*` (service manual) and `BRT_*` (body repair manual) navigation files.
    /// Values such as sct=0/sc=000/sys=000 are classifier placeholders and must
    /// never become visible section names.
    private func originalNavigationBreadcrumbs(
        sct: String,
        sc: String,
        sys: String,
        comp: String,
        sitq: String,
        supp: String,
        sectionNames: [String: String],
        componentNames: [String: String],
        systemNames: [String: String]
    ) -> [String] {
        if sct == "0" || sct.isEmpty {
            switch sitq {
            case "JB", "JC", "JD", "SA":
                return ["Руководство", "График техобслуживания", "Техобслуживание"]
            case "NA":
                return ["Руководство", "Спецификация", "Стандарты и сроки эксплуатации"]
            case "NB":
                return ["Руководство", "Спецификация", "Проектная спецификация"]
            case "NC":
                return ["Руководство", "Спецификация", "Габариты кузова"]
            case "EB", "ZD", "ZE":
                return ["Руководство", "Схемы электропроводки"]
            case "BA" where comp == "K0081" || supp == "T80":
                return ["Руководство", "График техобслуживания", "Жидкости и смазочные материалы"]
            default:
                return ["Руководство", "Общая информация"]
            }
        }

        if sct == "R" {
            let bodyRepairSections = [
                "111": "Общая информация",
                "211": "Информация о покраске",
                "311": "Замена",
                "411": "Иллюстрации, относящиеся к измерениям геометрии кузова",
                "511": "Предотвращение коррозии",
                "000": "Прочее"
            ]
            return ["Руководство", "Ремонт кузова"] + (bodyRepairSections[sc].map { [$0] } ?? [])
        }

        var classification: [String]
        if sct == "A", sc == "203" {
            classification = ["Топливо и система снижения токсичности"]
        } else if sct == "K" {
            classification = ["Поиск неисправностей DTC"]
        } else if sct == "Y" {
            classification = ["Поиск неисправностей по признакам"]
        } else {
            classification = [sectionNames[sct] ?? "Общая информация"]
        }

        if !(sct == "A" && sc == "203"), sc != "000", !sc.isEmpty,
           let name = componentNames["\(sct)/\(sc)"], !isClassifierPlaceholder(name) {
            classification.append(name)
        } else if sct == "K", let name = componentNames["\(sct)/\(sc)"], !isClassifierPlaceholder(name) {
            classification.append(name)
        }
        if sys != "000", !sys.isEmpty, let name = systemNames[sys], !isClassifierPlaceholder(name) {
            classification.append(name)
        }

        if sitq == "NA" {
            return ["Руководство", "Спецификация", "Стандарты и сроки эксплуатации"] + classification
        }
        if sitq == "NB" { return ["Руководство", "Спецификация", "Проектная спецификация"] + classification }
        if sitq == "NC" { return ["Руководство", "Спецификация", "Габариты кузова"] + classification }
        return ["Руководство"] + classification
    }

    private func isClassifierPlaceholder(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["не применимо", "not applicable", "na", "не используется"].contains(normalized)
    }
    private func regexMatches(_ pattern: String, in value: String) -> [[String]] { guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }; return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in (0..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: value).map { String(value[$0]) } } } }
    private func xmlDecode(_ value: String) -> String {
        var result = value
        for _ in 0..<4 {
            let decoded = decodeNumericEntities(in: result
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&#160;", with: " ")
                .replacingOccurrences(of: "&nbsp;", with: " "))
            if decoded == result { break }
            result = decoded
        }
        return result
    }
    private func decodeNumericEntities(in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(?:x([0-9A-Fa-f]+)|([0-9]+));") else { return value }
        var result = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let hex = match.range(at: 1).location != NSNotFound ? Range(match.range(at: 1), in: value).map { String(value[$0]) } : nil
            let decimal = match.range(at: 2).location != NSNotFound ? Range(match.range(at: 2), in: value).map { String(value[$0]) } : nil
            let scalar = hex.flatMap { UInt32($0, radix: 16) }.flatMap(UnicodeScalar.init) ?? decimal.flatMap { UInt32($0) }.flatMap(UnicodeScalar.init)
            if let scalar { result.replaceSubrange(range, with: String(Character(scalar))) }
        }
        return result
    }
    private func modelApplicabilityByDGC(at root: URL) -> [String: Applicability] {
        guard let xml = try? String(contentsOf: root.appendingPathComponent("ru/info/model_list.xml"), encoding: .utf8) else { return [:] }
        var yearsByDGC: [String: Set<Int>] = [:]
        var bodiesByDGC: [String: Set<String>] = [:]
        for model in regexMatches("<model\\b([^>]*)>(.*?)</model>", in: xml) {
            guard model.count > 2 else { continue }
            let attributes = model[1]
            let body = regexMatches("model_code=\\\"([^\\\"]+)\\\"", in: attributes).first.flatMap { $0.count > 1 ? $0[1] : nil }
            let year = regexMatches("model_year=\\\"([^\\\"]+)\\\"", in: attributes).first?.dropFirst().first.flatMap { Int($0) }
            for dgcMatch in regexMatches("<dgc\\s+code=\\\"([^\\\"]+)\\\"", in: model[2]) where dgcMatch.count > 1 {
                let dgc = dgcMatch[1]
                if let body { bodiesByDGC[dgc, default: []].insert(body) }
                if let year { yearsByDGC[dgc, default: []].insert(year) }
            }
        }
        return Dictionary(uniqueKeysWithValues: Set(yearsByDGC.keys).union(bodiesByDGC.keys).map { dgc in
            (dgc, Applicability(years: Array(yearsByDGC[dgc] ?? []).sorted(), bodyCodes: Array(bodiesByDGC[dgc] ?? []).sorted()))
        })
    }
    private func applicability(for path: String, text: String, catalogueDGC: String?, modelApplicability: [String: Applicability]) -> Applicability {
        let upper = (path + " " + text).uppercased()
        let directBodies = ["CL7", "CL9", "CM1", "CM2", "CN1", "CN2"].filter { upper.contains($0) }
        let directYears = (2003...2008).filter { upper.contains(String($0)) }
        let mapped = catalogueDGC.flatMap { modelApplicability[$0] }
        let engines = matches(/\b(?:K20A6|K20Z2|K24A3|N22A1|K20A|K24A|N22A)\b/, in: upper)
        let transmissions: [String] = [
            upper.range(of: "АКП|AUTOMATIC|AT\\b", options: [.regularExpression]) != nil ? "AT" : nil,
            upper.range(of: "МКП|MANUAL|MT\\b", options: [.regularExpression]) != nil ? "MT" : nil
        ].compactMap { $0 }
        return Applicability(
            years: Array(Set(directYears).union(mapped?.years ?? [])).sorted(),
            bodyCodes: Array(Set(directBodies).union(mapped?.bodyCodes ?? [])).sorted(),
            engineCodes: Array(Set(engines)).sorted(),
            transmissions: Array(Set(transmissions)).sorted()
        )
    }
    private func buildSections(from articles: [ImportedArticle]) -> [ImportedSection] { var seen = Set<String>(); var result: [ImportedSection] = []; for article in articles { for index in article.breadcrumbs.indices { let path = Array(article.breadcrumbs.prefix(index + 1)); let id = path.joined(separator: "/"); if seen.insert(id).inserted { result.append(ImportedSection(id: id, title: path.last ?? "Руководство", parentID: index == 0 ? nil : Array(path.dropLast()).joined(separator: "/"), sortOrder: result.count, breadcrumbPath: path, applicability: article.applicability)) } } }; return result }
    private func searchDocument(for article: ImportedArticle) -> SearchDocument { let combined = article.title + " " + article.plainText + " " + (article.esmKey ?? ""); return SearchDocument(articleID: article.id, normalizedTitle: article.title.lowercased(), normalizedText: article.plainText.lowercased(), tags: SearchTokenizer.tokens(in: combined), dtcCodes: matches(/\b[PCBU][0-9]{4}\b/, in: combined), engineCodes: matches(/\b[KJ][0-9]{2}[A-Z0-9]*\b/, in: combined)) }
    private func matches(_ expression: Regex<Substring>, in text: String) -> [String] { text.matches(of: expression).map { String($0.output) } }
    private func projectTitle(at root: URL) -> String? { let candidate = root.appendingPathComponent("ru/info/project.xml"); guard let text = try? String(contentsOf: candidate), let range = text.range(of: "title=\\\"([^\\\"]+)\\\"", options: .regularExpression) else { return nil }; return String(text[range]).split(separator: "\"").dropFirst().first.map(String.init) }
    private func copyMediaFile(_ relative: String, root: URL, output: URL, diagnostics: inout [ImportDiagnostic]) { let source = root.appendingPathComponent(relative).standardizedFileURL; guard source.path.hasPrefix(root.path + "/") else { diagnostics.append(.init(severity: "warning", path: relative, message: "Rejected path outside source root")); return }; let target = output.appendingPathComponent("media/").appendingPathComponent(relative); do { try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); if FileManager.default.fileExists(atPath: source.path) { try? FileManager.default.removeItem(at: target); try FileManager.default.copyItem(at: source, to: target) } else { diagnostics.append(.init(severity: "warning", path: relative, message: "Missing image")) } } catch { diagnostics.append(.init(severity: "warning", path: relative, message: "Could not copy image: \(error.localizedDescription)")) } }
    private func write<T: Encodable>(_ value: T, name: String, to output: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(value).write(to: output.appendingPathComponent(name), options: .atomic) }

    private func writeSQLite(package: ManualPackage, metadata: ImportMetadata, diagnostics: [ImportDiagnostic], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw sqliteError(database, operation: "open") }
        defer { sqlite3_close(database) }
        try execute(database, "PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; BEGIN IMMEDIATE;")
        do {
            try execute(database, """
            CREATE TABLE sections (id TEXT PRIMARY KEY, parent_id TEXT, sort_order INTEGER, title TEXT, json BLOB NOT NULL);
            CREATE TABLE articles (id TEXT PRIMARY KEY, source_path TEXT UNIQUE NOT NULL, section_id TEXT, title TEXT NOT NULL, esm_key TEXT, plain_text TEXT, has_images INTEGER NOT NULL, is_service INTEGER NOT NULL, applicability BLOB NOT NULL, article_json BLOB NOT NULL);
            CREATE INDEX articles_section_idx ON articles(section_id);
            CREATE INDEX articles_source_idx ON articles(source_path);
            CREATE VIRTUAL TABLE article_fts USING fts5(article_id UNINDEXED, title, body, tags, tokenize='unicode61 remove_diacritics 2');
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value BLOB NOT NULL);
            """)
            let encoder = JSONEncoder()
            for section in package.sections {
                try insert(database, sql: "INSERT INTO sections VALUES (?,?,?,?,?)", values: [.text(section.id), section.parentID.map(SQLiteValue.text) ?? .null, .integer(section.sortOrder), .text(section.title), .blob(try encoder.encode(section))])
            }
            for article in package.articles {
                let applicationData = try encoder.encode(article.applicability)
                let articleData = try encoder.encode(article)
                let isService = isTechnicalPresentation(article.sourcePath)
                try insert(database, sql: "INSERT INTO articles VALUES (?,?,?,?,?,?,?,?,?,?)", values: [
                    .text(article.id), .text(article.sourcePath), .text(article.breadcrumbs.joined(separator: "/")), .text(article.title), article.esmKey.map(SQLiteValue.text) ?? .null,
                    .text(article.plainText), .integer(article.images.isEmpty ? 0 : 1), .integer(isService ? 1 : 0), .blob(applicationData), .blob(articleData)
                ])
                if !isService {
                    let tags = SearchTokenizer.tokens(in: article.title + " " + article.breadcrumbs.joined(separator: " ") + " " + article.plainText + " " + (article.esmKey ?? "")).joined(separator: " ")
                    try insert(database, sql: "INSERT INTO article_fts VALUES (?,?,?,?)", values: [.text(article.id), .text(article.title), .text(article.plainText + " " + (article.esmKey ?? "")), .text(tags)])
                }
            }
            try insert(database, sql: "INSERT INTO metadata VALUES (?,?)", values: [.text("metadata"), .blob(try encoder.encode(metadata))])
            try insert(database, sql: "INSERT INTO metadata VALUES (?,?)", values: [.text("diagnostics"), .blob(try encoder.encode(diagnostics))])
            try execute(database, "COMMIT;")
        } catch {
            try? execute(database, "ROLLBACK;")
            throw error
        }
    }

    private enum SQLiteValue { case text(String), integer(Int), blob(Data), null }
    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw sqliteError(database, operation: sql) }
    }
    private func insert(_ database: OpaquePointer, sql: String, values: [SQLiteValue]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw sqliteError(database, operation: sql) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let position = Int32(offset + 1)
            switch value {
            case .text(let value): sqlite3_bind_text(statement, position, value, -1, transient)
            case .integer(let value): sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32(data.count), transient) }
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError(database, operation: sql) }
    }
    private func sqliteError(_ database: OpaquePointer?, operation: String) -> Error {
        let message = database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "Unknown SQLite error"
        return NSError(domain: "ManualImporter.SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(operation): \(message)"])
    }
}

extension HTMLArticleParser {
    static func parseTitle(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<title[^>]*>(.*?)</title>"), let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range]).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
    }
}
