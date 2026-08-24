import XCTest

@MainActor
final class AccordManualUITests: XCTestCase {
    private let seededArticleID = "e0f1d9553589ca92"
    private let seededArticleTitle = "Конструкция кузова — лист 000000000001544"
    private let sectionArticleID = "036cd34a7aafbb9e"
    private let sectionArticleTitle = "Навигация исходного руководства — лист BRL_CM2_2008"
    private let tableAndImageArticleID = "381eeb12f4e6141a"

    func testRecentArticleOpensFromManualHome() {
        let app = makeManualHomeApp()

        let recentArticle = app.buttons["recent-article-\(seededArticleID)"]
        XCTAssertTrue(recentArticle.waitForExistence(timeout: 10))
        recentArticle.tap()

        XCTAssertTrue(app.staticTexts[seededArticleTitle].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Manual home recent article"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSectionArticleOpensFromManualHome() {
        let app = makeManualHomeApp()

        app.swipeUp()
        let rootSection = app.buttons["manual-section-Руководство"]
        XCTAssertTrue(rootSection.waitForExistence(timeout: 10))
        rootSection.tap()

        let bodyRepair = app.buttons["manual-section-Руководство/Ремонт кузова"]
        XCTAssertTrue(bodyRepair.waitForExistence(timeout: 10))
        bodyRepair.tap()

        let generalInformation = app.buttons["manual-section-Руководство/Ремонт кузова/Общая информация"]
        XCTAssertTrue(generalInformation.waitForExistence(timeout: 10))
        generalInformation.tap()

        let article = app.buttons["section-article-\(sectionArticleID)"]
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        article.tap()

        XCTAssertTrue(app.staticTexts[sectionArticleTitle].waitForExistence(timeout: 10))
    }

    func testIPadManualHomeOpensSelectionInDetail() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = makeManualHomeApp()

        let sidebarRootSection = app.buttons["manual-section-Руководство"]
        XCTAssertTrue(sidebarRootSection.waitForExistence(timeout: 10))
        app.buttons["recent-article-\(seededArticleID)"].tap()

        XCTAssertTrue(app.staticTexts[seededArticleTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(sidebarRootSection.exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "iPad manual sidebar and article portrait"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testIPadArticleContentIsReadableAndDoesNotOverflow() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = makeManualHomeApp(historyArticleID: tableAndImageArticleID)
        app.buttons["recent-article-\(tableAndImageArticleID)"].tap()

        let content = app.otherElements["article-content"]
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(content.frame.width, 900)
        XCTAssertLessThanOrEqual(content.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(content.frame.minX, app.frame.minX - 1)

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "iPad article landscape"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFeedbackShowsConfiguredContactMethods() {
        let app = XCUIApplication()
        app.launch()

        let moreTab = app.buttons["Ещё"].firstMatch
        XCTAssertTrue(moreTab.waitForExistence(timeout: 10))
        moreTab.tap()
        app.swipeUp()

        let email = app.descendants(matching: .any)["feedback-email"]
        let telegram = app.descendants(matching: .any)["feedback-telegram"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertTrue(email.isHittable)
        XCTAssertTrue(telegram.isHittable)
    }

    func testFullManualSearchOpensArticle() {
        let app = XCUIApplication()
        app.launchEnvironment["ACCORD_UI_TEST_RESET_NAVIGATION"] = "1"
        app.launch()
        let searchTab = app.buttons["Поиск"].firstMatch
        XCTAssertTrue(searchTab.waitForExistence(timeout: 15))
        searchTab.tap()
        let field = app.searchFields["DTC, момент, деталь или тема"]
        if !field.waitForExistence(timeout: 2) {
            let revealSearch = app.buttons["Search"].firstMatch
            XCTAssertTrue(revealSearch.waitForExistence(timeout: 10))
            revealSearch.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("P0300")
        let firstResult = app.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 10))
        let openedTitle = firstResult.staticTexts.firstMatch.label
        XCTAssertFalse(openedTitle.isEmpty)
        firstResult.tap()
        XCTAssertTrue(app.staticTexts[openedTitle].waitForExistence(timeout: 10))
    }

    func testImageViewerCoversScreenAndCentersDiagram() {
        let app = XCUIApplication()
        app.launchEnvironment["ACCORD_UI_TEST_ARTICLE"] = "e0f1d9553589ca92"
        app.launch()
        let galleryButton = app.buttons["Рисунки"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 10))
        galleryButton.tap()

        let viewer = app.otherElements["full-screen-image-viewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Рисунок 1 из 1"].exists)
        XCTAssertLessThanOrEqual(viewer.frame.minY, app.frame.minY + app.frame.height * 0.2)
        XCTAssertGreaterThanOrEqual(viewer.frame.maxY, app.frame.maxY - app.frame.height * 0.2)
        XCTAssertEqual(viewer.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertTrue(app.buttons["Закрыть"].isHittable)
        XCTAssertTrue(app.buttons["Вписать"].isHittable)
        let originalScale = app.buttons["Масштаб один к одному"]
        XCTAssertTrue(originalScale.isHittable)

        let fitScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fitScreenshot.name = "Diagram centered and fitted"
        fitScreenshot.lifetime = .keepAlways
        add(fitScreenshot)

        originalScale.tap()
        XCTAssertTrue(app.buttons["Вписать"].isHittable)

        let originalScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        originalScreenshot.name = "Diagram at original scale"
        originalScreenshot.lifetime = .keepAlways
        add(originalScreenshot)
    }

    func testTappingInlineImageOpensFullScreenViewer() {
        let app = XCUIApplication()
        app.launchEnvironment["ACCORD_UI_TEST_ARTICLE"] = "e0f1d9553589ca92"
        app.launch()

        let inlineImage = app.buttons["Открыть рисунок"].firstMatch
        XCTAssertTrue(inlineImage.waitForExistence(timeout: 10))
        XCTAssertTrue(inlineImage.isHittable)
        inlineImage.tap()

        XCTAssertTrue(app.otherElements["full-screen-image-viewer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Закрыть"].isHittable)
    }

    func testDiagramLinkShowsDestinationBeforeOpeningArticle() {
        let app = XCUIApplication()
        app.launchEnvironment["ACCORD_UI_TEST_ARTICLE"] = "1a8a6de2bb276292"
        app.launch()

        let galleryButton = app.buttons["Рисунки"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 10))
        galleryButton.tap()

        let linksMenu = app.buttons["Ссылки на схеме"]
        XCTAssertTrue(linksMenu.waitForExistence(timeout: 10))
        linksMenu.tap()
        let link = app.buttons["Регулировка положения,"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()

        let destinationTitle = "Регулировка положения передней и задней дверей"
        XCTAssertTrue(app.staticTexts[destinationTitle].exists)

        let openArticle = app.buttons["Открыть статью"]
        XCTAssertTrue(openArticle.waitForExistence(timeout: 10))

        let linkScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        linkScreenshot.name = "Interactive diagram link"
        linkScreenshot.lifetime = .keepAlways
        add(linkScreenshot)

        openArticle.tap()
        XCTAssertTrue(app.staticTexts[destinationTitle].waitForExistence(timeout: 10))
    }

    func testArticleOffersPDFExport() {
        let app = XCUIApplication()
        app.launchEnvironment["ACCORD_UI_TEST_ARTICLE"] = "e0f1d9553589ca92"
        app.launch()

        let export = app.buttons["Экспорт в PDF"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        XCTAssertTrue(export.isHittable)
        export.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10) || app.buttons["Сохранить в Файлы"].waitForExistence(timeout: 10))
    }

    private func makeManualHomeApp(historyArticleID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ACCORD_UI_TEST_RESET_NAVIGATION"] = "1"
        app.launchEnvironment["ACCORD_UI_TEST_SEED_HISTORY_ARTICLE"] = historyArticleID ?? seededArticleID
        app.launch()
        return app
    }
}
