import XCTest
import UIKit
@testable import AccordManual

@MainActor
final class ManualStoreTests: XCTestCase {
    func testPrivacyPolicyStatesThatDataStaysOnDeviceAndTrackingIsDisabled() {
        XCTAssertEqual(PrivacyPolicy.appPrivacySummary, "Данные не собираются")
        XCTAssertFalse(PrivacyPolicy.tracksUsers)
        XCTAssertTrue(PrivacyPolicy.inAppText.contains("на устройстве"))
        XCTAssertTrue(PrivacyPolicy.inAppText.contains(AppConfiguration.supportEmail))
    }

    func testArticleContentLayoutGroupsStandaloneNoteAndItsSupportingBlocks() {
        let note = ArticleBlock(id: "note", kind: .note, text: "ПРИМЕЧАНИЕ:")
        let list = ArticleBlock(id: "list", kind: .bulletList, items: ["Первый пункт"])
        let link = ArticleBlock(id: "link", kind: .link, text: "Связанная статья", target: "ru/html/next.html#i010")
        let image = ArticleBlock(id: "image", kind: .image, target: "ru/img/note.png")
        let anchor = ArticleBlock(id: "anchor", kind: .anchor, text: "i020", anchor: "i020")
        let followingText = ArticleBlock(id: "following", kind: .paragraph, text: "Основной текст после примечания")

        let layout = ArticleContentLayout.blocks(from: [note, list, link, image, anchor, followingText])

        XCTAssertEqual(layout.count, 3)
        XCTAssertEqual(layout[0].note?.supportingBlocks.map(\.id), ["list", "link", "image"])
        XCTAssertEqual(layout[1].block?.id, "anchor")
        XCTAssertEqual(layout[2].block?.id, "following")
    }

    func testArticleContentLayoutDoesNotAbsorbTextAfterPopulatedNote() {
        let note = ArticleBlock(id: "note", kind: .note, text: "Примечание: Используйте подходящий инструмент.")
        let followingText = ArticleBlock(id: "following", kind: .paragraph, text: "Основной текст статьи")

        let layout = ArticleContentLayout.blocks(from: [note, followingText])

        XCTAssertEqual(layout.count, 2)
        XCTAssertEqual(layout[0].block?.id, "note")
        XCTAssertEqual(layout[1].block?.id, "following")
    }

    func testProcedureStepLayoutPlacesNestedNoteBeforeItsSubstepsAndMedia() {
        let note = ArticleBlock(id: "note", kind: .note, text: "ПРИМЕЧАНИЕ:")
        let link = ArticleBlock(id: "link", kind: .link, text: "Связанная статья", target: "ru/html/next.html#i010")
        let image = ArticleBlock(id: "image", kind: .image, target: "ru/img/note.png")
        let step = ProcedureStep(id: "step", number: 7, text: "Заполните радиатор.", substeps: ["Первый пункт", "Второй пункт"], supportingBlocks: [note, link, image])

        let layout = ProcedureStepContentLayout.content(for: step)

        XCTAssertEqual(layout.regularSubsteps, [])
        XCTAssertEqual(layout.regularSupportingBlocks, [])
        XCTAssertEqual(layout.note?.supportingBlocks.map(\.kind), [.bulletList, .link, .image])
    }

    func testProcedureStepLayoutRemovesInlineNoteThatIsAlsoStoredAsSupportingBlock() {
        let noteText = "ПРИМЕЧАНИЕ: Надавите отверткой на крюки."
        let step = ProcedureStep(
            id: "step",
            number: 2,
            text: "Снимите крышку камеры LKAS. \(noteText)",
            supportingBlocks: [ArticleBlock(id: "note", kind: .note, text: noteText)]
        )

        let content = ProcedureStepContentLayout.content(for: step)

        XCTAssertEqual(content.stepText, "Снимите крышку камеры LKAS.")
        XCTAssertEqual(content.note?.block.text, noteText)
    }

