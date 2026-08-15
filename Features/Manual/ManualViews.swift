import SwiftUI
import SwiftData

struct RootTabView: View {
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { switch appearance { case "dark": return .dark; case "light": return .light; default: return nil } }
    var body: some View { ZStack { Color(uiColor: .systemBackground).ignoresSafeArea(); TabView { ManualHomeView().tabItem { Label("Руководство", systemImage: "books.vertical") }; SearchView().tabItem { Label("Поиск", systemImage: "magnifyingglass") }; SavedView().tabItem { Label("Сохранённое", systemImage: "bookmark") }; SettingsView().tabItem { Label("Ещё", systemImage: "ellipsis.circle") } }.frame(maxWidth: .infinity, maxHeight: .infinity) }.preferredColorScheme(colorScheme) }
}

struct ManualHomeView: View {
    @Environment(ManualStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \ReadingHistoryEntry.lastOpenedAt, order: .reverse) private var history: [ReadingHistoryEntry]
    @Query private var profiles: [VehicleProfile]
    @State private var router = NavigationRouter(storageKey: "manualNavigationState")
    @ViewBuilder private var compactBody: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) { manualList.manualDestinations(preference: vehiclePreference) }
    }
    @ViewBuilder private var regularBody: some View {
        @Bindable var router = router
        NavigationSplitView {
            manualList.navigationTitle("Руководство")
        } detail: {
            NavigationStack(path: $router.path) {
                ContentUnavailableView("Выберите материал", systemImage: "books.vertical", description: Text("Откройте раздел или быструю категорию."))
                    .manualDestinations(preference: vehiclePreference)
            }
        }
    }
    var body: some View {
        Group {
            if sizeClass == .compact { compactBody } else { regularBody }
        }
        .environment(router)
    }
    private var manualList: some View { List { if !history.isEmpty { Section("Продолжить чтение") { ForEach(history.prefix(5)) { entry in if let article = store.summary(id: entry.articleID) { AdaptiveRouteLink(route: .article(articleID: article.id, anchor: nil)) { Label(article.title, systemImage: "clock") }.accessibilityLabel("Продолжить: \(article.title)") } } } }; Section("Быстрые категории") { ForEach(QuickCategory.allCases) { category in AdaptiveRouteLink(route: .category(category.rawValue)) { Label(category.title, systemImage: category.symbol) } } }; Section("Все разделы") { ForEach(store.children(of: nil)) { section in PhoneSectionRow(section: section, preference: vehiclePreference) } } }.navigationTitle("Руководство") }
    private var vehiclePreference: SearchFilters { let profile = profiles.first; return SearchFilters(year: profile?.year, bodyCode: profile?.bodyCode, engineCode: profile?.engineCode, transmission: profile?.transmission) }
}

private struct PhoneSectionRow: View { @Environment(ManualStore.self) private var store; let section: ManualSection; let preference: SearchFilters; var body: some View { let children = store.children(of: section.id); let articles = sorted(store.articles.filter { $0.sectionID == section.id }); if children.isEmpty { AdaptiveRouteLink(route: .section(section.id)) { Text(section.title) } } else { DisclosureGroup(section.title) { ForEach(children) { PhoneSectionRow(section: $0, preference: preference) }; ForEach(articles) { article in AdaptiveRouteLink(route: .article(articleID: article.id, anchor: nil)) { Text(article.title) } } } } }; private func sorted(_ articles: [ManualArticle]) -> [ManualArticle] { articles.sorted { ManualStore.compatibilityScore($0, preference: preference) > ManualStore.compatibilityScore($1, preference: preference) } } }

private struct AdaptiveRouteLink<Label: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(NavigationRouter.self) private var router
    let route: ManualRoute
    @ViewBuilder let label: () -> Label
    var body: some View {
        if sizeClass == .compact {
            NavigationLink(value: route, label: label)
        } else {
            Button { router.open(route) } label: { HStack { label(); Spacer(); Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) } }
                .buttonStyle(.plain)
        }
    }
}

