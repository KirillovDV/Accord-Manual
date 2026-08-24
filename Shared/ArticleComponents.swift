import SwiftUI
import SwiftData
import UIKit

enum ArticleContentItem: Identifiable {
    case block(ArticleBlock)
    case note(ArticleNoteGroup)

    var id: String {
        switch self {
        case let .block(block): block.id
        case let .note(note): note.id
        }
    }

    var block: ArticleBlock? {
        guard case let .block(block) = self else { return nil }
        return block
    }

    var note: ArticleNoteGroup? {
        guard case let .note(note) = self else { return nil }
        return note
    }
}

struct ArticleNoteGroup: Identifiable {
    let block: ArticleBlock
    let supportingBlocks: [ArticleBlock]
    var id: String { block.id }
}

enum ArticleContentLayout {
    static func blocks(from source: [ArticleBlock]) -> [ArticleContentItem] {
        var result: [ArticleContentItem] = []
        var index = 0
        while index < source.count {
            let block = source[index]
            guard block.kind == .note, isStandaloneNoteLabel(block.text) else {
                result.append(.block(block))
                index += 1
                continue
            }

            var supportingBlocks: [ArticleBlock] = []
            var next = index + 1
            while next < source.count, isSupportingNoteContent(source[next]) {
                supportingBlocks.append(source[next])
                next += 1
            }
            result.append(.note(ArticleNoteGroup(block: block, supportingBlocks: supportingBlocks)))
            index = next
        }
        return result
    }

    static func isStandaloneNoteLabel(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.range(of: "^примечание\\s*:?$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isSupportingNoteContent(_ block: ArticleBlock) -> Bool {
        switch block.kind {
        case .paragraph, .bulletList, .link, .image, .table:
            true
        case .heading, .numberedSteps, .warning, .note, .anchor, .specification:
            false
        }
    }
}

struct ProcedureStepDisplayContent {
    let stepText: String
    let regularSubsteps: [String]
    let regularSupportingBlocks: [ArticleBlock]
    let note: ArticleNoteGroup?
}

enum ProcedureStepContentLayout {
    static func content(for step: ProcedureStep) -> ProcedureStepDisplayContent {
        let split = splitInlineNote(from: step.text)
        guard let noteIndex = step.supportingBlocks.firstIndex(where: { $0.kind == .note }) else {
            guard let inlineNote = split.noteText else {
                return ProcedureStepDisplayContent(
                    stepText: step.text,
                    regularSubsteps: step.substeps,
                    regularSupportingBlocks: step.supportingBlocks,
                    note: nil
                )
            }

            let note = ArticleBlock(
                id: "\(step.id)-inline-note",
                kind: .note,
                text: inlineNote
            )
            return ProcedureStepDisplayContent(
                stepText: split.stepText,
                regularSubsteps: step.substeps,
                regularSupportingBlocks: step.supportingBlocks,
                note: ArticleNoteGroup(block: note, supportingBlocks: [])
            )
        }

        let originalMarker = step.supportingBlocks[noteIndex]
        let marker = split.noteText.map { noteBlock(replacingTextOf: originalMarker, with: $0) } ?? originalMarker
        var noteBlocks: [ArticleBlock] = []
        if !step.substeps.isEmpty {
            noteBlocks.append(ArticleBlock(
                id: "\(step.id)-note-substeps",
                kind: .bulletList,
                items: step.substeps
            ))
        }
        noteBlocks += step.supportingBlocks.dropFirst(noteIndex + 1).filter {
            !($0.kind == .note && ArticleContentLayout.isStandaloneNoteLabel($0.text))
        }

        return ProcedureStepDisplayContent(
            stepText: split.stepText,
            regularSubsteps: [],
            regularSupportingBlocks: Array(step.supportingBlocks[..<noteIndex]),
            note: ArticleNoteGroup(block: marker, supportingBlocks: noteBlocks)
        )
    }

