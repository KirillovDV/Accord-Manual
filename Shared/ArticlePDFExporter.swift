import Foundation
import UIKit
import CoreGraphics

enum ArticlePDFExporter {
    private static let portrait = CGSize(width: 595, height: 842) // A4, 72 dpi
    private static let landscape = CGSize(width: 842, height: 595)
    nonisolated private static let margin: CGFloat = 38

    @MainActor static func render(article: ManualArticle) throws -> Data {
        let needsLandscape = article.images.contains { image in
            let width = image.canvasWidth ?? Double(image.width ?? 0)
            let height = image.canvasHeight ?? Double(image.height ?? 1)
            return width / max(height, 1) > 1.25
        } || article.blocks.contains { $0.kind == .table && tableColumnCount($0) > 3 }
        let pageSize = needsLandscape ? landscape : portrait
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: pdfFormat(article: article))
        return renderer.pdfData { context in
            var layout = Layout(context: context, pageSize: pageSize, title: article.title)
            layout.beginPage()
            layout.drawArticleHeader(article)

            let blocks = ArticleContentLayout.blocks(from: article.blocks)
            for (index, item) in blocks.enumerated() {
                switch item {
                case let .block(block):
                    guard block.kind != .anchor else { continue }
                    let nextBlock = blocks.indices.contains(index + 1) ? blocks[index + 1].block : nil
                    layout.draw(block, article: article, keepWithNext: block.kind == .heading && nextBlock != nil)
                case let .note(note):
                    layout.drawNote(note, article: article)
                }
            }
        }
    }

    @MainActor static func write(article: ManualArticle) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: article.title), isDirectory: false)
        try render(article: article).write(to: url, options: .atomic)
        return url
    }

    static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let parts = title.components(separatedBy: forbidden)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let compact = parts.joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "\(String((compact.isEmpty ? "Accord-Manual" : compact).prefix(90))).pdf"
    }

    static func pageCount(in data: Data) -> Int {
        guard let document = CGPDFDocument(CGDataProvider(data: data as CFData)!) else { return 0 }
        return document.numberOfPages
    }

    static func noteText(for note: ArticleNoteGroup) -> String {
        var lines: [String] = []
        let headerText = note.block.text
            .replacingOccurrences(of: "(?i)^\\s*примечание\\s*:\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !headerText.isEmpty { lines.append(headerText) }
        for block in note.supportingBlocks {
            switch block.kind {
            case .paragraph, .specification:
                if !block.text.isEmpty { lines.append(block.text) }
            case .bulletList:
                lines += block.items.map { "• \($0)" }
            case .link:
                let label = block.target.map { "\(block.text)  [\($0)]" } ?? block.text
                if !label.isEmpty { lines.append(label) }
            case .warning, .note:
                if !block.text.isEmpty { lines.append(block.text) }
            case .heading, .numberedSteps, .table, .image, .anchor:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor private static func pdfFormat(article: ManualArticle) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: article.title,
            kCGPDFContextAuthor as String: "Accord Manual",
            kCGPDFContextSubject as String: article.breadcrumbs.joined(separator: " › ")
        ]
        return format
    }

    private static func tableColumnCount(_ block: ArticleBlock) -> Int {
        let rows = block.tableRows.isEmpty ? block.rows.map { $0.map { ManualTableCell(text: $0) } } : block.tableRows
        return rows.map { $0.reduce(0) { $0 + $1.columnSpan } }.max() ?? 0
    }

    @MainActor private struct Layout {
        let context: UIGraphicsPDFRendererContext
        let pageSize: CGSize
        let title: String
        let content: CGRect
        var y: CGFloat = 0
        var pageNumber = 0

        init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, title: String) {
            self.context = context
            self.pageSize = pageSize
            self.title = title
            self.content = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        }

        mutating func beginPage() {
            context.beginPage()
            pageNumber += 1
            y = content.minY
            drawFooter()
        }

        mutating func drawArticleHeader(_ article: ManualArticle) {
            let breadcrumbs = article.breadcrumbs.joined(separator: " › ")
            drawText(breadcrumbs, font: .systemFont(ofSize: 9), color: .secondaryLabel, spacing: 3)
            drawText(article.title, font: .boldSystemFont(ofSize: 22), color: .label, spacing: 12, keepTogether: true)
            if let esmKey = article.esmKey, !esmKey.isEmpty {
                drawText("ESM: \(esmKey)", font: .systemFont(ofSize: 8), color: .secondaryLabel, spacing: 12)
            }
        }

        mutating func draw(_ block: ArticleBlock, article: ManualArticle, keepWithNext: Bool) {
            switch block.kind {
            case .heading:
                drawText(block.text, font: .boldSystemFont(ofSize: 16), color: .label, spacing: 8, keepTogether: keepWithNext)
            case .paragraph, .specification:
                drawText(block.text, font: .systemFont(ofSize: 11), color: .label, spacing: 8)
            case .numberedSteps:
                let steps = block.steps.isEmpty
                    ? block.items.enumerated().map { ProcedureStep(id: "\(block.id)-pdf-step-\($0.offset)", number: $0.offset + 1, text: $0.element) }
                    : block.steps
                for step in steps {
                    let content = ProcedureStepContentLayout.content(for: step)
                    drawText("\(step.number). \(content.stepText)", font: .systemFont(ofSize: 11), color: .label, spacing: 5)
                    if let note = content.note { drawNote(note, article: article) }
                    for substep in content.regularSubsteps {
                        drawText("     • \(substep)", font: .systemFont(ofSize: 10.5), color: .label, spacing: 4)
                    }
                    for supporting in content.regularSupportingBlocks {
                        draw(supporting, article: article, keepWithNext: false)
                    }
                }
                addSpacing(6)
            case .bulletList:
                for item in block.items { drawText("• \(item)", font: .systemFont(ofSize: 11), color: .label, spacing: 5) }
                addSpacing(6)
            case .warning:
                drawCallout(title: warningTitle(block.text), text: block.text)
            case .note:
                drawNote(ArticleNoteGroup(block: block, supportingBlocks: []), article: article)
            case .table:
                drawTable(block)
            case .image:
                if let target = block.target, let image = article.images.first(where: { $0.localRelativePath == target }) { drawImage(image, fallbackCaption: block.text) }
            case .link:
                let label = block.target.map { "\(block.text)  [\($0)]" } ?? block.text
                drawText(label, font: .systemFont(ofSize: 10), color: .systemBlue, spacing: 6)
            case .anchor:
                break
            }
        }

        mutating func drawNote(_ note: ArticleNoteGroup, article: ManualArticle) {
            drawCallout(title: "Примечание", text: ArticlePDFExporter.noteText(for: note))
            for block in note.supportingBlocks where block.kind == .image || block.kind == .table {
                draw(block, article: article, keepWithNext: false)
            }
        }

        mutating func drawText(_ text: String, font: UIFont, color: UIColor, spacing: CGFloat, keepTogether: Bool = false) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.lineSpacing = max(font.pointSize * 0.16, 1)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
            let rendered = NSAttributedString(string: text, attributes: attributes)
            let height = rendered.boundingRect(with: CGSize(width: content.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral.height
            if keepTogether && height <= content.height, y + height > content.maxY { beginPage() }
            drawAttributed(rendered, estimatedHeight: height, spacing: spacing)
        }

        mutating func drawCallout(title: String, text: String) {
            let full = "\(title)\n\(text)"
            let font = UIFont.systemFont(ofSize: 11)
            let style = NSMutableParagraphStyle(); style.lineSpacing = 2
            let rendered = NSAttributedString(string: full, attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: style])
            let height = max(rendered.boundingRect(with: CGSize(width: content.width - 24, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height + 20, 44)
            if height <= content.height, y + height > content.maxY { beginPage() }
            let rect = CGRect(x: content.minX, y: y, width: content.width, height: min(height, content.maxY - y))
            UIColor.secondarySystemFill.setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
            rendered.draw(in: rect.insetBy(dx: 12, dy: 10))
            y = rect.maxY + 10
        }

        mutating func drawTable(_ block: ArticleBlock) {
            let rows = block.tableRows.isEmpty ? block.rows.map { $0.map { ManualTableCell(text: $0) } } : block.tableRows
            guard !rows.isEmpty else { return }
            let columns = max(rows.map { $0.reduce(0) { $0 + $1.columnSpan } }.max() ?? 1, 1)
            let width = content.width / CGFloat(columns)
            for (rowIndex, row) in rows.enumerated() {
                let rowHeight = max(28, row.map { cell in
                    let font = UIFont.systemFont(ofSize: 8.5)
                    return (cell.text as NSString).boundingRect(with: CGSize(width: width * CGFloat(cell.columnSpan) - 12, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height + 14
                }.max() ?? 28)
                if y + rowHeight > content.maxY { beginPage() }
                var x = content.minX
                for cell in row {
                    let cellWidth = width * CGFloat(cell.columnSpan)
                    let rect = CGRect(x: x, y: y, width: cellWidth, height: rowHeight)
                    (rowIndex == 0 || cell.isHeader ? UIColor.secondarySystemFill : UIColor.systemBackground).setFill(); UIRectFill(rect)
                    UIColor.separator.setStroke(); UIBezierPath(rect: rect).stroke()
                    let font = rowIndex == 0 || cell.isHeader ? UIFont.boldSystemFont(ofSize: 8.5) : UIFont.systemFont(ofSize: 8.5)
                    NSAttributedString(string: cell.text, attributes: [.font: font, .foregroundColor: UIColor.label]).draw(in: rect.insetBy(dx: 6, dy: 6))
                    x += cellWidth
                }
                y += rowHeight
            }
            addSpacing(12)
        }

        mutating func drawImage(_ metadata: ManualImage, fallbackCaption: String) {
            let caption = metadata.caption ?? metadata.altText ?? fallbackCaption
            guard let image = ManualImageCache.shared.syncImage(path: metadata.localRelativePath) else {
                drawText("Изображение недоступно: \(caption)", font: .italicSystemFont(ofSize: 10), color: .secondaryLabel, spacing: 8)
                return
            }
            let source = CGSize(width: metadata.canvasWidth ?? Double(image.size.width), height: metadata.canvasHeight ?? Double(image.size.height))
            let width = content.width
            let imageHeight = width * source.height / max(source.width, 1)
            let captionHeight: CGFloat = caption.isEmpty ? 0 : 17
            if imageHeight + captionHeight <= content.height {
                if y + imageHeight + captionHeight > content.maxY { beginPage() }
                let rect = CGRect(x: content.minX, y: y, width: width, height: imageHeight)
                image.draw(in: rect)
                drawAnnotations(metadata.annotations, in: rect, canvas: source)
                y = rect.maxY
                if !caption.isEmpty { drawText(caption, font: .italicSystemFont(ofSize: 9), color: .secondaryLabel, spacing: 10) }
                else { addSpacing(10) }
            } else {
                beginPage()
                let fit = min(width / source.width, content.height / source.height)
                let rendered = CGSize(width: source.width * fit, height: source.height * fit)
                let rect = CGRect(x: content.midX - rendered.width / 2, y: content.midY - rendered.height / 2, width: rendered.width, height: rendered.height)
                image.draw(in: rect)
                drawAnnotations(metadata.annotations, in: rect, canvas: source)
                y = content.maxY
                beginPage()
                if !caption.isEmpty { drawText(caption, font: .italicSystemFont(ofSize: 9), color: .secondaryLabel, spacing: 10) }
            }
        }

        func drawAnnotations(_ annotations: [ImageAnnotation], in rect: CGRect, canvas: CGSize) {
            guard !annotations.isEmpty else { return }
            let scale = rect.width / max(canvas.width, 1)
            for annotation in annotations {
                let size = max(CGFloat(annotation.fontSize ?? 7) * scale, 3)
                let frame = CGRect(x: rect.minX + CGFloat(annotation.x) * scale, y: rect.minY + CGFloat(annotation.y) * scale, width: rect.maxX - (rect.minX + CGFloat(annotation.x) * scale), height: rect.maxY - (rect.minY + CGFloat(annotation.y) * scale))
                NSAttributedString(string: annotation.text, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]).draw(in: frame)
            }
        }

        mutating func drawAttributed(_ text: NSAttributedString, estimatedHeight: CGFloat, spacing: CGFloat) {
            var remaining = text
            while remaining.length > 0 {
                if y >= content.maxY - 1 { beginPage() }
                let available = content.maxY - y
                let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(remaining), CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: content.minX, y: 0, width: content.width, height: available), transform: nil), nil)
                let visible = CTFrameGetVisibleStringRange(frame).length
                guard visible > 0 else { beginPage(); continue }
                let chunk = remaining.attributedSubstring(from: NSRange(location: 0, length: visible))
                let used = chunk.boundingRect(with: CGSize(width: content.width, height: available), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral.height
                chunk.draw(in: CGRect(x: content.minX, y: y, width: content.width, height: used))
                y += used
                if visible < remaining.length { remaining = remaining.attributedSubstring(from: NSRange(location: visible, length: remaining.length - visible)); beginPage() }
                else { y += spacing; remaining = NSAttributedString() }
            }
        }

        mutating func addSpacing(_ value: CGFloat) { if y + value > content.maxY { beginPage() } else { y += value } }

        func drawFooter() {
            let number = "Accord Manual  •  \(pageNumber)"
            NSAttributedString(string: number, attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.secondaryLabel]).draw(at: CGPoint(x: content.minX, y: pageSize.height - margin + 12))
        }

        private func warningTitle(_ text: String) -> String {
            let lower = text.lowercased()
            if lower.contains("опасно") { return "Опасно" }
            if lower.contains("предупреждение") { return "Предупреждение" }
            return "Внимание"
        }
    }
}