    func testPDFNoteTextOmitsStandaloneLabelAndRetainsNestedTextAndLinks() {
        let note = ArticleNoteGroup(
            block: ArticleBlock(id: "note", kind: .note, text: "ПРИМЕЧАНИЕ:"),
            supportingBlocks: [
                ArticleBlock(id: "list", kind: .bulletList, items: ["Первый пункт", "Второй пункт"]),
                ArticleBlock(id: "link", kind: .link, text: "Связанная статья", target: "ru/html/next.html#i010")
            ]
        )

        let text = ArticlePDFExporter.noteText(for: note)

        XCTAssertEqual(text, "• Первый пункт\n• Второй пункт\nСвязанная статья  [ru/html/next.html#i010]")
    }

    func testImportedNavigationNoteKeepsItsListLinkAndImageTogether() async throws {
        let loaded = await ManualStore().loadArticle(id: "da3a11a767b80da0")
        let article = try XCTUnwrap(loaded)
        let layout = ArticleContentLayout.blocks(from: article.blocks)
        let note = try XCTUnwrap(layout.compactMap(\.note).first { $0.block.text.uppercased() == "ПРИМЕЧАНИЕ:" })

        XCTAssertEqual(note.supportingBlocks.map(\.kind), [.bulletList, .link, .image])
    }

    func testImportedCoolantProcedureKeepsNoteBeforeItsTwoBullets() async throws {
        let loaded = await ManualStore().loadArticle(id: "8a32ab3a8e586e1a")
        let article = try XCTUnwrap(loaded)
        let step = try XCTUnwrap(article.blocks
            .filter { $0.kind == .numberedSteps }
            .flatMap(\.steps)
            .first {
            $0.supportingBlocks.contains { $0.kind == .note && $0.text.uppercased() == "ПРИМЕЧАНИЕ:" }
            })

        let content = ProcedureStepContentLayout.content(for: step)

        XCTAssertEqual(content.regularSubsteps, [])
        XCTAssertEqual(content.regularSupportingBlocks, [])
        XCTAssertEqual(content.note?.supportingBlocks.first?.items.count, 2)
    }

    func testImportedLKASProcedureShowsInlineNoteOnlyInNoteBlock() async throws {
        let loaded = await ManualStore().loadArticle(id: "79bbe0ee4bd5b5f1")
        let article = try XCTUnwrap(loaded)
        let step = try XCTUnwrap(article.blocks
            .filter { $0.kind == .numberedSteps }
            .flatMap(\.steps)
            .first { $0.text.contains("Снимите крышку камеры LKAS") })

        let content = ProcedureStepContentLayout.content(for: step)

        XCTAssertFalse(content.stepText.localizedCaseInsensitiveContains("примечание"))
        XCTAssertEqual(content.note?.block.text, "ПРИМЕЧАНИЕ: При снятии крышки камеры LKAS надавите отверткой на крюки (В) и выдавите крышку камеры LKAS, затем приподнимите переднюю часть крышки и снимите ее.")
    }

    func testImportedLKASAimingStepShowsInlineNoteInCalloutAfterItsTable() async throws {
        let loaded = await ManualStore().loadArticle(id: "b1b36cbfc5666cde")
        let article = try XCTUnwrap(loaded)
        let step = try XCTUnwrap(article.blocks
            .filter { $0.kind == .numberedSteps }
            .flatMap(\.steps)
            .first { $0.text.contains("Выберите возможное указанное расстояние") })

        let content = ProcedureStepContentLayout.content(for: step)

        XCTAssertFalse(content.stepText.localizedCaseInsensitiveContains("примечание"))
        XCTAssertEqual(content.regularSupportingBlocks.map(\.kind), [.table])
        XCTAssertTrue(content.note?.block.text.localizedCaseInsensitiveContains("указанное расстояние - это расстояние") == true)
    }