    private static func splitInlineNote(from stepText: String) -> (stepText: String, noteText: String?) {
        let pattern = "(?i)\\bпримечание\\s*:"
        guard let range = stepText.range(of: pattern, options: .regularExpression) else {
            return (stepText, nil)
        }
        let title = String(stepText[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = String(stepText[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, note.isEmpty ? nil : note)
    }

    private static func noteBlock(replacingTextOf block: ArticleBlock, with text: String) -> ArticleBlock {
        ArticleBlock(
            id: block.id,
            kind: block.kind,
            text: text,
            items: block.items,
            rows: block.rows,
            tableRows: block.tableRows,
            target: block.target,
            anchor: block.anchor,
            steps: block.steps,
            inlineLinks: block.inlineLinks
        )
    }
}

struct ArticleBlockView: View {
    @Environment(ManualStore.self) private var store
    @Environment(NavigationRouter.self) private var router
    let block: ArticleBlock
    let article: ManualArticle
    let findText: String
    let openImage: (String) -> Void
    var openLink: ((String) -> Void)? = nil
    var highlightedAnchor: String? = nil

    var body: some View {
        content
            .id(block.anchor ?? block.id)
            .background(isHighlighted ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2), value: isHighlighted)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .heading:
            HighlightedText(text: block.text, query: findText).font(.title2.bold())
        case .paragraph, .specification:
            InlineLinkedText(text: block.text, links: block.inlineLinks, query: findText, openLink: navigate).font(.body)
        case .numberedSteps:
            ProcedureChecklist(block: block, article: article, findText: findText, openImage: openImage, openLink: openLink, highlightedAnchor: highlightedAnchor)
        case .bulletList:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "circle.fill").labelStyle(BulletLabelStyle())
                }
            }
        case .warning:
            Callout(title: warningTitle(block.text), text: block.text, symbol: "exclamationmark.triangle.fill")
        case .note:
            NoteCalloutView(note: ArticleNoteGroup(block: block, supportingBlocks: []), article: article, findText: findText, openImage: openImage, openLink: openLink, highlightedAnchor: highlightedAnchor)
        case .table:
            SpecificationTable(rows: block.tableRows)
        case .image:
            ManualImageThumbnail(
                metadata: article.images.first { $0.localRelativePath == block.target },
                path: block.target,
                label: imageLabel,
                openImage: { if let target = block.target { openImage(target) } }
            )
            .accessibilityHint("Открывает изображение на весь экран")
        case .link:
            linkView
        case .anchor:
            Color.clear.frame(height: 1)
        }
    }

    private var imageLabel: String {
        if !block.text.isEmpty { return block.text }
        let index = article.images.firstIndex(where: { $0.localRelativePath == block.target }).map { $0 + 1 } ?? 1
        return "Рисунок \(index) из \(article.images.count)"
    }

    @ViewBuilder private var linkView: some View {
        if let target = block.target, destination(for: target) != nil {
            Button { navigate(target) } label: {
                Label(block.text, systemImage: "link")
            }
        } else {
            Label(block.text, systemImage: "link.badge.plus").foregroundStyle(.secondary)
        }
    }

    private var isHighlighted: Bool {
        guard let highlightedAnchor else { return false }
        return block.anchor == highlightedAnchor || block.id == highlightedAnchor
    }

    private func navigate(_ target: String) {
        if let openLink {
            openLink(target)
        } else if let destination = destination(for: target) {
            router.open(articleID: destination.article.id, anchor: destination.anchor)
        }
    }

    private func destination(for target: String) -> (article: ManualArticle, anchor: String?)? {
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let destination = store.article(path: String(parts[0])) else { return nil }
        let anchor = parts.count == 2 && !["000", "i000"].contains(String(parts[1])) ? String(parts[1]) : nil
        return (destination, anchor)
    }

    private func warningTitle(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("опасно") { return "Опасно" }
        if lower.contains("предупреждение") { return "Предупреждение" }
        return "Внимание"
    }
}