enum QuickCategory: String, CaseIterable, Identifiable {
    case service, engine, transmission, brakes, suspension, steering, electrical, body, diagrams, dtc
    var id: String { rawValue }
    var title: String { ["service":"Обслуживание", "engine":"Двигатель", "transmission":"Трансмиссия", "brakes":"Тормоза", "suspension":"Подвеска", "steering":"Рулевое управление", "electrical":"Электрика", "body":"Кузов", "diagrams":"Схемы", "dtc":"Диагностика / DTC"][rawValue] ?? rawValue }
    var symbol: String { ["service":"wrench.and.screwdriver", "engine":"engine.combustion", "transmission":"gearshape", "brakes":"car.rear.and.tire.marks", "suspension":"car", "steering":"steeringwheel", "electrical":"bolt.car", "body":"car.side", "diagrams":"point.3.connected.trianglepath.dotted", "dtc":"exclamationmark.triangle"][rawValue] ?? "books.vertical" }
    func matches(_ article: ManualArticle) -> Bool {
        let haystack = ManualStore.normalized(article.title + " " + article.breadcrumbs.joined(separator: " "))
        let terms: [String]
        switch self {
        case .service: terms = ["обслужив", "техническое состояние", "замена масла"]
        case .engine: terms = ["двигател", "топлив", "впуск", "выпуск"]
        case .transmission: terms = ["трансмисс", "коробк", "сцеплен", "акп", "мкп"]
        case .brakes: terms = ["тормоз", "abs", "vsa"]
        case .suspension: terms = ["подвеск", "амортиз", "ступиц"]
        case .steering: terms = ["рулев", "гидроусилител"]
        case .electrical: terms = ["электр", "аккумулятор", "генератор", "стартер"]
        case .body: terms = ["кузов", "двер", "стекл", "салон"]
        case .diagrams: terms = ["схем", "расположение", "разъем"]
        case .dtc: terms = ["диагност", "dtc", "поиск неисправност", "код неисправност"]
        }
        return terms.contains { haystack.contains($0) }
    }
}
struct CategoryView: View { @Environment(ManualStore.self) private var store; let category: QuickCategory; let preference: SearchFilters; var body: some View { ArticleListView(title: category.title, articles: store.articles.filter(category.matches).sorted { ManualStore.compatibilityScore($0, preference: preference) > ManualStore.compatibilityScore($1, preference: preference) }) } }
struct ArticleListView: View { let title: String; let articles: [ManualArticle]; var body: some View { List(articles) { article in AdaptiveRouteLink(route: .article(articleID: article.id, anchor: nil)) { VStack(alignment: .leading) { Text(article.title); Text(article.breadcrumbs.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary) } } }.navigationTitle(title).overlay { if articles.isEmpty { ContentUnavailableView("Материалов пока нет", systemImage: "doc.text.magnifyingglass", description: Text("Импортируйте полный пакет ESM, чтобы увидеть этот раздел.")) } } } }

private extension View {
    func manualDestinations(preference: SearchFilters) -> some View {
        navigationDestination(for: ManualRoute.self) { route in ManualRouteView(route: route, preference: preference) }
    }
}

private struct ManualRouteView: View {
    @Environment(ManualStore.self) private var store
    let route: ManualRoute
    let preference: SearchFilters
    var body: some View {
        switch route.kind {
        case .article:
            if let article = store.summary(id: route.value) { ArticleView(article: article, initialAnchor: route.anchor) }
            else { ContentUnavailableView("Материал недоступен", systemImage: "doc.badge.exclamationmark") }
        case .category:
            if let category = QuickCategory(rawValue: route.value) { CategoryView(category: category, preference: preference) }
            else { ContentUnavailableView("Категория недоступна", systemImage: "folder.badge.questionmark") }
        case .section:
            let section = store.sections.first { $0.id == route.value }
            ArticleListView(title: section?.title ?? "Раздел", articles: store.articles.filter { $0.sectionID == route.value }.sorted { ManualStore.compatibilityScore($0, preference: preference) > ManualStore.compatibilityScore($1, preference: preference) })
        }
    }
}

