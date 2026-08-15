import XCTest

@MainActor
final class AccordManualUITests: XCTestCase {
    func testFeedbackShowsConfiguredContactMethods() {
        let app = XCUIApplication()
        app.launch()

        let moreTab = app.tabBars.buttons["Ещё"]
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
        let searchTab = app.tabBars.buttons["Поиск"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 15))
        searchTab.tap()
        let field = app.searchFields["DTC, момент, деталь или тема"]
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
}