private struct BulletLabelStyle: LabelStyle { func makeBody(configuration: Configuration) -> some View { HStack(alignment: .firstTextBaseline, spacing: 10) { configuration.icon.imageScale(.small); configuration.title } } }
private struct Callout: View { let title: String; let text: String; let symbol: String; var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: symbol).accessibilityHidden(true); VStack(alignment: .leading) { Text(title).font(.headline); Text(text) } }.padding().background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("\(title). \(text)") } }
struct NoteCalloutView: View {
    let note: ArticleNoteGroup
    let article: ManualArticle
    let findText: String
    let openImage: (String) -> Void
    var openLink: ((String) -> Void)? = nil
    var highlightedAnchor: String? = nil
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if UIAccessibility.isReduceMotionEnabled {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").imageScale(.medium).accessibilityHidden(true)
                    Text("Примечание").font(.headline)
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Примечание")
            .accessibilityValue(isExpanded ? "Развернуто" : "Свернуто")
            .accessibilityHint(isExpanded ? "Свернуть примечание" : "Развернуть примечание")

            if isExpanded {
                if !noteText.isEmpty {
                    HighlightedText(text: noteText, query: findText).font(.body)
                }
                ForEach(note.supportingBlocks) { block in
                    ArticleBlockView(block: block, article: article, findText: findText, openImage: openImage, openLink: openLink, highlightedAnchor: highlightedAnchor)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .id(note.block.anchor ?? note.id)
    }

    private var noteText: String {
        note.block.text
            .replacingOccurrences(of: "(?i)^\\s*примечание\\s*:\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
private struct SpecificationTable: View {
    let rows: [[ManualTableCell]]
    private var layout: [[TableLayoutCell]] { TableLayout.rows(from: rows) }
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(layout.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow(alignment: .top) {
                        ForEach(row) { item in
                            if let cell = item.cell {
                                Text(cell.text)
                                    .font(cell.isHeader || rowIndex == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                    .frame(minWidth: 136 * Double(item.columnSpan), maxWidth: 240 * Double(item.columnSpan), minHeight: 42, alignment: .topLeading)
                                    .padding(10)
                                    .background(cell.isHeader || rowIndex == 0 ? Color.secondary.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
                                    .overlay { Rectangle().stroke(Color.secondary.opacity(0.28), lineWidth: 0.5) }
                                    .gridCellColumns(item.columnSpan)
                                    .accessibilityLabel(tableCellLabel(cell))
                            } else {
                                Color.clear.frame(minWidth: 136, minHeight: 42).gridCellColumns(item.columnSpan).accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .padding(1)
        }
        .scrollIndicators(.visible)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Таблица, строк: \(rows.count)")
    }
    private func tableCellLabel(_ cell: ManualTableCell) -> String { var details = cell.text; if cell.isHeader { details = "Заголовок. " + details }; if cell.rowSpan > 1 { details += ". Объединяет \(cell.rowSpan) строки" }; if cell.columnSpan > 1 { details += ". Объединяет \(cell.columnSpan) столбца" }; return details }
}

struct TableLayoutCell: Identifiable, Equatable {
    let id: String
    let cell: ManualTableCell?
    let columnSpan: Int
}

enum TableLayout {
    static func rows(from source: [[ManualTableCell]]) -> [[TableLayoutCell]] {
        var pending: [Int: (remaining: Int, isHeader: Bool)] = [:]
        var result: [[TableLayoutCell]] = []
        var maximumColumns = 0
        for (rowIndex, sourceRow) in source.enumerated() {
            let active = pending
            pending = pending.compactMapValues { value in value.remaining > 1 ? (value.remaining - 1, value.isHeader) : nil }
            var rendered: [TableLayoutCell] = []
            var column = 0
            func appendOccupiedColumns() {
                while active[column] != nil {
                    rendered.append(.init(id: "\(rowIndex)-\(column)-span", cell: nil, columnSpan: 1))
                    column += 1
                }
            }
            for (cellIndex, cell) in sourceRow.enumerated() {
                appendOccupiedColumns()
                while (column..<(column + cell.columnSpan)).contains(where: { active[$0] != nil }) {
                    rendered.append(.init(id: "\(rowIndex)-\(column)-gap", cell: nil, columnSpan: 1))
                    column += 1
                    appendOccupiedColumns()
                }
                rendered.append(.init(id: "\(rowIndex)-\(column)-\(cellIndex)", cell: cell, columnSpan: cell.columnSpan))
                if cell.rowSpan > 1 {
                    for occupied in column..<(column + cell.columnSpan) { pending[occupied] = (cell.rowSpan - 1, cell.isHeader) }
                }
                column += cell.columnSpan
            }
            let lastActiveColumn = active.keys.max().map { $0 + 1 } ?? 0
            while column < lastActiveColumn {
                rendered.append(.init(id: "\(rowIndex)-\(column)-tail", cell: nil, columnSpan: 1))
                column += 1
            }
            maximumColumns = max(maximumColumns, column)
            result.append(rendered)
        }
        return result.enumerated().map { rowIndex, row in
            let used = row.reduce(0) { $0 + $1.columnSpan }
            guard used < maximumColumns else { return row }
            return row + [.init(id: "\(rowIndex)-padding", cell: nil, columnSpan: maximumColumns - used)]
        }
    }
}

struct HighlightedText: View {
    let text: String
    let query: String
    var body: some View { Text(attributed) }
    private var attributed: AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange), let range = Range(found, in: result) {
            result[range].backgroundColor = .yellow.opacity(0.55)
            result[range].foregroundColor = .primary
            searchRange = found.upperBound..<text.endIndex
        }
        return result
    }
}

private struct InlineLinkedText: View {
    let text: String
    let links: [ArticleInlineLink]
    let query: String
    let openLink: (String) -> Void

    var body: some View {
        Text(attributed)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "accordmanual",
                      let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "target" })?.value else {
                    return .systemAction
                }
                openLink(target)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        var searchStart = text.startIndex
        for link in links {
            guard !link.text.isEmpty,
                  let range = text.range(of: link.text, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex),
                  let attributedRange = Range(range, in: result),
                  let url = linkURL(target: link.target) else { continue }
            result[attributedRange].link = url
            result[attributedRange].underlineStyle = .single
            searchStart = range.upperBound
        }
        var queryStart = text.startIndex
        while !query.isEmpty,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: queryStart..<text.endIndex),
              let attributedRange = Range(range, in: result) {
            result[attributedRange].backgroundColor = .yellow.opacity(0.55)
            queryStart = range.upperBound
        }
        return result
    }

    private func linkURL(target: String) -> URL? {
        var components = URLComponents()
        components.scheme = "accordmanual"
        components.host = "article-link"
        components.queryItems = [URLQueryItem(name: "target", value: target)]
        return components.url
    }
}

struct ProcedureChecklist: View {
    @Environment(\.modelContext) private var context
    @Query private var states: [ChecklistState]
    let block: ArticleBlock
    let article: ManualArticle
    let findText: String
    let openImage: (String) -> Void
    let openLink: ((String) -> Void)?
    let highlightedAnchor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Порядок выполнения").font(.headline)
            ForEach(Array(steps), id: \ProcedureStep.id) { step in
                let content = ProcedureStepContentLayout.content(for: step)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: binding(step)) {
                        HighlightedText(text: "\(step.number). \(content.stepText)", query: findText)
                    }
                    .accessibilityLabel("Шаг \(step.number): \(content.stepText)")

                    ForEach(content.regularSupportingBlocks) { supporting in
                        ArticleBlockView(
                            block: supporting,
                            article: article,
                            findText: findText,
                            openImage: openImage,
                            openLink: openLink,
                            highlightedAnchor: highlightedAnchor
                        )
                        .padding(.leading, 32)
                    }

                    if let note = content.note {
                        NoteCalloutView(note: note, article: article, findText: findText, openImage: openImage, openLink: openLink, highlightedAnchor: highlightedAnchor)
                            .padding(.leading, 32)
                    }

                    if !content.regularSubsteps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(content.regularSubsteps.enumerated()), id: \.offset) { _, item in
                                Label(item, systemImage: "circle.fill").labelStyle(BulletLabelStyle())
                            }
                        }
                        .padding(.leading, 32)
                    }
                }
                .background(step.anchors.contains(highlightedAnchor ?? "") ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .id(step.id)
                ForEach(step.anchors, id: \.self) { anchor in
                    Color.clear.frame(height: 0).id(anchor).accessibilityHidden(true)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var steps: [ProcedureStep] {
        if !block.steps.isEmpty { return block.steps }
        return block.items.enumerated().map { index, item in
            ProcedureStep(id: "\(block.id)-legacy-step-\(index)", number: index + 1, text: item)
        }
    }

    private func binding(_ step: ProcedureStep) -> Binding<Bool> {
        let key = "\(article.id):\(block.id):\(step.id)"
        return Binding {
            states.first { $0.key == key }?.complete ?? false
        } set: { value in
            if let state = states.first(where: { $0.key == key }) {
                state.complete = value
            } else {
                context.insert(ChecklistState(key: key, complete: value))
            }
        }
    }
}

struct ManualImageThumbnail: View {
    let metadata: ManualImage?
    let path: String?
    let label: String
    let openImage: () -> Void
    @State private var image: UIImage?
    @State private var didFail = false
    var body: some View {
        Group {
            if let image {
                Button(action: openImage) {
                    AnnotatedDiagram(image: image, metadata: metadata)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Открыть рисунок")
                .accessibilityHint("Открывает рисунок на весь экран")
            }
            else if didFail { ContentUnavailableView("Изображение недоступно", systemImage: "photo.badge.exclamationmark", description: Text(label)) }
            else { ProgressView("Загрузка рисунка…").frame(maxWidth: .infinity, minHeight: 120) }
        }
        .accessibilityElement(children: .contain)
        .task(id: path) {
            guard let path else { didFail = true; return }
            image = await ManualImageCache.shared.image(path: path)
            didFail = image == nil
        }
    }
}

struct AnnotatedDiagram: View {
    let image: UIImage
    let metadata: ManualImage?
    var annotationLinkSelected: ((ImageAnnotationLink, CGRect) -> Void)?
    var renderScale: CGFloat?

    init(
        image: UIImage,
        metadata: ManualImage?,
        annotationLinkSelected: ((ImageAnnotationLink, CGRect) -> Void)? = nil,
        renderScale: CGFloat? = nil
    ) {
        self.image = image
        self.metadata = metadata
        self.annotationLinkSelected = annotationLinkSelected
        self.renderScale = renderScale
    }

    var body: some View {
        let canvas = sourceCanvas
        Group {
            if let renderScale {
                DiagramArtworkLayer(
                    image: image,
                    metadata: metadata,
                    sourceCanvas: canvas,
                    renderScale: renderScale,
                    annotationLinkSelected: annotationLinkSelected
                )
            } else {
                GeometryReader { geometry in
                    let scale = min(
                        geometry.size.width / max(canvas.width, 1),
                        geometry.size.height / max(canvas.height, 1)
                    )
                    let renderedSize = CGSize(width: canvas.width * scale, height: canvas.height * scale)
                    DiagramArtworkLayer(
                        image: image,
                        metadata: metadata,
                        sourceCanvas: canvas,
                        renderScale: scale,
                        annotationLinkSelected: annotationLinkSelected
                    )
                    .frame(width: renderedSize.width, height: renderedSize.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .aspectRatio(canvas.width / max(canvas.height, 1), contentMode: .fit)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sourceCanvas: CGSize {
        CGSize(
            width: max(metadata?.canvasWidth ?? Double(image.size.width), 1),
            height: max(metadata?.canvasHeight ?? Double(image.size.height), 1)
        )
    }
}

private struct DiagramArtworkLayer: View {
    let image: UIImage
    let metadata: ManualImage?
    let sourceCanvas: CGSize
    let renderScale: CGFloat
    let annotationLinkSelected: ((ImageAnnotationLink, CGRect) -> Void)?

    var body: some View {
        let renderedSize = CGSize(
            width: sourceCanvas.width * renderScale,
            height: sourceCanvas.height * renderScale
        )
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: renderedSize.width, height: renderedSize.height)
                .accessibilityHidden(true)
            DiagramAnnotations(
                annotations: metadata?.annotations ?? [],
                renderScale: renderScale
            )
            .frame(width: renderedSize.width, height: renderedSize.height, alignment: .topLeading)
            if let annotationLinkSelected {
                DiagramImageMap(
                    links: metadata?.annotations.flatMap(\.links) ?? [],
                    renderScale: renderScale,
                    selected: annotationLinkSelected
                )
                .frame(width: renderedSize.width, height: renderedSize.height, alignment: .topLeading)
            }
        }
        .frame(width: renderedSize.width, height: renderedSize.height, alignment: .topLeading)
        .clipped()
    }
}

private struct DiagramAnnotations: View {
    let annotations: [ImageAnnotation]
    let renderScale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(annotations) { annotation in
                let lines = annotation.lines.isEmpty ? [annotation.text] : annotation.lines
                let pointSize = CGFloat(max(annotation.fontSize ?? 7, 1) * 4 / 3) * renderScale
                let lineHeight = max(pointSize * 1.2, 1)
                ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                    let linked = annotation.links.contains { $0.lineIndex == lineIndex && $0.text == line }
                    Text(line)
                        .font(.custom("Arial-BoldMT", size: pointSize))
                        .foregroundStyle(linked ? Color.accentColor : Color.black)
                        .underline(linked)
                        .fixedSize(horizontal: true, vertical: true)
                        .offset(
                            x: CGFloat(annotation.x) * renderScale,
                            y: CGFloat(annotation.y) * renderScale + CGFloat(lineIndex) * lineHeight
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct DiagramImageMap: View {
    let links: [ImageAnnotationLink]
    let renderScale: CGFloat
    let selected: (ImageAnnotationLink, CGRect) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(links) { link in
                Button {
                    selected(link, DiagramGeometry.sourceLinkFrame(link))
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(
                    width: max(CGFloat(link.width) * renderScale, 1),
                    height: max(CGFloat(link.height) * renderScale, 1)
                )
                .offset(x: CGFloat(link.x) * renderScale, y: CGFloat(link.y) * renderScale)
                .accessibilityLabel("Ссылка на схеме: \(link.text)")
                .accessibilityHint("Открывает связанную статью")
            }
        }
    }
}
