import Foundation

/// Internal parser marker. It is replaced by the stable block identifier before
/// the imported article is written, so it never becomes reader-facing data.
private let layoutCompanionImageMarker = "__layout-companion-image__"
private let tableCellContentMarkerPrefix = "__table-cell-content-"

public enum ArticleBlockKind: String, Codable, Sendable {
    case heading, paragraph, numberedSteps, bulletList, warning, note, table, image, link, anchor, specification
}

public struct ImportedTableCell: Codable, Equatable, Sendable {
    public var text: String
    public var isHeader: Bool
    public var rowSpan: Int
    public var columnSpan: Int

    public init(text: String, isHeader: Bool = false, rowSpan: Int = 1, columnSpan: Int = 1) {
        self.text = text
        self.isHeader = isHeader
        self.rowSpan = max(1, rowSpan)
        self.columnSpan = max(1, columnSpan)
    }
}

/// A text link retained inside a paragraph. Legacy ESM decision trees commonly
/// put a link in the middle of a sentence, where representing it as a separate
/// block would change both its reading order and meaning.
public struct ImportedInlineLink: Codable, Equatable, Sendable {
    public var text: String
    public var target: String

    public init(text: String, target: String) {
        self.text = text
        self.target = target
    }
}

public struct ImportedImageAnnotationLink: Codable, Equatable, Sendable {
    public var text: String
    public var target: String
    /// Position in the source VML canvas. These values deliberately stay in
    /// source pixels so a reader can transform the hit area with the diagram.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var lineIndex: Int

    public init(text: String, target: String, x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0, lineIndex: Int = 0) {
        self.text = text
        self.target = target
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.lineIndex = lineIndex
    }
}

public struct ImportedImageAnnotation: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double?
    public var height: Double?
    public var fontSize: Double?
    /// Lines are retained exactly as the original positioned markup breaks
    /// them, rather than being reflowed by the reader.
    public var lines: [String]
    public var links: [ImportedImageAnnotationLink]

    public init(id: String, text: String, x: Double, y: Double, width: Double? = nil, height: Double? = nil, fontSize: Double? = nil, lines: [String] = [], links: [ImportedImageAnnotationLink] = []) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fontSize = fontSize
        self.lines = lines
        self.links = links
    }
}

public struct ImportedBlock: Codable, Equatable, Sendable {
    public var id: String
    public var kind: ArticleBlockKind
    public var text: String
    public var items: [String]
    public var rows: [[String]]
    public var tableRows: [[ImportedTableCell]]
    public var target: String?
    public var anchor: String?
    public var steps: [ImportedProcedureStep]
    public var inlineLinks: [ImportedInlineLink]

    public init(id: String = "", kind: ArticleBlockKind, text: String = "", items: [String] = [], rows: [[String]] = [], tableRows: [[ImportedTableCell]] = [], target: String? = nil, anchor: String? = nil, steps: [ImportedProcedureStep] = [], inlineLinks: [ImportedInlineLink] = []) {
        self.id = id; self.kind = kind; self.text = text; self.items = items; self.rows = rows; self.tableRows = tableRows; self.target = target; self.anchor = anchor; self.steps = steps; self.inlineLinks = inlineLinks
    }
}

public struct ImportedProcedureStep: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var text: String
    public var substeps: [String]
    public var anchors: [String]
    public var supportingBlocks: [ImportedBlock]

    public init(id: String, number: Int, text: String, substeps: [String] = [], anchors: [String] = [], supportingBlocks: [ImportedBlock] = []) {
        self.id = id
        self.number = number
        self.text = text
        self.substeps = substeps
        self.anchors = anchors
        self.supportingBlocks = supportingBlocks
    }
}

public struct ImportedImage: Codable, Equatable, Sendable {
    public var id: String
    public var localRelativePath: String
    public var caption: String?
    public var altText: String?
    public var width: Int?
    public var height: Int?
    public var articleID: String
    public var canvasWidth: Double?
    public var canvasHeight: Double?
    public var annotations: [ImportedImageAnnotation]
}

public struct Applicability: Codable, Equatable, Sendable {
    public var years: [Int]
    public var bodyCodes: [String]
    public var engineCodes: [String]
    public var transmissions: [String]
    public init(years: [Int] = [], bodyCodes: [String] = [], engineCodes: [String] = [], transmissions: [String] = []) {
        self.years = years; self.bodyCodes = bodyCodes; self.engineCodes = engineCodes; self.transmissions = transmissions
    }
}

public struct ImportedArticle: Codable, Equatable, Sendable {
    public var id: String
    public var esmKey: String?
    public var title: String
    public var breadcrumbs: [String]
    public var sourcePath: String
    public var blocks: [ImportedBlock]
    public var plainText: String
    public var links: [String]
    public var images: [ImportedImage]
    public var applicability: Applicability
    public var relatedArticleIDs: [String]
    public init(id: String, title: String, breadcrumbs: [String], sourcePath: String, blocks: [ImportedBlock], plainText: String, links: [String], images: [ImportedImage], esmKey: String?, applicability: Applicability = .init(), relatedArticleIDs: [String] = []) {
        self.id = id; self.title = title; self.breadcrumbs = breadcrumbs; self.sourcePath = sourcePath; self.blocks = blocks; self.plainText = plainText; self.links = links; self.images = images; self.esmKey = esmKey; self.applicability = applicability; self.relatedArticleIDs = relatedArticleIDs
    }
}