struct ArticleView: View {
    @Environment(ManualStore.self) private var store; @Environment(NavigationRouter.self) private var router; @Environment(FullScreenPresenter.self) private var fullScreenPresenter; @Environment(\.modelContext) private var context; @Query private var bookmarks: [Bookmark]; @Query private var notes: [UserNote]; @Query private var history: [ReadingHistoryEntry]; @State private var showNote = false; @State private var findText = ""; @State private var scrollPosition: String?; @State private var isContentsExpanded = false; @State private var didRestoreReaderState = false; @State private var loadedArticle: ManualArticle?; @State private var exportDocument: ArticlePDFDocument?; @State private var exportError: String?
    let article: ManualArticle
    let initialAnchor: String?
    init(article: ManualArticle, initialAnchor: String? = nil) { self.article = article; self.initialAnchor = initialAnchor }
    var body: some View {
        let fullArticle = loadedArticle ?? article
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(fullArticle.breadcrumbs.joined(separator: " › "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Путь: \(fullArticle.breadcrumbs.joined(separator: ", "))")
                    Text(fullArticle.title).font(.largeTitle.bold()).textSelection(.enabled)
                    if fullArticle.blocks.isEmpty { ProgressView("Загрузка статьи…").frame(maxWidth: .infinity, minHeight: 180) }
                    if fullArticle.blocks.filter({ $0.kind == .heading }).count > 2 {
                        ArticleContents(blocks: fullArticle.blocks, isExpanded: $isContentsExpanded, scrollTo: { proxy.scrollTo($0, anchor: .top) })
                    }
                    ForEach(ArticleContentLayout.blocks(from: fullArticle.blocks)) { item in
                        switch item {
                        case let .block(block):
                            ArticleBlockView(block: block, article: fullArticle, findText: findText, openImage: { path in showGallery(article: fullArticle, index: fullArticle.images.firstIndex { $0.localRelativePath == path } ?? 0) })
                        case let .note(note):
                            NoteCalloutView(note: note, article: fullArticle, findText: findText, openImage: { path in showGallery(article: fullArticle, index: fullArticle.images.firstIndex { $0.localRelativePath == path } ?? 0) })
                        }
                    }
                    RelatedArticles(article: fullArticle)
                    Button("К началу", systemImage: "arrow.up") { withAnimation { proxy.scrollTo("article-top", anchor: .top) } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding()
                .id("article-top")
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition)
            .searchable(text: $findText, prompt: "Искать в статье")
            .task(id: "\(article.id):\(fullArticle.blocks.count)") {
                restoreReaderState(for: fullArticle, proxy: proxy)
            }
            .onChange(of: scrollPosition) { _, _ in saveTransientReaderState() }
            .onChange(of: isContentsExpanded) { _, _ in saveTransientReaderState() }
            .onChange(of: findText) { _, value in
                guard !value.isEmpty, let block = fullArticle.blocks.first(where: { $0.text.localizedCaseInsensitiveContains(value) || $0.items.contains(where: { $0.localizedCaseInsensitiveContains(value) }) }) else { return }
                withAnimation { proxy.scrollTo(block.id, anchor: .center) }
            }
        }
        .navigationTitle(fullArticle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button("Вперёд", systemImage: "chevron.forward") { _ = router.goForward() }.disabled(!router.canGoForward); Button("Экспорт в PDF", systemImage: "square.and.arrow.up") { exportArticle(fullArticle) }.accessibilityHint("Создаёт PDF со всем содержимым статьи"); if !fullArticle.images.isEmpty { Button("Рисунки", systemImage: "photo.on.rectangle") { showGallery(article: fullArticle, index: 0) } }; Button(isBookmarked ? "Удалить из избранного" : "В избранное", systemImage: isBookmarked ? "bookmark.fill" : "bookmark") { toggleBookmark() }.accessibilityLabel(isBookmarked ? "Удалить из избранного" : "Добавить в избранное"); Button("Добавить заметку", systemImage: "square.and.pencil") { showNote = true } } }
        .sheet(isPresented: $showNote) { NoteEditor(article: fullArticle, existing: notes.first { $0.articleID == fullArticle.id }) }
        .sheet(item: $exportDocument) { document in ArticleShareSheet(items: [document.url]) }
        .alert("Не удалось создать PDF", isPresented: Binding { exportError != nil } set: { if !$0 { exportError = nil } }) { Button("Готово", role: .cancel) {} } message: { Text(exportError ?? "Неизвестная ошибка") }
        .task(id: article.id) { didRestoreReaderState = false; loadedArticle = await store.loadArticle(id: article.id); recordVisit() }
        .onDisappear { saveTransientReaderState(); saveReadingPosition() }
    }
    private func showGallery(article: ManualArticle, index: Int) { fullScreenPresenter.present(GalleryPresentation(article: article, initialIndex: index, openLink: openDiagramLink, linkTitle: diagramLinkTitle)) }
    private func diagramLinkTitle(_ target: String) -> String? {
        let components = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        return store.article(path: String(components[0]))?.title
    }
    private func openDiagramLink(_ target: String) {
        let components = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let destination = store.article(path: String(components[0])) else { return }
        let anchor = components.count == 2 && !["000", "i000"].contains(String(components[1])) ? String(components[1]) : nil
        fullScreenPresenter.dismiss()
        // The full-screen viewer owns a temporary key window. Route on the
        // next main-loop turn, after that window has been released, so the
        // original NavigationStack receives the update deterministically.
        DispatchQueue.main.async { router.open(articleID: destination.id, anchor: anchor) }
    }
    private func exportArticle(_ article: ManualArticle) { do { exportDocument = ArticlePDFDocument(url: try ArticlePDFExporter.write(article: article)) } catch { exportError = error.localizedDescription } }
    private var isBookmarked: Bool { bookmarks.contains { $0.articleID == article.id } }
    private func toggleBookmark() { if let bookmark = bookmarks.first(where: { $0.articleID == article.id }) { context.delete(bookmark) } else { context.insert(Bookmark(articleID: article.id)) } }
    private func recordVisit() { if let entry = try? context.fetch(FetchDescriptor<ReadingHistoryEntry>(predicate: #Predicate { $0.articleID == article.id })).first { entry.lastOpenedAt = .now } else { context.insert(ReadingHistoryEntry(articleID: article.id)) } }
    private func restoreReaderState(for fullArticle: ManualArticle, proxy: ScrollViewProxy) {
        if let state = router.readerState(for: fullArticle.id) {
            isContentsExpanded = state.expandedBlockIDs.contains("contents")
        }
        guard !didRestoreReaderState, !fullArticle.blocks.isEmpty else { return }
        didRestoreReaderState = true
        let target = initialAnchor
            ?? router.readerState(for: fullArticle.id)?.scrollAnchor
            ?? history.first(where: { $0.articleID == fullArticle.id })?.scrollAnchor
        guard let target else { return }
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
    }
    private func saveTransientReaderState() {
        let existing = router.readerState(for: article.id)
        router.saveReaderState(
            articleID: article.id,
            scrollAnchor: scrollPosition ?? existing?.scrollAnchor,
            expandedBlockIDs: isContentsExpanded ? ["contents"] : []
        )
    }
    private func saveReadingPosition() {
        guard let entry = history.first(where: { $0.articleID == article.id }) else { return }
        entry.scrollAnchor = scrollPosition ?? router.readerState(for: article.id)?.scrollAnchor
    }
}

struct GallerySelection: Identifiable, Equatable {
    let articleID: String
    let index: Int
    var id: String { "\(articleID):\(index)" }
}

private struct ArticleShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
private struct ArticlePDFDocument: Identifiable { let url: URL; var id: String { url.absoluteString } }

private struct ArticleContents: View { let blocks: [ArticleBlock]; @Binding var isExpanded: Bool; let scrollTo: (String) -> Void; var body: some View { DisclosureGroup("Содержание", isExpanded: $isExpanded) { ForEach(blocks.filter { $0.kind == .heading }) { block in Button(block.text) { scrollTo(block.anchor ?? block.id) }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading) } }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
private struct RelatedArticles: View { @Environment(ManualStore.self) private var store; @Environment(NavigationRouter.self) private var router; let article: ManualArticle; var body: some View { let related = article.relatedArticleIDs.compactMap { store.summary(id: $0) }; if !related.isEmpty { Section("Связанные материалы") { ForEach(related) { destination in Button(destination.title) { router.open(articleID: destination.id) }.buttonStyle(.plain).foregroundStyle(.tint) } } } } }
private extension Optional where Wrapped == String { var orEmpty: String { self ?? "" } }
