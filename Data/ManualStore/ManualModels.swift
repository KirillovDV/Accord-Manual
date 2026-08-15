import Foundation

struct ManualPackage: Codable, Sendable { let sections: [ManualSection]; let articles: [ManualArticle] }
struct ManualSection: Codable, Identifiable, Hashable, Sendable { let id: String; let title: String; let parentID: String?; let sortOrder: Int; let breadcrumbPath: [String]; let applicability: Applicability }
struct ManualArticle: Codable, Identifiable, Hashable, Sendable {
    let id: String; let esmKey: String?; let title: String; let breadcrumbs: [String]; let sourcePath: String; let blocks: [ArticleBlock]; let plainText: String; let links: [String]; let images: [ManualImage]; let applicability: Applicability; let relatedArticleIDs: [String]
    var sectionID: String { breadcrumbs.joined(separator: "/") }
}
struct ArticleBlock: Codable, Hashable, Sendable, Identifiable {
    let id: String; let kind: BlockKind; let text: String; let items: [String]; let rows: [[String]]; let tableRows: [[ManualTableCell]]; let target: String?; let anchor: String?; let steps: [ProcedureStep]
    init(id: String = UUID().uuidString, kind: BlockKind, text: String = "", items: [String] = [], rows: [[String]] = [], tableRows: [[ManualTableCell]] = [], target: String? = nil, anchor: String? = nil, steps: [ProcedureStep] = []) { self.id = id; self.kind = kind; self.text = text; self.items = items; self.rows = rows; self.tableRows = tableRows; self.target = target; self.anchor = anchor; self.steps = steps }
    private enum CodingKeys: String, CodingKey { case id, kind, text, items, rows, tableRows, target, anchor, steps }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decode(BlockKind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
        rows = try container.decodeIfPresent([[String]].self, forKey: .rows) ?? []
        tableRows = try container.decodeIfPresent([[ManualTableCell]].self, forKey: .tableRows) ?? rows.map { $0.map { ManualTableCell(text: $0) } }
        target = try container.decodeIfPresent(String.self, forKey: .target)
        anchor = try container.decodeIfPresent(String.self, forKey: .anchor)
        steps = try container.decodeIfPresent([ProcedureStep].self, forKey: .steps) ?? []
    }
    enum BlockKind: String, Codable, Sendable { case heading, paragraph, numberedSteps, bulletList, warning, note, table, image, link, anchor, specification }
}
struct ProcedureStep: Codable, Hashable, Sendable, Identifiable {
    let id: String; let number: Int; let text: String; let substeps: [String]; let anchors: [String]; let supportingBlocks: [ArticleBlock]
    init(id: String, number: Int, text: String, substeps: [String] = [], anchors: [String] = [], supportingBlocks: [ArticleBlock] = []) { self.id = id; self.number = number; self.text = text; self.substeps = substeps; self.anchors = anchors; self.supportingBlocks = supportingBlocks }
    private enum CodingKeys: String, CodingKey { case id, number, text, substeps, anchors, supportingBlocks }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); number = try c.decode(Int.self, forKey: .number); text = try c.decode(String.self, forKey: .text); substeps = try c.decodeIfPresent([String].self, forKey: .substeps) ?? []; anchors = try c.decodeIfPresent([String].self, forKey: .anchors) ?? []; supportingBlocks = try c.decodeIfPresent([ArticleBlock].self, forKey: .supportingBlocks) ?? [] }
}
struct ManualTableCell: Codable, Hashable, Sendable {
    let text: String
    let isHeader: Bool
    let rowSpan: Int
    let columnSpan: Int
    init(text: String, isHeader: Bool = false, rowSpan: Int = 1, columnSpan: Int = 1) { self.text = text; self.isHeader = isHeader; self.rowSpan = max(1, rowSpan); self.columnSpan = max(1, columnSpan) }
}
struct ImageAnnotationLink: Codable, Hashable, Sendable, Identifiable {
    let text: String
    let target: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let lineIndex: Int
    var id: String { "\(target):\(text):\(x):\(y)" }
    private enum CodingKeys: String, CodingKey { case text, target, x, y, width, height, lineIndex }
    init(text: String, target: String, x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0, lineIndex: Int = 0) { self.text = text; self.target = target; self.x = x; self.y = y; self.width = width; self.height = height; self.lineIndex = lineIndex }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); text = try c.decode(String.self, forKey: .text); target = try c.decode(String.self, forKey: .target); x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0; y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0; width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0; height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0; lineIndex = try c.decodeIfPresent(Int.self, forKey: .lineIndex) ?? 0 }
}
struct ImageAnnotation: Codable, Hashable, Sendable, Identifiable {
    let id: String; let text: String; let x: Double; let y: Double; let width: Double?; let height: Double?; let fontSize: Double?; let lines: [String]; let links: [ImageAnnotationLink]
    private enum CodingKeys: String, CodingKey { case id, text, x, y, width, height, fontSize, lines, links }
    init(id: String, text: String, x: Double, y: Double, width: Double? = nil, height: Double? = nil, fontSize: Double? = nil, lines: [String] = [], links: [ImageAnnotationLink] = []) { self.id = id; self.text = text; self.x = x; self.y = y; self.width = width; self.height = height; self.fontSize = fontSize; self.lines = lines; self.links = links }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); text = try c.decode(String.self, forKey: .text); x = try c.decode(Double.self, forKey: .x); y = try c.decode(Double.self, forKey: .y); width = try c.decodeIfPresent(Double.self, forKey: .width); height = try c.decodeIfPresent(Double.self, forKey: .height); fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize); lines = try c.decodeIfPresent([String].self, forKey: .lines) ?? []; links = try c.decodeIfPresent([ImageAnnotationLink].self, forKey: .links) ?? [] }
}
struct ManualImage: Codable, Hashable, Sendable, Identifiable {
    let id: String; let localRelativePath: String; let caption: String?; let altText: String?; let width: Int?; let height: Int?; let articleID: String; let canvasWidth: Double?; let canvasHeight: Double?; let annotations: [ImageAnnotation]
    private enum CodingKeys: String, CodingKey { case id, localRelativePath, caption, altText, width, height, articleID, canvasWidth, canvasHeight, annotations }
    init(id: String, localRelativePath: String, caption: String?, altText: String?, width: Int?, height: Int?, articleID: String, canvasWidth: Double? = nil, canvasHeight: Double? = nil, annotations: [ImageAnnotation] = []) { self.id = id; self.localRelativePath = localRelativePath; self.caption = caption; self.altText = altText; self.width = width; self.height = height; self.articleID = articleID; self.canvasWidth = canvasWidth; self.canvasHeight = canvasHeight; self.annotations = annotations }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); localRelativePath = try c.decode(String.self, forKey: .localRelativePath); caption = try c.decodeIfPresent(String.self, forKey: .caption); altText = try c.decodeIfPresent(String.self, forKey: .altText); width = try c.decodeIfPresent(Int.self, forKey: .width); height = try c.decodeIfPresent(Int.self, forKey: .height); articleID = try c.decode(String.self, forKey: .articleID); canvasWidth = try c.decodeIfPresent(Double.self, forKey: .canvasWidth); canvasHeight = try c.decodeIfPresent(Double.self, forKey: .canvasHeight); annotations = try c.decodeIfPresent([ImageAnnotation].self, forKey: .annotations) ?? [] }
}
struct Applicability: Codable, Hashable, Sendable { let years: [Int]; let bodyCodes: [String]; let engineCodes: [String]; let transmissions: [String] }
struct SearchDocument: Codable, Sendable { let articleID: String; let normalizedTitle: String; let normalizedText: String; let tags: [String]; let dtcCodes: [String]; let engineCodes: [String] }
struct ManualMetadata: Codable, Sendable { let formatVersion: Int; let importedAt: String; let sourceTitle: String?; let pageCount: Int; let imageCount: Int; let sectionCount: Int; let indexedTokenCount: Int }
struct ImportDiagnostic: Codable, Sendable, Identifiable { let severity: String; let path: String; let message: String; var id: String { "\(severity):\(path):\(message)" } }
struct LocalDiagnosticReport: Sendable {
    let generatedAt: Date
    let packageStatus: String
    let packageSize: Int64?
    let metadata: ManualMetadata?
    let catalogueArticleCount: Int
    let sectionCount: Int
    let mediaFileCount: Int
    let diagnostics: [ImportDiagnostic]
    let runtimeIssues: [String]