public struct ImportedSection: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var parentID: String?
    public var sortOrder: Int
    public var breadcrumbPath: [String]
    public var applicability: Applicability
}

public struct SectionNode: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var children: [SectionNode]
    public init(id: String, title: String, children: [SectionNode] = []) { self.id = id; self.title = title; self.children = children }
}

public enum LinkNormalizer {
    /// Resolves normal local URLs as well as the navigation JavaScript emitted by Honda ESM.
    /// The returned value retains an optional anchor so the native reader can scroll to it.
    public static func target(_ link: String, from sourcePath: String) -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("mailto:") else { return nil }

        if let legacyTarget = legacyTarget(in: trimmed, from: sourcePath) { return legacyTarget }
        guard !trimmed.lowercased().hasPrefix("javascript:") else { return nil }

        let pieces = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(pieces[0])
        let anchor = pieces.count == 2 ? String(pieces[1]) : nil
        if pathPart.isEmpty {
            return anchor.map { sourcePath + "#" + $0 }
        }
        guard !pathPart.contains("://"), !pathPart.hasPrefix("/") else { return nil }
        var components = sourcePath.split(separator: "/").dropLast().map(String.init)
        for component in pathPart.split(separator: "/") {
            if component == "." || component.isEmpty { continue }
            if component == ".." { guard !components.isEmpty else { return nil }; components.removeLast() }
            else { components.append(String(component)) }
        }
        let path = components.joined(separator: "/")
        return anchor.map { path + "#" + $0 } ?? path
    }

    public static func normalized(_ link: String, from sourcePath: String) -> String? {
        guard let target = target(link, from: sourcePath) else { return nil }
        return target.split(separator: "#", maxSplits: 1).first.map(String.init)
    }

    private static func legacyTarget(in link: String, from sourcePath: String) -> String? {
        // CtsProc opens an ordinary ESM HTML page; PrtProc opens the matching zoom page.
        let cts = #"(?i)(?:CtsProc|PrtProc)\s*\(\s*['\"][^'\"]+['\"]\s*,\s*['\"]([^'\"]+)['\"](?:\s*,\s*['\"]([^'\"]+)['\"])?"#
        if let values = captures(cts, in: link), let key = values.first, !key.isEmpty {
            let anchor = values.dropFirst().first ?? ""
            return "ru/html/\(key).html" + (anchor.isEmpty ? "" : "#\(anchor)")
        }
        // The regular article viewer uses parent.Jmp('i040') for an in-page
        // diagnostic step. Unlike CtsProc it carries no page key.
        let inPageJump = #"(?i)(?:parent\s*\.\s*)?Jmp\s*\(\s*['\"]([^'\"]+)['\"]"#
        if let anchor = captures(inPageJump, in: link)?.first,
           !anchor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourcePath + "#" + anchor
        }
        // A zoom page's in-page links are represented by JumpFunc('page.html#anchor').
        let jump = #"(?i)JumpFunc\s*\(\s*['\"]([^'\"]+)['\"]"#
        if let value = captures(jump, in: link)?.first, !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".html") {
            return target(value, from: sourcePath)
        }
        return nil
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

public enum SearchTokenizer {
    public static func tokens(in text: String) -> [String] {
        let lowered = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")).lowercased()
        let pieces = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Array(Set(pieces.filter { $0.count > 1 })).sorted()
    }
}

public enum SectionTreeBuilder {
    public static func build(from articles: [ImportedArticle]) -> [SectionNode] {
        var roots: [SectionNode] = []
        for article in articles {
            let path = article.breadcrumbs.isEmpty ? ["Руководство"] : article.breadcrumbs
            insert(path: path, into: &roots)
        }
        return roots
    }
    private static func insert(path: [String], into nodes: inout [SectionNode]) {
        guard let first = path.first else { return }
        let id = path.joined(separator: "/")
        if let index = nodes.firstIndex(where: { $0.title == first }) {
            if path.count > 1 { insert(path: Array(path.dropFirst()), into: &nodes[index].children) }
        } else {
            var node = SectionNode(id: id, title: first)
            if path.count > 1 { insert(path: Array(path.dropFirst()), into: &node.children) }
            nodes.append(node)
        }
    }
}