    func testProcedureStepWithOnlyInlineNoteStillCreatesNoteCallout() {
        let step = ProcedureStep(
            id: "inline-note-only",
            number: 1,
            text: "Установите шаблон. ПРИМЕЧАНИЕ: Не используйте поврежденный шаблон.",
            substeps: ["Проверьте положение шаблона."],
            supportingBlocks: []
        )

        let content = ProcedureStepContentLayout.content(for: step)

        XCTAssertEqual(content.stepText, "Установите шаблон.")
        XCTAssertEqual(content.note?.block.text, "ПРИМЕЧАНИЕ: Не используйте поврежденный шаблон.")
        XCTAssertEqual(content.regularSubsteps, ["Проверьте положение шаблона."])
    }

    func testCoolantArticlePDFRendersWithNestedNoteContent() async throws {
        let loaded = await ManualStore().loadArticle(id: "8a32ab3a8e586e1a")
        let article = try XCTUnwrap(loaded)

        let data = try ArticlePDFExporter.render(article: article)

        XCTAssertGreaterThan(data.count, 10_000)
        XCTAssertGreaterThanOrEqual(ArticlePDFExporter.pageCount(in: data), 1)
    }

    func testFeedbackConfigurationUsesProvidedContactDetails() {
        XCTAssertEqual(AppConfiguration.supportEmail, "mail@deniskirillov.com")
        XCTAssertEqual(AppConfiguration.telegramUsername, "KirillovDV")
        XCTAssertEqual(URL(string: AppConfiguration.telegramWebURLString)?.absoluteString, "https://t.me/KirillovDV")
    }

    func testLocalDiagnosticReportProducesShareableReadableReport() {
        let report = LocalDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            packageStatus: "SQLite-база открыта",
            packageSize: 1_024,
            metadata: ManualMetadata(formatVersion: 1, importedAt: "2026-08-15T00:00:00Z", sourceTitle: "ACCORD", pageCount: 9_210, imageCount: 14_311, sectionCount: 312, indexedTokenCount: 28_317),
            catalogueArticleCount: 9_210,
            sectionCount: 312,
            mediaFileCount: 14_311,
            diagnostics: [ImportDiagnostic(severity: "warning", path: "ru/img/missing.png", message: "Не найдено изображение")],
            runtimeIssues: []
        )

        let text = report.formattedText

