#if canImport(XCTest)
import XCTest
import SQLite3
@testable import ManualImporter

final class ManualImporterTests: XCTestCase {
    func testPreservesDecisionLabelsAndInArticleJmpLink() throws {
        let html = """
        <p>Код DTC B1000 высветился на экране?</p>
        <table class="Viewer" frame="void" style="margin-left:50px;">
          <tr><td width="30" class="ViewerTD"><b>ДА</b></td><td width="10" class="ViewerTD" align="center">-</td><td class="ViewerTD"><div>Перейдите к <a href="javascript:parent.Jmp('i040')">Этап 4</a>.</div></td></tr>
          <tr><td width="30" class="ViewerTD"><b>НЕТ</b></td><td width="10" class="ViewerTD" align="center">-</td><td class="ViewerTD"><div>Пропадающая неисправность.</div></td></tr>
        </table>
        <a name="i040"></a><ol><li value="4">Проверьте цепь.</li></ol>
        """

        XCTAssertEqual(
            LinkNormalizer.target("javascript:parent.Jmp('i040')", from: "ru/html/b1000.html"),
            "ru/html/b1000.html#i040"
        )

        let article = try HTMLArticleParser.parse(
            html: html,
            id: "b1000",
            title: "Коды поиска неисправностей (DTC): B1000",
            breadcrumbs: [],
            sourcePath: "ru/html/b1000.html"
        )

        XCTAssertTrue(article.blocks.contains { $0.text.contains("ДА") && $0.text.contains("Перейдите к") })
        XCTAssertTrue(article.blocks.contains { $0.text.contains("НЕТ") && $0.text.contains("Пропадающая неисправность") })
        let inlineLink = try XCTUnwrap(article.blocks.first { $0.text.contains("ДА") }?.inlineLinks.first)
        XCTAssertEqual(inlineLink.text, "Этап 4")
        XCTAssertEqual(inlineLink.target, "ru/html/b1000.html#i040")
        XCTAssertEqual(article.blocks.first { $0.kind == .numberedSteps }?.steps.first?.anchors, ["i040"])
    }