    var formattedText: String {
        var lines = [
            "Локальная диагностика Accord Manual",
            "Создано: \(ISO8601DateFormatter().string(from: generatedAt))",
            "",
            "Состояние пакета: \(packageStatus)",
            "Статей в каталоге: \(Self.number(catalogueArticleCount))",
            "Разделов: \(Self.number(sectionCount))",
            "Файлов медиа: \(Self.number(mediaFileCount))"
        ]
        if let packageSize { lines.append("Размер SQLite: \(ByteCountFormatter.string(fromByteCount: packageSize, countStyle: .file))") }
        if let metadata {
            lines += [
                "",
                "Импортированный пакет",
                "Версия формата: \(metadata.formatVersion)",
                "Дата импорта: \(metadata.importedAt)",
                "Страниц: \(Self.number(metadata.pageCount))",
                "Изображений: \(Self.number(metadata.imageCount))",
                "Токенов поискового индекса: \(Self.number(metadata.indexedTokenCount))"
            ]
        }
        if !runtimeIssues.isEmpty { lines += ["", "Проблемы текущей проверки"] + runtimeIssues.map { "• \($0)" } }
        let grouped = Dictionary(grouping: diagnostics, by: \.severity)
        lines += ["", "Сообщения импортёра: \(Self.number(diagnostics.count))"]
        for severity in grouped.keys.sorted() { lines.append("• \(severity): \(Self.number(grouped[severity]?.count ?? 0))") }
        if !diagnostics.isEmpty {
            lines += ["", "Детали сообщений импортёра"]
            lines += diagnostics.prefix(500).map { "[\($0.severity)] \($0.path): \($0.message)" }
            if diagnostics.count > 500 { lines.append("Показаны первые 500 из \(Self.number(diagnostics.count)) сообщений.") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{00A0}"
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
struct SearchResult: Identifiable, Sendable { let article: ManualArticle; let group: SearchGroup; let excerpt: String; let matchedText: String?; var id: String { article.id }; enum SearchGroup: String, CaseIterable, Sendable { case titles = "Заголовки", diagnostic = "Диагностика / DTC", specifications = "Характеристики", articles = "Статьи", text = "В тексте" } }
struct SearchFilters: Sendable, Equatable { var sectionID: String?; var year: Int?; var bodyCode: String?; var engineCode: String?; var transmission: String?; var manualType: String?; var imagesOnly = false; var savedOnly = false }