public enum HTMLArticleParser {
    public static func parse(html: String, id: String, title: String, breadcrumbs: [String], sourcePath: String, imagePathResolver: @escaping @Sendable (String) -> String = { $0 }) throws -> ImportedArticle {
        var tokenizer = OrderedHTMLTokenizer(articleID: id, sourcePath: sourcePath, imagePathResolver: imagePathResolver)
        // Inline legacy JavaScript frequently contains raw comparison operators such as
        // `x < width`. It is not article content and can look like malformed HTML to a
        // tokenizer. External image scripts have already been expanded by the importer.
        let semanticHTML = html.replacingOccurrences(
            of: "(?is)<script\\b[^>]*>.*?</script>|<style\\b[^>]*>.*?</style>",
            with: " ",
            options: .regularExpression
        )
        tokenizer.consume(semanticHTML)
        var blocks = mergeProcedures(tokenizer.blocks)
        blocks = blocks.enumerated().map { index, block in
            var identified = block
            identified.id = "\(id)-block-\(index)"
            return identified
        }
        let allText = tokenizer.plainText
        let resolvedTitle = title.isEmpty ? (blocks.first(where: { $0.kind == ArticleBlockKind.heading })?.text ?? filenameTitle(sourcePath)) : title
        if blocks.isEmpty, !allText.isEmpty { blocks = [ImportedBlock(kind: .paragraph, text: allText)] }
        return ImportedArticle(id: id, title: resolvedTitle, breadcrumbs: breadcrumbs, sourcePath: sourcePath, blocks: blocks, plainText: allText, links: Array(Set(tokenizer.links)).sorted(), images: tokenizer.images, esmKey: esmKey(from: html) ?? esmKey(from: sourcePath))
    }

    private static func mergeProcedures(_ source: [ImportedBlock]) -> [ImportedBlock] {
        var result: [ImportedBlock] = []
        var active: ImportedBlock?
        var pendingAnchors: [String] = []

        func flushActive() {
            guard let current = active else { return }
            result.append(current)
            active = nil
        }
        func flushPendingAnchors() {
            result.append(contentsOf: pendingAnchors.map { ImportedBlock(kind: .anchor, text: $0, anchor: $0) })
            pendingAnchors = []
        }
        func flush() {
            flushActive()
            flushPendingAnchors()
        }

        for block in source {
            switch block.kind {
            case .anchor:
                if let anchor = block.anchor {
                    pendingAnchors.append(anchor)
                }
            case .numberedSteps:
                let incoming = block.steps.isEmpty ? fallbackSteps(from: block) : block.steps
                guard !incoming.isEmpty else { flush(); result.append(block); continue }
                if var current = active,
                   let last = current.steps.last,
                   incoming.first?.number == last.number + 1 {
                    var appended = incoming
                    if !pendingAnchors.isEmpty { appended[0].anchors.append(contentsOf: pendingAnchors) }
                    current.steps.append(contentsOf: appended)
                    current.items = current.steps.map(\.text)
                    active = current
                    pendingAnchors = []
                } else {
                    let anchors = pendingAnchors
                    pendingAnchors = []
                    flushActive()
                    var first = block
                    var steps = incoming
                    if !anchors.isEmpty { steps[0].anchors.append(contentsOf: anchors) }
                    first.steps = steps
                    first.items = steps.map(\.text)
                    active = first
                }
            case .image where block.id == layoutCompanionImageMarker:
                // Honda's legacy viewer puts illustrations in a `graphTd` next
                // to the complete `textTd` procedure. In the flattened DOM the
                // image arrives after all steps; it illustrates the procedure as
                // a whole, not its final step.
                flush()
                result.append(block)
            case .image, .note, .warning, .bulletList, .link, .table:
                if var current = active, !pendingAnchors.isEmpty == false, !current.steps.isEmpty {
                    current.steps[current.steps.count - 1].supportingBlocks.append(block)
                    active = current
                } else {
                    flush()
                    result.append(block)
                }
            default:
                flush()
                result.append(block)
            }
        }
        flush()
        return result
    }

