import SwiftUI
import SwiftData

enum AppConfiguration {
    static let supportEmail = "mail@deniskirillov.com"
    static let telegramUsername = "KirillovDV"
    static let telegramWebURLString = "https://t.me/KirillovDV"
}

@main
struct AccordManualApp: App {
    private let container: ModelContainer? = {
        let schema = Schema([Bookmark.self, UserNote.self, ReadingHistoryEntry.self, ChecklistState.self, VehicleProfile.self, AppSettings.self])
        return try? ModelContainer(for: schema)
    }()
    @State private var manualStore = ManualStore()

    var body: some Scene {
        WindowGroup {
            if let container {
                RootContent()
                    .environment(manualStore)
                    .tint(.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                    .modelContainer(container)
                    .environment(FullScreenPresenter.shared)
            } else {
                ContentUnavailableView("Хранилище недоступно", systemImage: "externaldrive.badge.exclamationmark", description: Text("Освободите место на устройстве и перезапустите приложение."))
            }
        }
    }
}

private struct RootContent: View {
    var body: some View {
#if DEBUG
        if let articleID = ProcessInfo.processInfo.environment["ACCORD_UI_TEST_ARTICLE"] {
            UITestArticleHost(articleID: articleID)
        } else {
            RootTabView()
        }
#else
        RootTabView()
#endif
    }
}

private struct UITestArticleHost: View {
    @Environment(ManualStore.self) private var store
    let articleID: String
    @State private var router = NavigationRouter()

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            Group {
                if let article = store.summary(id: articleID) {
                    ArticleView(article: article)
                } else {
                    ContentUnavailableView("Материал недоступен", systemImage: "doc.badge.exclamationmark")
                }
            }
            .navigationDestination(for: ManualRoute.self) { route in
                if route.kind == .article, let article = store.summary(id: route.value) {
                    ArticleView(article: article, initialAnchor: route.anchor)
                }
            }
        }
        .environment(router)
    }
}