    func testKeepsZoomVariantForOriginalLinkButExcludesItFromCatalogueAndSearch() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        <contents_list><contents key="000000000000001" title="Замена противотуманной фары"><base_sie><sct>0</sct><sc>000</sc></base_sie></contents></contents_list>
        """.write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try """
        <title>Замена противотуманной фары</title>
        <a href="javascript:PrtProc('0','ZOOM000000000000001','1')"><img src="../img/fog.PNG"></a>
        <p>Основная процедура.</p>
        """.write(to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8)
        try """
        <title>ZOOM000000000000001</title><div class="top_title">Замена противотуманной фары</div><p>Технический вариант для просмотра.</p>
        """.write(to: root.appendingPathComponent("ru/html/ZOOM000000000000001.html"), atomically: true, encoding: .utf8)

        let report = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let package = try loadSQLitePackage(at: output)
        XCTAssertEqual(report.metadata.pageCount, 1)
        XCTAssertEqual(package.articles.count, 2)
        XCTAssertEqual(
            package.articles.first(where: { $0.sourcePath == "ru/html/000000000000001.html" })?.title,
            "Замена противотуманной фары"
        )

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(output.appendingPathComponent("manual.sqlite").path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT is_service FROM articles WHERE source_path='ru/html/ZOOM000000000000001.html'", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)

        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT count(*) FROM article_fts WHERE article_fts MATCH 'технический'", -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
    }

    func testCombinesSplitOrderedListsIntoOneProcedureWithSourceNumbersAndStepImages() throws {
        let html = """
        <div>ПРИМЕЧАНИЕ:</div>
        <ol><li value="1"><div>Снимите верхние фиксаторы.</div></li></ol>
        <img src="../img/step-one.PNG">
        <a name="i020"></a>
        <ol><li value="2"><div>Снимите решетку.</div></li></ol>
        <a name="i030"></a>
        <ol><li value="3"><div>Установите решетку в обратном порядке.</div><ul><li><div>Замените поврежденные фиксаторы.</div></li><li><div>Зацепите крючки.</div></li></ul></li></ol>
        <img src="../img/step-three.PNG">
        """

        let article = try HTMLArticleParser.parse(
            html: html,
            id: "grille",
            title: "Замена передней решетки",
            breadcrumbs: [],
            sourcePath: "ru/html/grille.html"
        )

        let procedure = try XCTUnwrap(article.blocks.first { $0.kind == .numberedSteps })
        XCTAssertEqual(article.blocks.filter { $0.kind == .numberedSteps }.count, 1)
        XCTAssertEqual(procedure.steps.map(\.number), [1, 2, 3])
        XCTAssertEqual(procedure.steps.map(\.text), [
            "Снимите верхние фиксаторы.",
            "Снимите решетку.",
            "Установите решетку в обратном порядке."
        ])
        XCTAssertEqual(procedure.steps[0].supportingBlocks.map(\.target), ["ru/img/step-one.PNG"])
        XCTAssertEqual(procedure.steps[2].substeps, ["Замените поврежденные фиксаторы.", "Зацепите крючки."])
        XCTAssertEqual(procedure.steps[2].supportingBlocks.map(\.target), ["ru/img/step-three.PNG"])
        XCTAssertEqual(procedure.steps[1].anchors, ["i020"])
        XCTAssertEqual(procedure.steps[2].anchors, ["i030"])
    }

    func testKeepsLayoutTableCompanionImageInlineAfterWholeProcedure() throws {
        let html = """
        <table class="Viewer"><tr>
          <td id="textTd"><ol><li value="1">Первый шаг.</li></ol><ol><li value="2">Второй шаг.</li></ol><ol><li value="3">Третий шаг.</li></ol></td>
          <td id="graphTd"><a href="javascript:PrtProc('0','ZOOM000000000000001','1')"><img src="../img/radiator.PNG"></a></td>
        </tr></table>
        """

        let article = try HTMLArticleParser.parse(
            html: html,
            id: "radiator",
            title: "Замена радиатора и вентилятора",
            breadcrumbs: [],
            sourcePath: "ru/html/radiator.html"
        )

        let procedureIndex = try XCTUnwrap(article.blocks.firstIndex { $0.kind == .numberedSteps })
        XCTAssertEqual(article.blocks[procedureIndex].steps.map(\.number), [1, 2, 3])
        XCTAssertTrue(article.blocks[procedureIndex].steps.allSatisfy { $0.supportingBlocks.isEmpty })
        let following = article.blocks.dropFirst(procedureIndex + 1).first
        XCTAssertEqual(following?.kind, .image)
        XCTAssertEqual(following?.target, "ru/img/radiator.PNG")
    }

    func testPreservesSemanticViewerTableWithHeadersAndSpans() throws {
        let html = """
        <table class="Viewer" frame="box">
          <tr><th rowspan="2">Позиция</th><th colspan="2">Допуск</th></tr>
          <tr><th>мм</th><th>дюйм</th></tr>
          <tr><td>Зазор клапана</td><td>0,21–0,25</td><td>0.008–0.010</td></tr>
        </table>
        """
        let article = try HTMLArticleParser.parse(html: html, id: "table", title: "", breadcrumbs: [], sourcePath: "ru/html/table.html")
        let table = try XCTUnwrap(article.blocks.first { $0.kind == .table })

        XCTAssertEqual(table.tableRows.count, 3)
        XCTAssertEqual(table.tableRows[0][0].text, "Позиция")
        XCTAssertEqual(table.tableRows[0][0].rowSpan, 2)
        XCTAssertEqual(table.tableRows[0][1].columnSpan, 2)
        XCTAssertTrue(table.tableRows[0][0].isHeader)
        XCTAssertEqual(table.tableRows[2].map(\.text), ["Зазор клапана", "0,21–0,25", "0.008–0.010"])
    }

    func testDoesNotEmitSemanticTableCellsAsDuplicateParagraphs() throws {
        let html = """
        <table class="Viewer" frame="box">
          <tr><th><div>Номер предохранителя</div></th><th><div>Сила тока</div></th></tr>
          <tr><td><div>1</div></td><td><div>7,5 A</div></td></tr>
        </table>
        <p>Текст после таблицы.</p>
        """

        let article = try HTMLArticleParser.parse(html: html, id: "fuses", title: "", breadcrumbs: [], sourcePath: "ru/html/fuses.html")

        XCTAssertEqual(article.blocks.map(\.kind), [.table, .paragraph])
        XCTAssertEqual(article.blocks.last?.text, "Текст после таблицы.")
    }

    func testRemovesEarlyCellsWhenTableBecomesStructuralOnlyInALaterRow() throws {
        let html = """
        <table class="Viewer" frame="void">
          <tr><td><div>ABS</div></td><td><div>Антиблокировочная тормозная система</div></td></tr>
          <tr><td rowspan="2"><div>ACL</div></td><td><div>Воздухоочиститель</div></td></tr>
        </table>
        <p>Текст после таблицы.</p>
        """

        let article = try HTMLArticleParser.parse(html: html, id: "abbreviations", title: "", breadcrumbs: [], sourcePath: "ru/html/abbreviations.html")

        XCTAssertEqual(article.blocks.map(\.kind), [.table, .paragraph])
        XCTAssertEqual(article.blocks[0].tableRows.flatMap { $0.map(\.text) }, [
            "ABS", "Антиблокировочная тормозная система", "ACL", "Воздухоочиститель"
        ])
        XCTAssertEqual(article.blocks[1].text, "Текст после таблицы.")
    }

    func testDoesNotPromoteOuterViewerLayoutTableToContentTable() throws {
        let html = """
        <table width="100%" class="Viewer"><tr><td id="textTd">
          <p>Инструкция</p>
          <table class="Viewer" frame="box"><tr><td>Параметр</td><td>Значение</td></tr></table>
        </td></tr></table>
        """
        let article = try HTMLArticleParser.parse(html: html, id: "layout", title: "", breadcrumbs: [], sourcePath: "ru/html/layout.html")
        let tables = article.blocks.filter { $0.kind == .table }
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0].tableRows[0].map(\.text), ["Параметр", "Значение"])
    }

    func testImporterRestoresPositionedAnnotationsFromDiagramScript() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/js"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/img"), withIntermediateDirectories: true)
        try "<title>Схема</title><div><script src='../js/diagram.js'></script></div>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )
        try """
        with(document) {
        write("<v:group style=\"position:relative;width:950px;height:1113px;\" coordsize=\"950,1113\">");
        write("<img src=\"../img/diagram.PNG\" style=\"position:absolute;left:0px;top:0px;width:950px;height:1113px;\">");
        write("<p style=\"position:absolute;left:850px;top:285px;font-size:6.51pt;\"><nobr><b>ДАТЧИК IAT<br><a href=\\\"javascript:CtsProc('0','000000000000042','i010')\\\"></b>Замена,</a></nobr></p>");
        write("</v:group>");
        }
        """.write(to: root.appendingPathComponent("ru/js/diagram.js"), atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("ru/img/diagram.PNG"))

        _ = try ESMImporter().importManual(input: root, output: output)
        let image = try XCTUnwrap(loadSQLitePackage(at: output).articles.first?.images.first)
        XCTAssertEqual(image.canvasWidth, 950)
        XCTAssertEqual(image.canvasHeight, 1113)
        XCTAssertEqual(image.annotations.count, 1)
        XCTAssertEqual(image.annotations[0].text, "ДАТЧИК IAT Замена,")
        XCTAssertEqual(image.annotations[0].x, 850, accuracy: 0.01)
        XCTAssertEqual(image.annotations[0].y, 285, accuracy: 0.01)
        XCTAssertEqual(image.annotations[0].links.map(\.text), ["Замена,"])
        XCTAssertEqual(image.annotations[0].links.map(\.target), ["ru/html/000000000000042.html#i010"])
        XCTAssertEqual(image.annotations[0].lines, ["ДАТЧИК IAT", "Замена,"])
        let link = try XCTUnwrap(image.annotations[0].links.first)
        XCTAssertEqual(link.x, 850, accuracy: 0.01)
        XCTAssertGreaterThan(link.y, 285)
        XCTAssertGreaterThan(link.width, 0)
        XCTAssertGreaterThan(link.height, 0)
        let blocks = try XCTUnwrap(loadSQLitePackage(at: output).articles.first).blocks
        XCTAssertFalse(blocks.contains { $0.kind == .link })
        XCTAssertEqual(blocks.map(\.kind), [.image])
    }
    func testNormalisesLocalRelativeLinksAndRemovesFragments() {
        XCTAssertEqual(LinkNormalizer.normalized("../brakes/abs.html#sensor", from: "manual/chassis/index.html"), "manual/brakes/abs.html")
    }

    func testResolvesHondaCtsJavaScriptLinkWithItsAnchor() {
        XCTAssertEqual(
            LinkNormalizer.target("javascript:CtsProc('0','000000000003819','i120')", from: "ru/html/000000000007927.html"),
            "ru/html/000000000003819.html#i120"
        )
    }

    func testExtractsHondaCtsLinkNestedInsideTable() throws {
        let html = "<table><tr><td><a href=\"javascript:CtsProc('0','000000000003819','i120')\">Проверка датчика</a></td></tr></table>"
        let result = try HTMLArticleParser.parse(html: html, id: "links", title: "", breadcrumbs: [], sourcePath: "ru/html/000000000007927.html")
        XCTAssertEqual(result.blocks.last?.kind, .link)
        XCTAssertEqual(result.blocks.last?.target, "ru/html/000000000003819.html#i120")
        XCTAssertEqual(result.links, ["ru/html/000000000003819.html"])
    }

    func testPreservesTextLinkNestedInsideProcedureStep() throws {
        let html = """
        <ol><li><div>Перед началом <a href="javascript:CtsProc('0','000000000000001','i010')">установите страхующие опоры</a>.</div></li></ol>
        """
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "procedure-link",
            title: "Процедура",
            breadcrumbs: [],
            sourcePath: "ru/html/000000000000012.html"
        )

        let procedure = try XCTUnwrap(result.blocks.first { $0.kind == .numberedSteps })
        let link = try XCTUnwrap(procedure.steps.first?.supportingBlocks.first { $0.kind == .link })
        XCTAssertEqual(link.text, "установите страхующие опоры")
        XCTAssertEqual(link.target, "ru/html/000000000000001.html#i010")
    }

    func testInlineJavaScriptWithComparisonOperatorDoesNotSwallowFollowingArticleContent() throws {
        let html = """
        <script>if (width < 720) { document.title = 'compact'; }</script>
        <div>Видимая инструкция</div>
        <a href="javascript:PrtProc('2','ZOOM000000000000002')">Манометр давления</a>
        """
        let result = try HTMLArticleParser.parse(html: html, id: "script", title: "", breadcrumbs: [], sourcePath: "ru/html/page.html")
        XCTAssertTrue(result.plainText.contains("Видимая инструкция"))
        XCTAssertEqual(result.blocks.first { $0.kind == .link }?.text, "Манометр давления")
        XCTAssertEqual(result.blocks.first { $0.kind == .link }?.target, "ru/html/ZOOM000000000000002.html")
    }

    func testTreatsLegacyOnLoadRootContainerAsVisibleButKeepsNestedPrintDuplicateHidden() throws {
        let html = """
        <body onload="showBody()">
          <div id="divBody" style="display:none">
            <div>Основной текст</div>
            <img src="../img/original.png">
            <span id="imgPrtId" style="display:none"><img src="../img/duplicate.png"></span>
          </div>
        </body>
        """
        let result = try HTMLArticleParser.parse(html: html, id: "dynamic", title: "", breadcrumbs: [], sourcePath: "ru/html/zoom.html")
        XCTAssertTrue(result.plainText.contains("Основной текст"))
        XCTAssertEqual(result.images.map(\.localRelativePath), ["ru/img/original.png"])
    }

    func testDecodesNestedHTMLEntitiesInVisibleText() throws {
        let result = try HTMLArticleParser.parse(html: "<div>Цепь &amp;quot;массы&amp;quot;</div>", id: "entities", title: "", breadcrumbs: [], sourcePath: "ru/html/page.html")
        XCTAssertEqual(result.plainText, "Цепь \"массы\"")
    }

    func testPreservesAnchorNestedInsideLegacyTable() throws {
        let html = "<table><tr><td><a name='iG10'></a><p>Диагностика</p></td></tr></table>"
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "nested-anchor",
            title: "Диагностика",
            breadcrumbs: [],
            sourcePath: "ru/html/000000000005004.html"
        )

        XCTAssertEqual(result.blocks.filter { $0.kind == .anchor }.map(\.anchor), ["iG10"])
    }

    func testRejectsHondaCtsLinkWithoutDestinationKey() {
        XCTAssertNil(LinkNormalizer.target("javascript:CtsProc('0','','i000')", from: "ru/html/page.html"))
    }

    func testRejectsHondaJumpLinkWithoutDestinationPage() {
        XCTAssertNil(LinkNormalizer.target("javascript:JumpFunc('.html#i160')", from: "ru/html/page.html"))
    }

    func testIndexesRussianAndTechnicalCodes() {
        let tokens = SearchTokenizer.tokens(in: "Проверка датчика ABS K24A, ошибка P0420")
        XCTAssertTrue(tokens.contains("проверка")); XCTAssertTrue(tokens.contains("abs")); XCTAssertTrue(tokens.contains("k24a")); XCTAssertTrue(tokens.contains("p0420"))
    }

    func testBuildsStableSectionTreeFromArticleBreadcrumbs() {
        let article = ImportedArticle(id: "abs-sensor", title: "Проверка датчика", breadcrumbs: ["Руководство", "Тормоза", "ABS"], sourcePath: "brakes/abs.html", blocks: [], plainText: "", links: [], images: [], esmKey: nil)
        let tree = SectionTreeBuilder.build(from: [article])
        XCTAssertEqual(tree.first?.children.first?.title, "Тормоза")
        XCTAssertEqual(tree.first?.children.first?.children.first?.title, "ABS")
    }

    func testImporterClassifiesZeroCodeGeneralInformationLikeOriginalNavigation() throws {
        let article = try importedArticle(sct: "0", sc: "000", sys: "000", comp: "K0041", sitq: "BA", title: "Опорные точки для подъема")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Общая информация"])
    }

    func testImporterClassifiesZeroCodeElectricalSchematicsLikeOriginalNavigation() throws {
        let article = try importedArticle(sct: "0", sc: "000", sys: "000", sitq: "EB", title: "Схема электропроводки")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Схемы электропроводки"])
    }

    func testImporterClassifiesZeroCodeMaintenanceLikeOriginalNavigation() throws {
        let article = try importedArticle(sct: "0", sc: "000", sys: "000", sitq: "JB", title: "Расписание обслуживания")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "График техобслуживания", "Техобслуживание"])
    }

    func testImporterOmitsNonApplicableSubsectionFromRealSection() throws {
        let article = try importedArticle(sct: "F", sc: "000", sys: "000", sitq: "DA", title: "Перечень расположения элементов гидроусилителя руля")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Рулевое управление"])
    }

    func testImporterPreservesRealSystemLevelFromOriginalNavigation() throws {
        let article = try importedArticle(sct: "A", sc: "144", sys: "261", sitq: "DA", title: "Перечень компонентов вентилятора")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Двигатель", "Система охлаждения", "Управление вентилятором"])
    }

    func testImporterClassifiesBodyRepairManualSectionLikeOriginalNavigation() throws {
        let article = try importedArticle(sct: "R", sc: "311", sys: "000", sitq: "YD", title: "Замена панели кузова")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Ремонт кузова", "Замена"])
    }

    func testImporterMovesSpecificationsAboveMechanicalClassificationLikeOriginalNavigation() throws {
        let article = try importedArticle(sct: "A", sc: "144", sys: "000", sitq: "NA", title: "Технические характеристики системы охлаждения")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Спецификация", "Стандарты и сроки эксплуатации", "Двигатель", "Система охлаждения"])
    }

    func testImporterMakesFuelAndEmissionsASeparateOriginalTopLevelSection() throws {
        let article = try importedArticle(sct: "A", sc: "203", sys: "264", sitq: "DA", title: "Перечень компонентов топливной системы")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Топливо и система снижения токсичности", "Система питания топливом"])
    }

    func testImporterUsesOriginalDTCSectionName() throws {
        let article = try importedArticle(sct: "K", sc: "721", sys: "000", sitq: "FA", title: "DTC P0420")
        XCTAssertEqual(article.breadcrumbs, ["Руководство", "Поиск неисправностей DTC", "ЕСМ"])
    }

    func testImporterInheritsSectionForReadableLinkedZoomArticle() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <sct_sc_name_list><sct_name code="D" name="Тормозная система"><sc_name code="143" name="Стандартные компонеты тормозной системы"></sc_name></sct_name></sct_sc_name_list>
        """.write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try """
        <contents_list><contents key="000000000000001" title="Осмотр тормозных колодок"><base_sie>
          <sct>D</sct><sc>143</sc><sys>000</sys><comp>00000</comp><sitq>MA</sitq>
        </base_sie></contents></contents_list>
        """.write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>Осмотр тормозных колодок</title><a href=\"javascript:PrtProc('2','ZOOM000000000000002')\">Увеличенная схема</a>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )
        try "<title>ZOOM000000000000002</title><div class='top_title'>Осмотр и замена тормозной колодки</div>".write(
            to: root.appendingPathComponent("ru/html/ZOOM000000000000002.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let zoom = try XCTUnwrap(loadSQLitePackage(at: output).articles.first { $0.sourcePath.contains("ZOOM") })
        XCTAssertEqual(zoom.breadcrumbs, ["Руководство", "Тормозная система", "Стандартные компонеты тормозной системы"])
    }

    func testImporterDisambiguatesRepeatedTitlesUsingArticleContentAndModelMetadata() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <contents_list>
          <contents key="000000000000001" title="Схема электропроводки"><base_sie><sct>0</sct><sc>000</sc><sys>000</sys><comp>00000</comp><sitq>EB</sitq></base_sie></contents>
          <contents key="000000000000002" title="Схема электропроводки"><base_sie><sct>0</sct><sc>000</sc><sys>000</sys><comp>00000</comp><sitq>EB</sitq></base_sie></contents>
        </contents_list>
        """.write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>Схема электропроводки</title><p>Система PGM-FI</p><p>Блок ECM</p>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )
        try "<title>Схема электропроводки</title><p>Система наружного освещения</p><p>Левая фара</p>".write(
            to: root.appendingPathComponent("ru/html/000000000000002.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let titles = try loadSQLitePackage(at: output).articles.map(\.title)

        XCTAssertEqual(titles, [
            "Схема электропроводки — Система PGM-FI",
            "Схема электропроводки — Система наружного освещения"
        ])
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testImporterInheritsSectionForUnlinkedZoomCopyWithSameCatalogueTitle() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <sct_sc_name_list><sct_name code="J" name="Кузов"><sc_name code="362" name="Навигация/TV"></sc_name></sct_name></sct_sc_name_list>
        """.write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try """
        <contents_list><contents key="000000000000001" title="Поиск неисправностей системы навигации"><base_sie>
          <sct>J</sct><sc>362</sc><sys>000</sys><comp>00000</comp><sitq>FA</sitq>
        </base_sie></contents></contents_list>
        """.write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>Поиск неисправностей системы навигации</title>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )
        try "<title>ZOOM000000000000002</title><div class='top_title'>Поиск неисправностей системы навигации</div>".write(
            to: root.appendingPathComponent("ru/html/ZOOM000000000000002.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let zoom = try XCTUnwrap(loadSQLitePackage(at: output).articles.first { $0.sourcePath.contains("ZOOM") })
        XCTAssertEqual(zoom.breadcrumbs, ["Руководство", "Кузов", "Навигация/TV"])
    }

    func testImporterClassifiesUnlinkedZoomFromItsHondaESMKey() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <sct_sc_name_list><sct_name code="A" name="Двигатель"><sc_name code="203" name="Топливо и система снижения токсичности"></sc_name></sct_name></sct_sc_name_list>
        """.write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try """
        <sys_name_list><sys_name code="269" name="Система впрыскивания топлива (PGM-FI)"></sys_name></sys_name_list>
        """.write(to: root.appendingPathComponent("ru/info/sys_name_list.xml"), atomically: true, encoding: .utf8)
        try "<title>(SEA6EJ3A20326939902FART00)</title><div class='top_title'>Поиск неисправностей в цепи MIL</div>".write(
            to: root.appendingPathComponent("ru/html/ZOOM000000000000002.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let zoom = try XCTUnwrap(loadSQLitePackage(at: output).articles.first)
        XCTAssertEqual(zoom.breadcrumbs, ["Руководство", "Топливо и система снижения токсичности", "Система впрыскивания топлива (PGM-FI)"])
    }

    func testConvertsLocalHTMLIntoSemanticBlocks() throws {
        let html = "<h1>Проверка ABS</h1><p>Проверьте датчик.</p><div class='warning'>Внимание: отключите аккумулятор.</div><ol><li>Снимите колесо</li></ol>"
        let result = try HTMLArticleParser.parse(html: html, id: "abs", title: "", breadcrumbs: [], sourcePath: "brakes/abs.html")
        XCTAssertEqual(result.blocks.count, 4); XCTAssertEqual(result.blocks[2].kind, .warning); XCTAssertEqual(result.blocks[3].items, ["Снимите колесо"])
    }

    func testExtractsImageNestedInsideTable() throws {
        let html = "<table><tr><td><img src='../tn/diagram.png' alt='Схема коробки'></td></tr></table>"
        let result = try HTMLArticleParser.parse(html: html, id: "diagram", title: "", breadcrumbs: [], sourcePath: "ru/html/article.html")
        XCTAssertEqual(result.images.map(\.localRelativePath), ["ru/tn/diagram.png"])
    }

    func testPlacesResolvedImageFromTableIntoArticleBlockOrder() throws {
        let html = "<p>Перед рисунком</p><table><tr><td><img src='../tn/diagram.png' alt='Схема коробки'></td></tr></table><p>После рисунка</p>"
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "diagram",
            title: "",
            breadcrumbs: [],
            sourcePath: "ru/html/article.html",
            imagePathResolver: { $0.replacingOccurrences(of: "/tn/", with: "/img/") }
        )
        XCTAssertEqual(result.images.map(\.localRelativePath), ["ru/img/diagram.png"])
        XCTAssertEqual(result.blocks.map(\.kind), [.paragraph, .image, .paragraph])
        XCTAssertEqual(result.blocks[1].target, "ru/img/diagram.png")
    }

    func testPlacesImageNestedInLegacyDivAfterItsText() throws {
        let html = "<div>Описание схемы <img src='../tn/diagram.png' alt='Схема SRS'></div>"
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "diagram",
            title: "",
            breadcrumbs: [],
            sourcePath: "ru/html/article.html",
            imagePathResolver: { $0.replacingOccurrences(of: "/tn/", with: "/img/") }
        )
        XCTAssertEqual(result.blocks.map(\.kind), [.paragraph, .image])
        XCTAssertEqual(result.blocks.last?.target, "ru/img/diagram.png")
    }

    func testPlacesImageNestedInsideLegacyLink() throws {
        let html = "<a href=\"javascript:PrtProc('0','ZOOM000000000000001','1')\"><img src=\"../tn/diagram.png\" alt=\"Схема\"></a>"
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "diagram",
            title: "",
            breadcrumbs: [],
            sourcePath: "ru/html/article.html",
            imagePathResolver: { $0.replacingOccurrences(of: "/tn/", with: "/img/") }
        )
        XCTAssertEqual(result.blocks.map(\.kind), [.image])
        XCTAssertEqual(result.blocks.first?.target, "ru/img/diagram.png")
    }

    func testIgnoresHiddenPrintDuplicateAndKeepsVisibleOriginalOnce() throws {
        let html = """
        <span style="display:block"><img src="../tn/diagram.png" alt="Схема"></span>
        <span style="display:none"><img src="../img/diagram.PNG" alt="Схема для печати"></span>
        """
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "visible-image",
            title: "Схема",
            breadcrumbs: [],
            sourcePath: "ru/html/article.html",
            imagePathResolver: { _ in "ru/img/diagram.PNG" }
        )

        XCTAssertEqual(result.images.map(\.localRelativePath), ["ru/img/diagram.PNG"])
        XCTAssertEqual(result.blocks.filter { $0.kind == .image }.count, 1)
    }

    func testIgnoresLegacyViewerResizeButtons() throws {
        let html = "<div><img src='../img/SIZE_L.PNG'><img src='../img/PRINT.PNG'><img src='../img/GL_SEARCH.PNG'><img src='../img/MARKLINE_1.PNG'><img src='../img/diagram.PNG'><img src='../img/RESET_SIZE.PNG'></div>"
        let result = try HTMLArticleParser.parse(html: html, id: "viewer", title: "", breadcrumbs: [], sourcePath: "ru/html/zoom.html")
        XCTAssertEqual(result.images.map(\.localRelativePath), ["ru/img/diagram.PNG"])
    }

    func testDoesNotTreatSafetyTextAsDangerWarning() throws {
        let result = try HTMLArticleParser.parse(html: "<div>Система безопасности защищает пассажиров.</div>", id: "srs", title: "", breadcrumbs: [], sourcePath: "ru/html/article.html")
        XCTAssertEqual(result.blocks.first?.kind, .paragraph)
    }

    func testKeepsExtractedImageWhenListMarkupHasNoImageBlock() throws {
        let html = "<ol><li><img src='../tn/diagram.png'></li></ol>"
        let result = try HTMLArticleParser.parse(
            html: html,
            id: "diagram",
            title: "",
            breadcrumbs: [],
            sourcePath: "ru/html/article.html",
            imagePathResolver: { $0.replacingOccurrences(of: "/tn/", with: "/img/") }
        )
        XCTAssertEqual(result.blocks.map(\.kind), [.image])
        XCTAssertEqual(result.blocks.first?.target, "ru/img/diagram.png")
    }

    func testImporterUsesSubContentsTitleAndFullResolutionImage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/html"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/info"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/tn"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/img"), withIntermediateDirectories: true)
        try "<sct_name code=\"0\" name=\"Общее\"></sct_name>".write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try "<contents key=\"000000000000001\" title=\"Родитель\"><base_sie><sct>0</sct><sc>000</sc></base_sie><sub_contents key=\"000000000000002\" title=\"Человекочитаемое название\"></sub_contents></contents>".write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>SEA8EX3000000000000JCRT22</title><p>Текст <img src=\"../tn/diagram.png\"></p>".write(to: root.appendingPathComponent("ru/html/000000000000002.html"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: root.appendingPathComponent("ru/tn/diagram.png"))
        try Data([2, 3]).write(to: root.appendingPathComponent("ru/img/diagram.PNG"))

        _ = try ESMImporter().importManual(input: root, output: output)
        let package = try loadSQLitePackage(at: output)
        let article = try XCTUnwrap(package.articles.first)
        XCTAssertEqual(article.title, "Человекочитаемое название")
        XCTAssertEqual(article.images.map(\.localRelativePath), ["ru/img/diagram.PNG"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("media/ru/img/diagram.PNG").path))
    }

    func testImporterReplacesZoomPageKeyWithReadableTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/html"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/info"), withIntermediateDirectories: true)
        try "<sct_name code=\"0\" name=\"Общее\"></sct_name>".write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try "<contents_list />".write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>ZOOM000000000012826</title>".write(to: root.appendingPathComponent("ru/html/ZOOM000000000012826.html"), atomically: true, encoding: .utf8)

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let package = try loadSQLitePackage(at: output)
        XCTAssertEqual(package.articles.first?.title, "Увеличенная схема")
    }

    func testImporterUsesVisibleTopicTitleForZoomPage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/html"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/info"), withIntermediateDirectories: true)
        try "<sct_sc_name_list />".write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try "<contents_list />".write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>ZOOM000000000012826</title><div class='top_title'>Поиск неисправностей системы навигации</div>".write(
            to: root.appendingPathComponent("ru/html/ZOOM000000000012826.html"),
            atomically: true,
            encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let package = try loadSQLitePackage(at: output)
        XCTAssertEqual(package.articles.first?.title, "Поиск неисправностей системы навигации")
    }

    func testImporterNamesZoomPageFromHumanReadableIncomingLink() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try "<title>Проверка давления масла</title><a href=\"javascript:PrtProc('2','ZOOM000000000000002')\">Манометр низкого давления</a>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )
        try "<title>SEA8EX3000000000000JCRT22</title><img src='../img/tool.png'>".write(
            to: root.appendingPathComponent("ru/html/ZOOM000000000000002.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let package = try loadSQLitePackage(at: output)
        XCTAssertEqual(package.articles.first { $0.sourcePath.contains("ZOOM") }?.title, "Манометр низкого давления")
    }

    func testImporterFullyDecodesNestedTitleEntities() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try "<contents_list><contents key=\"000000000000001\" title=\"Цепь &amp;quot;массы&amp;quot;\"><base_sie><sct>0</sct><sc>000</sc></base_sie></contents></contents_list>".write(
            to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8
        )
        try "<title>SEA000000000000001</title>".write(to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8)

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let package = try loadSQLitePackage(at: output)
        XCTAssertEqual(package.articles.first?.title, "Цепь \"массы\"")
    }

    func testImporterExpandsImageWrittenByLegacyJavaScript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/html"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/js"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/img"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/info"), withIntermediateDirectories: true)
        try "<sct_name code=\"0\" name=\"Общее\"></sct_name>".write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try "<contents_list />".write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>Схема SRS</title><div>Описание<script src=\"../js/diagram.js\"></script></div>".write(to: root.appendingPathComponent("ru/html/page.html"), atomically: true, encoding: .utf8)
        try "document.write(\"<img src='../img/diagram.PNG' alt='Схема SRS'>\");".write(to: root.appendingPathComponent("ru/js/diagram.js"), atomically: true, encoding: .utf8)
        try Data([1, 2]).write(to: root.appendingPathComponent("ru/img/diagram.PNG"))

        _ = try ESMImporter().importManual(input: root, output: output)
        let package = try loadSQLitePackage(at: output)
        let article = try XCTUnwrap(package.articles.first)
        XCTAssertEqual(article.images.map(\.localRelativePath), ["ru/img/diagram.PNG"])
        XCTAssertEqual(article.blocks.map(\.kind), [.paragraph, .image])
    }

    func testImporterCreatesSearchableSQLitePackage() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try "<title>Проверка ABS</title><p>Код неисправности P0420</p>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"),
            atomically: true,
            encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)

        let databaseURL = output.appendingPathComponent("manual.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT title FROM article_fts WHERE article_fts MATCH 'p0420'", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "Проверка ABS")
    }

    func testImporterBuildsApplicabilityAndRelatedArticles() throws {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <contents_list><contents key="000000000000001" title="Проверка K24A3"><base_sie><dgc>05</dgc><sct>0</sct><sc>000</sc></base_sie></contents></contents_list>
        """.write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try """
        <model_list><model model_code="CL9" model_year="2006"><dgc_list><dgc code="05"></dgc></dgc_list></model></model_list>
        """.write(to: root.appendingPathComponent("ru/info/model_list.xml"), atomically: true, encoding: .utf8)
        try "<title>SEA0000000000000001</title><a href=\"javascript:CtsProc('0','000000000000002','i010')\">Следующая проверка</a>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )
        try "<title>Следующая проверка</title><a name='i010'></a>".write(
            to: root.appendingPathComponent("ru/html/000000000000002.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        let package = try loadSQLitePackage(at: output)
        let first = try XCTUnwrap(package.articles.first { $0.sourcePath.hasSuffix("001.html") })
        let second = try XCTUnwrap(package.articles.first { $0.sourcePath.hasSuffix("002.html") })
        XCTAssertEqual(first.applicability.years, [2006])
        XCTAssertEqual(first.applicability.bodyCodes, ["CL9"])
        XCTAssertEqual(first.applicability.engineCodes, ["K24A3"])
        XCTAssertEqual(first.relatedArticleIDs, [second.id])
    }

    private func makeMinimalRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/html"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ru/info"), withIntermediateDirectories: true)
        try "<sct_name code=\"0\" name=\"Общее\"><sc_name code=\"000\" name=\"Общее\"></sc_name></sct_name>".write(
            to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8
        )
        try "<contents_list />".write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        return root
    }

    private func importedArticle(
        sct: String,
        sc: String,
        sys: String,
        comp: String = "00000",
        sitq: String,
        title: String
    ) throws -> ImportedArticle {
        let root = try makeMinimalRoot()
        let output = root.appendingPathComponent("output")
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <sct_sc_name_list>
          <sct_name code="0" name="Не применимо"><sc_name code="000" name="Не применимо"></sc_name></sct_name>
          <sct_name code="A" name="Двигатель"><sc_name code="144" name="Система охлаждения"></sc_name><sc_name code="203" name="Топливо и система снижения токсичности"></sc_name></sct_name>
          <sct_name code="F" name="Рулевое управление"><sc_name code="000" name="Не применимо"></sc_name></sct_name>
          <sct_name code="K" name="Коды неисправностей системы управления"><sc_name code="721" name="ЕСМ"></sc_name></sct_name>
        </sct_sc_name_list>
        """.write(to: root.appendingPathComponent("ru/info/sct_sc_name_list.xml"), atomically: true, encoding: .utf8)
        try """
        <sys_name_list>
          <sys_name code="000" name="Не применимо"></sys_name>
          <sys_name code="261" name="Управление вентилятором"></sys_name>
          <sys_name code="264" name="Система питания топливом"></sys_name>
        </sys_name_list>
        """.write(to: root.appendingPathComponent("ru/info/sys_name_list.xml"), atomically: true, encoding: .utf8)
        try """
        <contents_list><contents key="000000000000001" title="\(title)"><base_sie>
          <sct>\(sct)</sct><sc>\(sc)</sc><sys>\(sys)</sys><comp>\(comp)</comp><sitq>\(sitq)</sitq>
        </base_sie></contents></contents_list>
        """.write(to: root.appendingPathComponent("ru/info/contents_list.xml"), atomically: true, encoding: .utf8)
        try "<title>\(title)</title><p>Содержимое</p>".write(
            to: root.appendingPathComponent("ru/html/000000000000001.html"), atomically: true, encoding: .utf8
        )

        _ = try ESMImporter().importManual(input: root, output: output, copyMedia: false)
        return try XCTUnwrap(loadSQLitePackage(at: output).articles.first)
    }

    private func loadSQLitePackage(at output: URL) throws -> ManualPackage {
        var database: OpaquePointer?
        let url = output.appendingPathComponent("manual.sqlite")
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw NSError(domain: "ManualImporterTests", code: 1)
        }
        defer { sqlite3_close(database) }
        let decoder = JSONDecoder()
        func blobs(_ sql: String) throws -> [Data] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw NSError(domain: "ManualImporterTests", code: 2)
            }
            defer { sqlite3_finalize(statement) }
            var result: [Data] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_bytes(statement, 0))
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                result.append(Data(bytes: bytes, count: count))
            }
            return result
        }
        let sections = try blobs("SELECT json FROM sections ORDER BY sort_order").map { try decoder.decode(ImportedSection.self, from: $0) }
        let articles = try blobs("SELECT article_json FROM articles ORDER BY rowid").map { try decoder.decode(ImportedArticle.self, from: $0) }
        return ManualPackage(sections: sections, articles: articles)
    }
}
#else
// The current machine has Command Line Tools only. Xcode supplies XCTest when
// this package is opened there; keep the target buildable for CLI-only hosts.
enum ManualImporterTestsUnavailableWithoutXcode {}
#endif