    private static func fallbackSteps(from block: ImportedBlock) -> [ImportedProcedureStep] {
        block.items.enumerated().map { index, text in
            ImportedProcedureStep(id: "\(block.id)-step-\(index)", number: index + 1, text: text)
        }
    }
    private static func append(_ kind: ArticleBlockKind, text: String, to blocks: inout [ImportedBlock]) { if !text.isEmpty { blocks.append(ImportedBlock(kind: kind, text: text)) } }
    private static func explicitCallout(_ value: String, names: [String]) -> Bool {
        let namesPattern = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return value.range(of: "^\\s*(?:\(namesPattern))\\s*[:!—-]", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func appendNestedImages(in html: String, sourcePath: String, imagePathResolver: @Sendable (String) -> String, images: [ImportedImage], to blocks: inout [ImportedBlock]) {
        for tag in imageTags(in: html) {
            let attributes = attributesOfOpeningTag(tag)
            guard let source = attribute("src", in: attributes),
                  let target = LinkNormalizer.target(source, from: sourcePath),
                  let image = images.first(where: { $0.localRelativePath == imagePathResolver(target) }) else { continue }
            blocks.append(ImportedBlock(kind: .image, text: image.altText ?? "", target: image.localRelativePath))
        }
    }
    private static func appendNestedLinks(in html: String, sourcePath: String, links: inout [String], to blocks: inout [ImportedBlock]) {
        for fragment in linkTags(in: html) {
            let attributes = attributesOfOpeningTag(fragment)
            guard let href = attribute("href", in: attributes), let target = LinkNormalizer.target(href, from: sourcePath) else { continue }
            let label = text(from: fragment)
            let path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
            links.append(path)
            if !label.isEmpty { blocks.append(ImportedBlock(kind: .link, text: label, target: target)) }
        }
    }
    private static func openingTag(in html: String) -> String { html.firstMatch(of: /(?i)<\s*([a-z0-9]+)/).map { String($0.1) } ?? "" }
    private static func attributesOfOpeningTag(_ html: String) -> String { String(html.prefix { $0 != ">" }) }
    private static func innerHTML(_ html: String) -> String { guard let end = html.firstIndex(of: ">") else { return html }; return String(html[html.index(after: end)...]) }
    private static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(['\\\"])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)), let range = Range(match.range(at: 2), in: attributes) else { return nil }
        return decode(String(attributes[range]))
    }
    private static func listItems(in html: String) -> [String] { matches("(?is)<li[^>]*>(.*?)</li>", in: html).map(text(from:)).filter { !$0.isEmpty } }
    private static func imageTags(in html: String) -> [String] { guard let regex = try? NSRegularExpression(pattern: "(?is)<img\\b[^>]*>") else { return [] }; return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range, in: html).map { String(html[$0]) } } }
    private static func linkTags(in html: String) -> [String] { guard let regex = try? NSRegularExpression(pattern: "(?is)<a\\b[^>]*>.*?</a>") else { return [] }; return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range, in: html).map { String(html[$0]) } } }
    private static func tableRows(in html: String) -> [[String]] { matches("(?is)<tr[^>]*>(.*?)</tr>", in: html).map { matches("(?is)<t[hd][^>]*>(.*?)</t[hd]>", in: $0).map(text(from:)).filter { !$0.isEmpty } }.filter { !$0.isEmpty } }
    private static func matches(_ pattern: String, in value: String) -> [String] { guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }; return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { Range($0.range(at: 1), in: value).map { String(value[$0]) } } }
    private static func text(from html: String) -> String { decode(html.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>|<[^>]+>", with: " ", options: .regularExpression)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func decode(_ value: String) -> String {
        var result = value
        for _ in 0..<4 {
            let decoded = result.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            if decoded == result { break }
            result = decoded
        }
        return result
    }
    private static func esmKey(from value: String) -> String? { value.firstMatch(of: /SEA[A-Z0-9]{12,}/).map { String($0.0) } ?? value.firstMatch(of: /\b\d{15}\b/).map { String($0.0) } }
    private static func filenameTitle(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
}

private struct OrderedHTMLTokenizer {
    private struct ListEntry {
        let number: Int?
        let text: String
        let substeps: [String]
    }

    private struct Frame {
        var name: String
        var attributes: String
        var hidden: Bool
        var text = ""
        var childElementCount = 0
        var blockInsertionIndex: Int
        var listEntries: [ListEntry] = []
        var nestedListItems: [String] = []
        var tableRows: [[ImportedTableCell]] = []
        var rowCells: [ImportedTableCell] = []
        var isArticleLayoutTable = false
        /// True only for a table that will become a reader-facing structured
        /// table.  Layout tables are common in the legacy ESM and must keep
        /// their textual links as article blocks.
        var isSemanticDataTable = false
        var cellContentMarker: String?
        var canvasWidth: Double?
        var canvasHeight: Double?
        var hasHeaderCell = false
        var hasSpanningCell = false
        var annotationLinks: [ImportedImageAnnotationLink] = []
        var annotationLines: [String] = [""]
    }

    let articleID: String
    let sourcePath: String
    let imagePathResolver: @Sendable (String) -> String
    private(set) var blocks: [ImportedBlock] = []
    private(set) var links: [String] = []
    private(set) var images: [ImportedImage] = []
    private(set) var plainText = ""
    private var stack: [Frame] = []
    private var imagePaths = Set<String>()
    private var skipDepth = 0
    private var nextTableMarker = 0

    init(articleID: String, sourcePath: String, imagePathResolver: @escaping @Sendable (String) -> String) {
        self.articleID = articleID
        self.sourcePath = sourcePath
        self.imagePathResolver = imagePathResolver
    }

    mutating func consume(_ html: String) {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<!--.*?-->|<![^>]*>|<[^>]+>|[^<]+") else { return }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let token = String(html[range])
            if token.hasPrefix("<!--") || token.hasPrefix("<!") { continue }
            if token.hasPrefix("</") { close(tagName(token)); continue }
            if token.hasPrefix("<") { open(token); continue }
            addText(token)
        }
        while let frame = stack.last { close(frame.name) }
        // Cells of a non-structural layout table are ordinary article content.
        // Drop their temporary parser marker before block IDs are made stable.
        blocks = blocks.map { block in
            guard block.id.hasPrefix(tableCellContentMarkerPrefix) else { return block }
            var restored = block
            restored.id = ""
            return restored
        }
        plainText = normalizedWhitespace(plainText)
    }

    private mutating func open(_ token: String) {
        let name = tagName(token)
        guard !name.isEmpty else { return }
        let attributes = String(token.dropFirst(name.count + 1).dropLast())
        let parentHidden = stack.last?.hidden ?? false
        let style = attribute("style", in: attributes)?.lowercased() ?? ""
        let isDynamicArticleRoot = attribute("id", in: attributes)?.localizedCaseInsensitiveCompare("divBody") == .orderedSame
        let hidden = parentHidden || (!isDynamicArticleRoot && style.replacingOccurrences(of: " ", with: "").contains("display:none")) || attribute("aria-hidden", in: attributes)?.lowercased() == "true"
        if ["script", "style"].contains(name) { skipDepth += 1 }
        if !stack.isEmpty { stack[stack.count - 1].childElementCount += 1 }

        if name == "img" {
            if !hidden && skipDepth == 0 { addImage(attributes) }
            return
        }
        if name == "br" {
            addDiagramLineBreak()
            addText(" ")
            return
        }

        var frame = Frame(name: name, attributes: attributes, hidden: hidden, blockInsertionIndex: blocks.count)
        if name == "table" {
            frame.isSemanticDataTable = hasStructuralTableAttributes(attributes)
            frame.cellContentMarker = "\(tableCellContentMarkerPrefix)\(nextTableMarker)__"
            nextTableMarker += 1
        }
        if name == "v:group" || name == "group" {
            let coordinates = attribute("coordsize", in: attributes)?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            frame.canvasWidth = coordinates?.first ?? styleNumber("width", in: style)
            frame.canvasHeight = coordinates?.dropFirst().first ?? styleNumber("height", in: style)
        }
        if ["td", "th"].contains(name), attribute("id", in: attributes)?.localizedCaseInsensitiveCompare("textTd") == .orderedSame,
           let tableIndex = stack.lastIndex(where: { $0.name == "table" }) {
            stack[tableIndex].isArticleLayoutTable = true
        }
        if (name == "th" || (name == "td" && hasCellSpan(attributes))),
           let tableIndex = stack.lastIndex(where: { $0.name == "table" }) {
            stack[tableIndex].isSemanticDataTable = true
        }
        if name == "a", !hidden, skipDepth == 0, let anchor = attribute("name", in: attributes) ?? attribute("id", in: attributes), !anchor.isEmpty {
            blocks.append(ImportedBlock(kind: .anchor, text: anchor, anchor: anchor))
            frame.blockInsertionIndex = blocks.count
        }
        stack.append(frame)
        if token.hasSuffix("/>") { close(name) }
    }

    private mutating func close(_ requestedName: String) {
        guard let index = stack.lastIndex(where: { $0.name == requestedName }) else {
            if ["script", "style"].contains(requestedName), skipDepth > 0 { skipDepth -= 1 }
            return
        }
        // Legacy Honda scripts often close a formatting tag *after* opening an
        // anchor (`<b>title<a …></b>link</a>`).  HTML browsers keep the anchor
        // alive; do the same so the positioned label retains its link target.
        if index < stack.count - 1,
           ["b", "strong", "i", "em", "font"].contains(requestedName),
           stack[(index + 1)...].allSatisfy({ $0.name == "a" }) {
            let formatting = stack.remove(at: index)
            if index > 0, !formatting.text.isEmpty {
                stack[index - 1].text += " " + formatting.text
            }
            return
        }
        while stack.count > index + 1, let nested = stack.last { close(nested.name) }
        let frame = stack.removeLast()
        if ["script", "style"].contains(frame.name), skipDepth > 0 { skipDepth -= 1 }
        let value = normalizedWhitespace(frame.text)
        let childListOfItem = ["ol", "ul"].contains(frame.name) && stack.last?.name == "li"
        if !stack.isEmpty, !value.isEmpty, !childListOfItem { stack[stack.count - 1].text += " " + value }
        guard !frame.hidden, skipDepth == 0 else { return }

        switch frame.name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            if !isInsideSemanticTableCell() {
                insert(.init(kind: .heading, text: value), at: frame.blockInsertionIndex, unlessEmpty: value)
            }
        case "p":
            if isPositionedAnnotation(frame), attachAnnotation(text: value, frame: frame, links: frame.annotationLinks) {
                break
            } else if !isInsideSemanticTableCell(), !stack.contains(where: { $0.name == "li" }) {
                insert(classifiedTextBlock(value, attributes: frame.attributes), at: frame.blockInsertionIndex, unlessEmpty: value)
            }
        case "div":
            let className = attribute("class", in: frame.attributes)?.lowercased() ?? ""
            if className.contains("top_title") || className.contains("topic_title") {
                insert(.init(kind: .heading, text: value), at: frame.blockInsertionIndex, unlessEmpty: value)
            } else if !isInsideSemanticTableCell(),
                      !isDiagramAnnotationDuplicate(value, from: frame.blockInsertionIndex),
                      frame.childElementCount == 0 || (!value.isEmpty && blocks[frame.blockInsertionIndex...].allSatisfy { $0.kind == .image }) {
                let classified = classifiedTextBlock(value, attributes: frame.attributes)
                if !stack.contains(where: { $0.name == "li" }) || classified.kind == .note || classified.kind == .warning || classified.kind == .specification {
                    insert(classified, at: frame.blockInsertionIndex, unlessEmpty: value)
                }
            }
        case "li":
            if let listIndex = stack.lastIndex(where: { $0.name == "ol" || $0.name == "ul" }), !value.isEmpty {
                let number = Int(attribute("value", in: frame.attributes) ?? "")
                stack[listIndex].listEntries.append(.init(number: number, text: value, substeps: frame.nestedListItems))
            }
        case "ol", "ul":
            if stack.last?.name == "li" {
                stack[stack.count - 1].nestedListItems.append(contentsOf: frame.listEntries.map(\.text))
            } else if !isInsideSemanticTableCell(), !frame.listEntries.isEmpty {
                let items = frame.listEntries.map(\.text)
                if frame.name == "ol" {
                    let steps = frame.listEntries.enumerated().map { index, entry in
                        ImportedProcedureStep(
                            id: "\(articleID)-procedure-step-\(blocks.count)-\(index)",
                            number: entry.number ?? index + 1,
                            text: entry.text,
                            substeps: entry.substeps
                        )
                    }
                    insert(.init(kind: .numberedSteps, items: items, steps: steps), at: frame.blockInsertionIndex)
                } else {
                    insert(.init(kind: .bulletList, items: items), at: frame.blockInsertionIndex)
                }
            }
        case "td", "th":
            if let rowIndex = stack.lastIndex(where: { $0.name == "tr" }) {
                let rowSpan = Int(attribute("rowspan", in: frame.attributes) ?? "") ?? 1
                let columnSpan = Int(attribute("colspan", in: frame.attributes) ?? "") ?? 1
                stack[rowIndex].hasHeaderCell = stack[rowIndex].hasHeaderCell || frame.name == "th"
                stack[rowIndex].hasSpanningCell = stack[rowIndex].hasSpanningCell || rowSpan > 1 || columnSpan > 1
                stack[rowIndex].rowCells.append(.init(
                    text: value,
                    isHeader: frame.name == "th",
                    rowSpan: rowSpan,
                    columnSpan: columnSpan
                ))
            }
        case "tr":
            if let tableIndex = stack.lastIndex(where: { $0.name == "table" }), !frame.rowCells.isEmpty {
                stack[tableIndex].tableRows.append(frame.rowCells)
                stack[tableIndex].hasHeaderCell = stack[tableIndex].hasHeaderCell || frame.hasHeaderCell
                stack[tableIndex].hasSpanningCell = stack[tableIndex].hasSpanningCell || frame.hasSpanningCell
            }
        case "table":
            let hasVisibleCellText = frame.tableRows.joined().contains { !$0.text.isEmpty }
            let structuralTable = frame.isSemanticDataTable || frame.hasHeaderCell || frame.hasSpanningCell
            if hasVisibleCellText, structuralTable, !frame.isArticleLayoutTable {
                if let marker = frame.cellContentMarker {
                    blocks.removeAll { $0.id == marker }
                }
                insert(
                    .init(kind: .table, rows: frame.tableRows.map { $0.map(\.text) }, tableRows: frame.tableRows),
                    at: frame.blockInsertionIndex,
                    decorateForTableCell: false
                )
            } else if let marker = frame.cellContentMarker,
                      let decisionBlocks = decisionBlocks(from: frame.tableRows, cellBlocks: blocks.filter({ $0.id == marker })) {
                // `Viewer` tables with the first two narrow cells "ДА -" or
                // "НЕТ -" are decision branches, not tabular data. The old
                // renderer flattened only their final cell. Rebuild each row
                // as a paragraph and retain links embedded in its sentence.
                blocks.removeAll { $0.id == marker }
                blocks.insert(contentsOf: decisionBlocks, at: min(frame.blockInsertionIndex, blocks.count))
            }
        case "a":
            if let href = attribute("href", in: frame.attributes), let target = LinkNormalizer.target(href, from: sourcePath) {
                links.append(target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target)
                if let paragraph = stack.lastIndex(where: { $0.name == "p" }), isPositionedAnnotation(stack[paragraph]) {
                    if !value.isEmpty {
                        stack[paragraph].annotationLinks.append(.init(
                            text: value,
                            target: target,
                            lineIndex: max(stack[paragraph].annotationLines.count - 1, 0)
                        ))
                    }
                } else if !isInsideSemanticTableCell(), !value.isEmpty {
                    insert(.init(kind: .link, text: value, target: target), at: blocks.count)
                }
            }
        case "figcaption":
            if !value.isEmpty { blocks.append(ImportedBlock(kind: .note, text: value)) }
        default:
            break
        }
    }

    private mutating func addText(_ raw: String) {
        guard skipDepth == 0, stack.last?.hidden != true else { return }
        let value = decode(raw)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let paragraph = stack.lastIndex(where: { $0.name == "p" && isAbsolutelyPositioned($0) }) {
            stack[paragraph].annotationLines[stack[paragraph].annotationLines.count - 1] += value
        }
        if !stack.isEmpty { stack[stack.count - 1].text += " " + value }
        if !stack.contains(where: { ["head", "title"].contains($0.name) }) { plainText += " " + value }
    }

    private func decisionBlocks(from rows: [[ImportedTableCell]], cellBlocks: [ImportedBlock]) -> [ImportedBlock]? {
        guard !rows.isEmpty else { return nil }
        let decisionLabels = Set(["да", "нет", "yes", "no"])
        let links = cellBlocks.compactMap { block -> ImportedInlineLink? in
            guard block.kind == .link, let target = block.target, !block.text.isEmpty else { return nil }
            return .init(text: block.text, target: target)
        }
        var result: [ImportedBlock] = []
        for row in rows {
            guard row.count >= 3 else { return nil }
            let label = normalizedWhitespace(row[0].text)
            let separator = normalizedWhitespace(row[1].text)
            let body = normalizedWhitespace(row.dropFirst(2).map(\.text).joined(separator: " "))
            guard decisionLabels.contains(label.lowercased()), ["-", "—", "–"].contains(separator), !body.isEmpty else { return nil }
            let inlineLinks = links.filter { body.localizedCaseInsensitiveContains($0.text) }
            result.append(.init(kind: .paragraph, text: "\(label) — \(body)", inlineLinks: inlineLinks))
        }
        return result
    }

    private mutating func addDiagramLineBreak() {
        guard let paragraph = stack.lastIndex(where: { $0.name == "p" && isAbsolutelyPositioned($0) }) else { return }
        stack[paragraph].annotationLines.append("")
    }

    /// A semantic data table already owns its cell text through `tableRows`.
    /// The legacy DOM commonly wraps each cell in `<div>` or `<p>`, which must
    /// not become an additional article block after the table is rendered.
    private func isInsideSemanticTableCell() -> Bool {
        guard stack.contains(where: { $0.name == "td" || $0.name == "th" }) else { return false }
        guard let table = stack.last(where: { $0.name == "table" }) else { return false }
        return table.isSemanticDataTable && !table.isArticleLayoutTable
    }

    private func hasStructuralTableAttributes(_ attributes: String) -> Bool {
        let tableFrame = attribute("frame", in: attributes)?.lowercased() ?? ""
        let rules = attribute("rules", in: attributes)?.lowercased() ?? ""
        let border = Int(attribute("border", in: attributes) ?? "") ?? 0
        return border > 0 || rules == "all" || ["border", "box", "hsides", "vsides", "above", "below"].contains(tableFrame)
    }

    private func hasCellSpan(_ attributes: String) -> Bool {
        (Int(attribute("rowspan", in: attributes) ?? "") ?? 1) > 1 ||
        (Int(attribute("colspan", in: attributes) ?? "") ?? 1) > 1
    }

    private mutating func addImage(_ attributes: String) {
        guard let source = attribute("src", in: attributes), !source.contains("&EsmImgPath;"), let target = LinkNormalizer.target(source, from: sourcePath) else { return }
        let relative = imagePathResolver(target)
        let basename = URL(fileURLWithPath: relative).lastPathComponent.uppercased()
        let viewerChrome = ["RESET_SIZE.PNG", "SIZE_L.PNG", "SIZE_S.PNG", "PRINT.PNG", "PRINT_PREVIEW.PNG", "IMAGE_DISPLAY_RD.PNG", "LABELPNT.PNG", "LABELARW.PNG"]
        guard !viewerChrome.contains(basename), !basename.hasPrefix("GL_"), !basename.hasPrefix("MARKLINE_") else { return }
        guard imagePaths.insert(relative.lowercased()).inserted else { return }
        let alt = attribute("alt", in: attributes)
        let caption = alt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let image = ImportedImage(
            id: "\(articleID)-image-\(images.count)",
            localRelativePath: relative,
            caption: caption,
            altText: caption,
            width: Int(attribute("width", in: attributes) ?? ""),
            height: Int(attribute("height", in: attributes) ?? ""),
            articleID: articleID,
            canvasWidth: stack.last(where: { $0.canvasWidth != nil })?.canvasWidth,
            canvasHeight: stack.last(where: { $0.canvasHeight != nil })?.canvasHeight,
            annotations: []
        )
        images.append(image)
        let isInGraphColumn = stack.contains { frame in
            frame.name == "td" && attribute("id", in: frame.attributes)?.localizedCaseInsensitiveCompare("graphTd") == .orderedSame
        }
        let layoutTable = stack.last(where: { $0.name == "table" && $0.isArticleLayoutTable })
        let procedureCount = layoutTable.map { table in
            blocks[table.blockInsertionIndex...].filter { $0.kind == .numberedSteps }.count
        } ?? 0
        // A short table (one or two steps) uses its graph as an illustration of
        // the latest step. Longer procedures use a single overview diagram for
        // the entire table, as in the radiator example from the source ESM.
        let isLayoutCompanionImage = isInGraphColumn && procedureCount > 2
        blocks.append(ImportedBlock(
            id: isLayoutCompanionImage ? layoutCompanionImageMarker : "",
            kind: .image,
            text: caption ?? "",
            target: relative
        ))
    }

    private func classifiedTextBlock(_ value: String, attributes: String) -> ImportedBlock {
        let className = attribute("class", in: attributes)?.lowercased() ?? ""
        if className.contains("warning") || explicitCallout(value, names: ["опасно", "предупреждение", "внимание"]) { return .init(kind: .warning, text: value) }
        if className.contains("note") || explicitCallout(value, names: ["примечание"]) { return .init(kind: .note, text: value) }
        if value.range(of: "(?:момент затяжки|н·м|n·m|n m|кгс)", options: [.regularExpression, .caseInsensitive]) != nil { return .init(kind: .specification, text: value) }
        return .init(kind: .paragraph, text: value)
    }

    private mutating func insert(_ block: ImportedBlock, at index: Int, unlessEmpty value: String? = nil, decorateForTableCell: Bool = true) {
        if let value, value.isEmpty { return }
        var decorated = block
        if decorateForTableCell,
           decorated.id.isEmpty,
           let marker = stack.last(where: { $0.name == "table" })?.cellContentMarker,
           stack.contains(where: { $0.name == "td" || $0.name == "th" }) {
            decorated.id = marker
        }
        blocks.insert(decorated, at: min(index, blocks.count))
    }

    private func tagName(_ token: String) -> String {
        token.firstMatch(of: /(?i)<\s*\/?\s*([a-z0-9:]+)/).map { String($0.1).lowercased() } ?? ""
    }

    private func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(['\\\"])(.*?)\\1"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              let range = Range(match.range(at: 2), in: attributes) else { return nil }
        return decode(String(attributes[range]))
    }

    private func decode(_ value: String) -> String {
        var result = value
        for _ in 0..<4 {
            let decoded = result.replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
            if decoded == result { break }
            result = decoded
        }
        return result
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func explicitCallout(_ value: String, names: [String]) -> Bool {
        let pattern = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return value.range(of: "^\\s*(?:\(pattern))\\s*[:!—-]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func styleNumber(_ property: String, in style: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        guard let regex = try? NSRegularExpression(pattern: "(?i)(?:^|;)\\s*\(escaped)\\s*:\\s*(-?[0-9.]+)"),
              let match = regex.firstMatch(in: style, range: NSRange(style.startIndex..., in: style)),
              let range = Range(match.range(at: 1), in: style) else { return nil }
        return Double(style[range])
    }

    private func isPositionedAnnotation(_ frame: Frame) -> Bool {
        let style = attribute("style", in: frame.attributes)?.lowercased() ?? ""
        return style.replacingOccurrences(of: " ", with: "").contains("position:absolute")
            && stack.contains(where: { $0.canvasWidth != nil && $0.canvasHeight != nil })
    }

    private mutating func attachAnnotation(text: String, frame: Frame, links: [ImportedImageAnnotationLink]) -> Bool {
        guard !text.isEmpty,
              let imageIndex = images.indices.last,
              images[imageIndex].canvasWidth != nil,
              images[imageIndex].canvasHeight != nil else { return false }
        let style = attribute("style", in: frame.attributes)?.lowercased() ?? ""
        guard let x = styleNumber("left", in: style), let y = styleNumber("top", in: style) else { return false }
        let fontSize = styleNumber("font-size", in: style)
        let lines = frame.annotationLines
            .map(normalizedWhitespace)
            .filter { !$0.isEmpty }
        let lineHeight = sourceLineHeight(fontSize: fontSize)
        let resolvedLinks = links.map { link in
            ImportedImageAnnotationLink(
                text: link.text,
                target: link.target,
                x: x,
                y: y + Double(link.lineIndex) * lineHeight,
                width: sourceTextWidth(link.text, fontSize: fontSize),
                height: lineHeight,
                lineIndex: link.lineIndex
            )
        }
        images[imageIndex].annotations.append(.init(
            id: "\(articleID)-image-\(imageIndex)-annotation-\(images[imageIndex].annotations.count)",
            text: text,
            x: x,
            y: y,
            width: styleNumber("width", in: style),
            height: styleNumber("height", in: style),
            fontSize: fontSize,
            lines: lines,
            links: resolvedLinks
        ))
        return true
    }

    private func isAbsolutelyPositioned(_ frame: Frame) -> Bool {
        let style = attribute("style", in: frame.attributes)?.lowercased() ?? ""
        return style.replacingOccurrences(of: " ", with: "").contains("position:absolute")
    }

    private func sourceLineHeight(fontSize: Double?) -> Double {
        // Browser CSS has 96 px per inch while the source specifies points.
        // 1.2 matches the legacy browser's normal line-height for Arial.
        max((fontSize ?? 7) * 4 / 3 * 1.2, 1)
    }

    private func sourceTextWidth(_ text: String, fontSize: Double?) -> Double {
        // This is only a transparent hit area. The visual label is rendered
        // from the retained source lines; a modest pad keeps it reachable on
        // small screens without moving it from the source coordinate.
        max(Double(text.count) * max((fontSize ?? 7) * 4 / 3, 1) * 0.62, 18)
    }

    private func isDiagramAnnotationDuplicate(_ value: String, from blockIndex: Int) -> Bool {
        guard !value.isEmpty, blockIndex <= blocks.count else { return false }
        let imagePaths = Set(blocks[blockIndex...].compactMap { block in
            block.kind == .image ? block.target : nil
        })
        let annotations = images
            .filter { imagePaths.contains($0.localRelativePath) }
            .flatMap(\.annotations)
        guard !annotations.isEmpty else { return false }
        return annotations.allSatisfy { annotation in
            value.localizedCaseInsensitiveContains(annotation.text)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