        XCTAssertTrue(text.contains("Локальная диагностика Accord Manual"))
        XCTAssertTrue(text.contains("9 210"))
        XCTAssertTrue(text.contains("Не найдено изображение"))
        XCTAssertTrue(text.contains("SQLite-база открыта"))
    }

    @MainActor
    func testManualStoreCanRerunLocalDiagnostics() {
        let report = ManualStore().runLocalDiagnostics()

        XCTAssertFalse(report.packageStatus.isEmpty)
        XCTAssertGreaterThanOrEqual(report.catalogueArticleCount, 0)
        XCTAssertGreaterThanOrEqual(report.sectionCount, 0)
    }

    @MainActor
    func testNavigationHistoryBackForwardAndBranching() {
        let store = NavigationRouter()
        store.open(articleID: "A")
        store.open(articleID: "B", anchor: "i010")
        store.open(articleID: "C")
        XCTAssertEqual(store.goBack()?.articleID, "B")
        XCTAssertEqual(store.goForward()?.articleID, "C")
        _ = store.goBack()
        store.open(articleID: "D")
        XCTAssertFalse(store.canGoForward)
        XCTAssertEqual(store.currentRoute?.articleID, "D")
    }

    @MainActor
    func testNavigationDoesNotDuplicateCurrentDestination() {
        let store = NavigationRouter()
        store.open(articleID: "A")
        store.open(articleID: "A")
        XCTAssertEqual(store.path.count, 1)
        store.open(articleID: "A", anchor: "i020")
        XCTAssertEqual(store.path.count, 1)
        XCTAssertEqual(store.currentRoute?.anchor, "i020")
    }

    @MainActor
    func testNavigationRetainsArticleReaderStateAcrossBackAndForward() {
        let router = NavigationRouter()
        router.open(articleID: "A")
        router.saveReaderState(articleID: "A", scrollAnchor: "A-block-12", expandedBlockIDs: ["contents"])
        router.open(articleID: "B")

        _ = router.goBack()
        XCTAssertEqual(router.readerState(for: "A")?.scrollAnchor, "A-block-12")
        XCTAssertEqual(router.readerState(for: "A")?.expandedBlockIDs, ["contents"])

        _ = router.goForward()
        XCTAssertEqual(router.currentRoute?.articleID, "B")
        XCTAssertEqual(router.readerState(for: "A")?.scrollAnchor, "A-block-12")
    }
    func testTableLayoutKeepsColumnsOccupiedByRowSpan() {
        let rows = [
            [ManualTableCell(text: "A", rowSpan: 2), ManualTableCell(text: "B")],
            [ManualTableCell(text: "C")]
        ]
        let layout = TableLayout.rows(from: rows)
        XCTAssertEqual(layout[0].reduce(0) { $0 + $1.columnSpan }, 2)
        XCTAssertNil(layout[1][0].cell)
        XCTAssertEqual(layout[1][1].cell?.text, "C")
    }
    func testSearchFindsRussianTitleCaseInsensitively() async {
        let store = ManualStore()
        let results = await store.search("p0300")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.article.plainText.localizedCaseInsensitiveContains("P0300") })
    }

    func testCatalogueHidesTechnicalZoomAndSeaVariantsButOriginalPathsResolve() async throws {
        let store = ManualStore()

        XCTAssertFalse(store.articles.isEmpty)
        XCTAssertFalse(store.articles.contains {
            let name = URL(fileURLWithPath: $0.sourcePath).deletingPathExtension().lastPathComponent.uppercased()
            return name.hasPrefix("ZOOM") || name.hasPrefix("SEA")
        })

        let loadedCanonical = await store.loadArticle(id: "cad850d9bdd535fd")
        let canonical = try XCTUnwrap(loadedCanonical)
        XCTAssertEqual(canonical.sourcePath, "ru/html/000000000000184.html")
        XCTAssertFalse(canonical.title.localizedCaseInsensitiveContains("лист 000000000000184"))

        let technicalVariant = try XCTUnwrap(store.article(path: "ru/html/ZOOM000000000000548.html"))
        XCTAssertEqual(technicalVariant.sourcePath, "ru/html/ZOOM000000000000548.html")
    }

    func testVehicleFilterKeepsUniversalArticle() async {
        let universal = ManualArticle(id: "universal", esmKey: nil, title: "Общее", breadcrumbs: ["Руководство"], sourcePath: "page.html", blocks: [], plainText: "", links: [], images: [], applicability: Applicability(years: [], bodyCodes: [], engineCodes: [], transmissions: []), relatedArticleIDs: [])
        XCTAssertTrue(ManualStore.matches(universal, filters: SearchFilters(bodyCode: "CL7"), savedIDs: []))
    }

    func testVehicleProfilePrioritisesCompatibleArticle() {
        let compatible = ManualArticle(id: "cl9", esmKey: nil, title: "CL9", breadcrumbs: ["Руководство"], sourcePath: "cl9.html", blocks: [], plainText: "", links: [], images: [], applicability: Applicability(years: [2006], bodyCodes: ["CL9"], engineCodes: ["K24A3"], transmissions: ["AT"]), relatedArticleIDs: [])
        let incompatible = ManualArticle(id: "cl7", esmKey: nil, title: "CL7", breadcrumbs: ["Руководство"], sourcePath: "cl7.html", blocks: [], plainText: "", links: [], images: [], applicability: Applicability(years: [2003], bodyCodes: ["CL7"], engineCodes: ["K20A6"], transmissions: ["MT"]), relatedArticleIDs: [])
        let profile = SearchFilters(year: 2006, bodyCode: "CL9", engineCode: "K24A3", transmission: "AT")
        XCTAssertGreaterThan(ManualStore.compatibilityScore(compatible, preference: profile), ManualStore.compatibilityScore(incompatible, preference: profile))
    }

    func testImportedFrontGrilleProcedureKeepsThreeNumberedStepsWithImagesAndSubsteps() async throws {
        let store = ManualStore()
        let loadedArticle = await store.loadArticle(id: "d354e7c9fa53e5ce")
        let article = try XCTUnwrap(loadedArticle)
        let procedure = try XCTUnwrap(article.blocks.first { $0.kind == .numberedSteps })

        XCTAssertEqual(procedure.steps.map(\.number), [1, 2, 3])
        XCTAssertEqual(procedure.steps.count, 3)
        XCTAssertEqual(procedure.steps[0].supportingBlocks.map(\.target), ["ru/img/SEA3E00J18573430201KBRD60.PNG"])
        XCTAssertEqual(procedure.steps[2].supportingBlocks.map(\.target), ["ru/img/SEA3E00J18573430201KBRD02.PNG"])
        XCTAssertEqual(procedure.steps[2].substeps, [
            "Замените все поврежденные фиксаторы.",
            "Надежно зацепите крючки передней решетки на место."
        ])
    }

    func testImportedRadiatorProcedureKeepsCompanionDiagramInArticleFlow() async throws {
        let store = ManualStore()
        let loadedArticle = await store.loadArticle(id: "b2def4f19f450b1e")
        let article = try XCTUnwrap(loadedArticle)
        let procedureIndex = try XCTUnwrap(article.blocks.firstIndex { $0.kind == .numberedSteps })
        let procedure = article.blocks[procedureIndex]

        XCTAssertEqual(procedure.steps.map(\.number), Array(1...9))
        XCTAssertTrue(procedure.steps.allSatisfy { step in
            step.supportingBlocks.allSatisfy { $0.kind != .image }
        })
        XCTAssertEqual(article.blocks.dropFirst(procedureIndex + 1).first?.kind, .image)
        XCTAssertEqual(
            article.blocks.dropFirst(procedureIndex + 1).first?.target,
            "ru/img/SEA5E13A14400049001KBRD01.PNG"
        )
    }

    func testDiagramAspectFitIsCenteredInPortraitViewport() {
        let frame = DiagramGeometry.aspectFit(
            canvas: CGSize(width: 950, height: 959),
            in: CGRect(x: 0, y: 0, width: 390, height: 600)
        )

        XCTAssertEqual(frame.minX, 0, accuracy: 0.01)
        XCTAssertEqual(frame.width, 390, accuracy: 0.01)
        XCTAssertEqual(frame.height, 393.69, accuracy: 0.01)
        XCTAssertEqual(frame.midY, 300, accuracy: 0.01)
    }

    func testViewerLayoutFitsTallDiagramAboveBottomControlsInPortrait() {
        let layout = DiagramGeometry.viewerLayout(
            canvas: CGSize(width: 950, height: 1_087),
            container: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            bottomBarHeight: 64
        )

        XCTAssertTrue(layout.artworkViewport.contains(layout.fitFrame))
        XCTAssertTrue(layout.safeBounds.contains(layout.bottomBarFrame))
        XCTAssertLessThanOrEqual(layout.fitFrame.maxY, layout.bottomBarFrame.minY)
        XCTAssertEqual(layout.fitFrame.width, 390, accuracy: 0.01)
        XCTAssertEqual(layout.fitFrame.height, 446.24, accuracy: 0.01)
    }

    func testViewerLayoutFitsWideDiagramAndKeepsControlBarInsideLandscapeSafeArea() {
        let layout = DiagramGeometry.viewerLayout(
            canvas: CGSize(width: 1_600, height: 900),
            container: CGRect(x: 0, y: 0, width: 844, height: 390),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59),
            bottomBarHeight: 64
        )

        XCTAssertTrue(layout.artworkViewport.contains(layout.fitFrame))
        XCTAssertTrue(layout.safeBounds.contains(layout.bottomBarFrame))
        XCTAssertEqual(layout.fitFrame.width, 542.22, accuracy: 0.01)
        XCTAssertEqual(layout.fitFrame.height, 305, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(layout.bottomBarFrame.minY, layout.safeBounds.minY)
    }

    func testPhotoViewerLayoutKeepsArtworkBetweenSafeAreaChrome() {
        let layout = DiagramGeometry.viewerLayout(
            canvas: CGSize(width: 950, height: 1_087),
            container: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            topBarHeight: 56,
            bottomBarHeight: 64
        )

        XCTAssertTrue(layout.safeBounds.contains(layout.topBarFrame))
        XCTAssertTrue(layout.safeBounds.contains(layout.bottomBarFrame))
        XCTAssertGreaterThanOrEqual(layout.artworkViewport.minY, layout.topBarFrame.maxY)
        XCTAssertLessThanOrEqual(layout.artworkViewport.maxY, layout.bottomBarFrame.minY)
        XCTAssertTrue(layout.artworkViewport.contains(layout.fitFrame))
    }

    func testViewerProjectedOffsetUsesPredictedDragAndRemainsInsideDiagram() {
        let offset = DiagramGeometry.projectedOffset(
            start: .zero,
            translation: CGSize(width: 80, height: 60),
            predictedTranslation: CGSize(width: 500, height: 500),
            contentSize: CGSize(width: 1_000, height: 1_000),
            viewport: CGSize(width: 390, height: 600)
        )

        XCTAssertEqual(offset.width, 305, accuracy: 0.01)
        XCTAssertEqual(offset.height, 200, accuracy: 0.01)
    }

    func testDiagramOriginalScaleNeverDownsamplesCanvas() {
        let size = DiagramGeometry.contentSize(
            canvas: CGSize(width: 950, height: 959),
            viewport: CGSize(width: 390, height: 600),
            zoomScale: 1
        )

        XCTAssertEqual(size.width, 950, accuracy: 0.01)
        XCTAssertEqual(size.height, 959, accuracy: 0.01)
    }

    func testDiagramNativeRasterScaleMapsOneSourcePixelToOneDevicePixel() {
        let nativeScale = DiagramGeometry.nativeRasterScale(
            sourceCanvas: CGSize(width: 950, height: 545),
            rasterPixels: CGSize(width: 950, height: 545),
            displayScale: 3
        )

        XCTAssertEqual(nativeScale.width, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(nativeScale.height, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testDiagramNativeRasterScalePreservesSourceCoordinatesForLargerOriginal() {
        let nativeScale = DiagramGeometry.nativeRasterScale(
            sourceCanvas: CGSize(width: 950, height: 545),
            rasterPixels: CGSize(width: 1_900, height: 1_090),
            displayScale: 2
        )

        XCTAssertEqual(nativeScale.width, 1, accuracy: 0.0001)
        XCTAssertEqual(nativeScale.height, 1, accuracy: 0.0001)
    }

    func testAnnotationFontScalesWithDiagramWithoutArtificialMinimum() {
        let size = DiagramGeometry.annotationFontSize(sourcePoints: 8.69, renderScale: 390 / 950)

        XCTAssertEqual(size, 4.76, accuracy: 0.01)
        XCTAssertLessThan(size, 7)
    }

    func testAnnotationCollisionResolverKeepsLabelsVisibleAndSeparate() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
        let proposed = [
            CGRect(x: 180, y: 6, width: 42, height: 20),
            CGRect(x: 178, y: 10, width: 48, height: 20),
            CGRect(x: -12, y: 104, width: 60, height: 24)
        ]

        let resolved = DiagramGeometry.resolveCollisions(proposed, within: bounds, spacing: 2)

        XCTAssertEqual(resolved.count, proposed.count)
        XCTAssertTrue(resolved.allSatisfy { bounds.contains($0) })
        for left in resolved.indices {
            for right in resolved.indices where right > left {
                XCTAssertFalse(resolved[left].intersects(resolved[right]))
            }
        }
    }

    func testDiagramLinkFrameRetainsImportedSourceCoordinates() {
        let link = ImageAnnotationLink(
            text: "Регулировка положения,",
            target: "ru/html/000000000000134.html#i000",
            x: 668,
            y: 252.4,
            width: 142,
            height: 13.9,
            lineIndex: 1
        )

        let frame = DiagramGeometry.sourceLinkFrame(link)

        XCTAssertEqual(frame, CGRect(x: 668, y: 252.4, width: 142, height: 13.9))
    }

    func testDiagramLinkHitTestingUsesSourceCanvasCoordinates() {
        let link = ImageAnnotationLink(text: "Замена,", target: "ru/html/000000000000142.html#i000", x: 407, y: 474.9, width: 54, height: 13.9, lineIndex: 1)

        XCTAssertEqual(DiagramGeometry.link(at: CGPoint(x: 430, y: 480), in: [link])?.id, link.id)
        XCTAssertNil(DiagramGeometry.link(at: CGPoint(x: 462, y: 480), in: [link]))
    }

    func testTooltipPlacementStaysInsideNarrowViewportAtEveryEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 480)
        let tooltipSize = CGSize(width: 280, height: 96)
        let anchors = [
            CGRect(x: 0, y: 0, width: 20, height: 20),
            CGRect(x: 300, y: 0, width: 20, height: 20),
            CGRect(x: 0, y: 460, width: 20, height: 20),
            CGRect(x: 300, y: 460, width: 20, height: 20)
        ]

        for anchor in anchors {
            let frame = TooltipPlacement.frame(anchor: anchor, tooltipSize: tooltipSize, viewport: viewport)
            XCTAssertGreaterThanOrEqual(frame.minX, 12)
            XCTAssertGreaterThanOrEqual(frame.minY, 12)
            XCTAssertLessThanOrEqual(frame.maxX, 308)
            XCTAssertLessThanOrEqual(frame.maxY, 468)
        }
    }

    func testBodyConstructionDiagramAnnotationsFitCanvasWithoutCollisions() async throws {
        let store = ManualStore()
        let loadedArticle = await store.loadArticle(id: "e0f1d9553589ca92")
        let article = try XCTUnwrap(loadedArticle)
        let image = try XCTUnwrap(article.images.first)
        let canvas = CGSize(
            width: try XCTUnwrap(image.canvasWidth),
            height: try XCTUnwrap(image.canvasHeight)
        )
        let frames = DiagramGeometry.annotationFrames(image.annotations, canvas: canvas)
        let bounds = CGRect(origin: .zero, size: canvas)

        XCTAssertEqual(frames.count, 127)
        XCTAssertTrue(frames.allSatisfy { bounds.contains($0) })
        for (annotation, frame) in zip(image.annotations, frames) {
            let fontSize = max(CGFloat(annotation.fontSize ?? 7), 1)
            let measuredHeight = (annotation.text as NSString).boundingRect(
                with: CGSize(width: frame.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: fontSize)],
                context: nil
            ).integral.height
            XCTAssertGreaterThanOrEqual(frame.height, measuredHeight, "Аннотация \(annotation.text) выходит за свою область")
        }
        for left in frames.indices {
            for right in frames.indices where right > left {
                XCTAssertFalse(frames[left].intersects(frames[right]), "Аннотации \(left) и \(right) пересекаются")
            }
        }
    }

    func testArticlePDFExportCreatesPDFWithRealDiagram() async throws {
        let store = ManualStore()
        let loaded = await store.loadArticle(id: "e0f1d9553589ca92")
        let article = try XCTUnwrap(loaded)

        let data = try ArticlePDFExporter.render(article: article)

        XCTAssertGreaterThan(data.count, 20_000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
        XCTAssertGreaterThanOrEqual(ArticlePDFExporter.pageCount(in: data), 1)
    }

    func testArticlePDFExportUsesSafeFilename() {
        XCTAssertEqual(ArticlePDFExporter.fileName(for: "Проверка / ABS: CL7?"), "Проверка-ABS-CL7.pdf")
    }
}
