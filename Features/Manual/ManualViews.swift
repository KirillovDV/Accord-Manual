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
    @Environment(\.modelContext) private var context
    @Query(sort: \ReadingHistoryEntry.lastOpenedAt, order: .reverse) private var history: [ReadingHistoryEntry]
    @Query private var profiles: [VehicleProfile]
    @State private var router = NavigationRouter(storageKey: "manualNavigationState")
    @State private var sidebarSelection: ManualRoute?
    @State private var installedUITestSeed = false

    @ViewBuilder private var compactBody: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) { manualList.manualDestinations(preference: vehiclePreference) }
    }

    @ViewBuilder private var regularBody: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                manualListContents
            }
            .navigationTitle("Руководство")
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
            .accessibilityIdentifier("manual-sidebar")
        } detail: {
            NavigationStack(path: $router.path) {
                Group {
                    if let sidebarSelection {
                        ManualRouteView(route: sidebarSelection, preference: vehiclePreference)
                    } else {
                        ContentUnavailableView("Выберите материал", systemImage: "books.vertical", description: Text("Откройте раздел или быструю категорию."))
                    }
                }
                .manualDestinations(preference: vehiclePreference)
            }
            .accessibilityIdentifier("manual-detail")
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: sidebarSelection) { oldValue, newValue in
            guard sizeClass != .compact, oldValue != newValue else { return }
            router.replacePath([])
        }
    }

    var body: some View {
        Group {
            if sizeClass == .compact { compactBody } else { regularBody }
        }
        .environment(router)
        .task { installUITestHistorySeedIfNeeded() }
    }

    private var manualList: some View {
        List { manualListContents }
            .navigationTitle("Руководство")
    }

    @ViewBuilder private var manualListContents: some View {
        if !history.isEmpty {
            Section("Продолжить чтение") {
                ForEach(history.prefix(5)) { entry in
                    if let article = store.summary(id: entry.articleID) {
                        ManualRouteLink(
                            route: .article(articleID: article.id, anchor: nil),
                            accessibilityID: "recent-article-\(article.id)"
                        ) {
                            Label(article.title, systemImage: "clock")
                        }
                        .accessibilityLabel("Продолжить: \(article.title)")
                    }
                }
            }
        }
        Section("Быстрые категории") {
            ForEach(QuickCategory.allCases) { category in
                ManualRouteLink(route: .category(category.rawValue)) {
                    Label(category.title, systemImage: category.symbol)
                }
            }
        }
        Section("Все разделы") {
            ForEach(store.children(of: nil)) { section in
                ManualSectionRow(section: section, preference: vehiclePreference)
            }
        }
    }

    private var vehiclePreference: SearchFilters { let profile = profiles.first; return SearchFilters(year: profile?.year, bodyCode: profile?.bodyCode, engineCode: profile?.engineCode, transmission: profile?.transmission) }

    private func installUITestHistorySeedIfNeeded() {
#if DEBUG
        guard !installedUITestSeed,
              let articleID = ProcessInfo.processInfo.environment["ACCORD_UI_TEST_SEED_HISTORY_ARTICLE"],
              store.summary(id: articleID) != nil else { return }
        installedUITestSeed = true
        let entries = (try? context.fetch(FetchDescriptor<ReadingHistoryEntry>())) ?? []
        entries.forEach(context.delete)
        context.insert(ReadingHistoryEntry(articleID: articleID))
        try? context.save()
#endif
    }
}

private struct ManualSectionRow: View {
    @Environment(ManualStore.self) private var store
    let section: ManualSection
    let preference: SearchFilters
    @State private var isExpanded = false

    var body: some View {
        let children = store.children(of: section.id)
        let articles = sorted(store.articles.filter { $0.sectionID == section.id })
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ManualRouteLink(
                    route: .section(section.id),
                    accessibilityID: "manual-section-\(section.id)"
                ) {
                    Text(section.title)
                }
                if !children.isEmpty || !articles.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isExpanded ? "Свернуть \(section.title)" : "Развернуть \(section.title)")
                    .accessibilityIdentifier("manual-expand-\(section.id)")
                }
            }
            if isExpanded {
                ForEach(children) { child in
                    ManualSectionRow(section: child, preference: preference)
                        .padding(.leading, 16)
                }
                ForEach(articles) { article in
                    ManualRouteLink(
                        route: .article(articleID: article.id, anchor: nil),
                        accessibilityID: "section-article-\(article.id)"
                    ) {
                        Text(article.title)
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func sorted(_ articles: [ManualArticle]) -> [ManualArticle] {
        articles.sorted { ManualStore.compatibilityScore($0, preference: preference) > ManualStore.compatibilityScore($1, preference: preference) }
    }
}

private struct ManualRouteLink<Label: View>: View {
    let route: ManualRoute
    let accessibilityID: String?
    @ViewBuilder let label: () -> Label

    init(route: ManualRoute, accessibilityID: String? = nil, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.accessibilityID = accessibilityID
        self.label = label
    }

    var body: some View { NavigationLink(value: route, label: label).accessibilityIdentifier(accessibilityID ?? "") }
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
struct ArticleListView: View { let title: String; let articles: [ManualArticle]; var body: some View { List(articles) { article in ManualRouteLink(route: .article(articleID: article.id, anchor: nil), accessibilityID: "section-article-\(article.id)") { VStack(alignment: .leading) { Text(article.title); Text(article.breadcrumbs.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary) } } }.navigationTitle(title).overlay { if articles.isEmpty { ContentUnavailableView("Материалов пока нет", systemImage: "doc.text.magnifyingglass", description: Text("Импортируйте полный пакет ESM, чтобы увидеть этот раздел.")) } } } }

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
            ManualSectionDetailView(sectionID: route.value, preference: preference)
        }
    }
}

private struct ManualSectionDetailView: View {
    @Environment(ManualStore.self) private var store
    let sectionID: String
    let preference: SearchFilters

    var body: some View {
        let section = store.sections.first { $0.id == sectionID }
        let children = store.children(of: sectionID)
        let articles = store.articles
            .filter { $0.sectionID == sectionID }
            .sorted { ManualStore.compatibilityScore($0, preference: preference) > ManualStore.compatibilityScore($1, preference: preference) }
        List {
            if !children.isEmpty {
                Section("Подразделы") {
                    ForEach(children) { child in
                        ManualRouteLink(route: .section(child.id), accessibilityID: "manual-section-\(child.id)") {
                            Label(child.title, systemImage: "folder")
                        }
                    }
                }
            }
            if !articles.isEmpty {
                Section("Материалы") {
                    ForEach(articles) { article in
                        ManualRouteLink(route: .article(articleID: article.id, anchor: nil), accessibilityID: "section-article-\(article.id)") {
                            VStack(alignment: .leading) {
                                Text(article.title)
                                Text(article.breadcrumbs.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(section?.title ?? "Раздел")
        .overlay {
            if children.isEmpty && articles.isEmpty {
                ContentUnavailableView("Материалов пока нет", systemImage: "folder.badge.questionmark")
            }
        }
    }
}

struct ArticleView: View {
    @Environment(ManualStore.self) private var store; @Environment(NavigationRouter.self) private var router; @Environment(FullScreenPresenter.self) private var fullScreenPresenter; @Environment(\.modelContext) private var context; @Query private var bookmarks: [Bookmark]; @Query private var notes: [UserNote]; @Query private var history: [ReadingHistoryEntry]; @State private var showNote = false; @State private var findText = ""; @State private var scrollPosition: String?; @State private var isContentsExpanded = false; @State private var didRestoreReaderState = false; @State private var loadedArticle: ManualArticle?; @State private var isLoadingArticle = true; @State private var exportDocument: ArticlePDFDocument?; @State private var exportError: String?; @State private var highlightedAnchor: String?
    let article: ManualArticle
    let initialAnchor: String?
    init(article: ManualArticle, initialAnchor: String? = nil) { self.article = article; self.initialAnchor = initialAnchor }
    var body: some View {
        let fullArticle = loadedArticle ?? article
        let loadPresentation = ArticleLoadPresentation(article: fullArticle, isLoading: isLoadingArticle)
        let contentItems = ArticleContentLayout.blocks(from: fullArticle.blocks)
        let hasContents = fullArticle.blocks.reduce(into: 0) { $0 += $1.kind == .heading ? 1 : 0 } > 2
        ScrollViewReader { proxy in
            let openImage: (String) -> Void = { path in
                showGallery(article: fullArticle, index: fullArticle.images.firstIndex { $0.localRelativePath == path } ?? 0)
            }
            let openLink: (String) -> Void = { target in
                followLink(target, in: fullArticle, proxy: proxy)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(fullArticle.breadcrumbs.joined(separator: " › "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Путь: \(fullArticle.breadcrumbs.joined(separator: ", "))")
                    Text(fullArticle.title).font(.largeTitle.bold()).textSelection(.enabled)
                    switch loadPresentation {
                    case .loading:
                        ProgressView("Загрузка статьи…")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    case .unavailable:
                        ContentUnavailableView(
                            "Содержимое этого листа недоступно",
                            systemImage: "doc.badge.questionmark",
                            description: Text("Вернитесь к разделу и выберите статью с описанием или процедурой.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    case .content:
                        EmptyView()
                    }
                    if hasContents {
                        ArticleContents(blocks: fullArticle.blocks, isExpanded: $isContentsExpanded, scrollTo: { proxy.scrollTo($0, anchor: .top) })
                    }
                    ForEach(contentItems) { item in
                        switch item {
                        case let .block(block):
                            ArticleBlockView(block: block, article: fullArticle, findText: findText, openImage: openImage, openLink: openLink, highlightedAnchor: highlightedAnchor)
                        case let .note(note):
                            NoteCalloutView(note: note, article: fullArticle, findText: findText, openImage: openImage, openLink: openLink, highlightedAnchor: highlightedAnchor)
                        }
                    }
                    RelatedArticles(article: fullArticle)
                    Button("К началу", systemImage: "arrow.up") { withAnimation { proxy.scrollTo("article-top", anchor: .top) } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .accessibilityIdentifier("article-content")
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
        .task(id: article.id) {
            didRestoreReaderState = false
            isLoadingArticle = true
            loadedArticle = await store.loadArticle(id: article.id) ?? article
            isLoadingArticle = false
            recordVisit()
        }
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
        DispatchQueue.main.async { scroll(to: target, in: fullArticle, proxy: proxy) }
    }
    private func followLink(_ target: String, in currentArticle: ManualArticle, proxy: ScrollViewProxy) {
        let components = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let destination = store.article(path: String(components[0])) else { return }
        let anchor = components.count == 2 && !["000", "i000"].contains(String(components[1])) ? String(components[1]) : nil
        if destination.id == currentArticle.id, let anchor {
            scroll(to: anchor, in: currentArticle, proxy: proxy)
        } else {
            router.open(articleID: destination.id, anchor: anchor)
        }
    }
    private func scroll(to anchor: String, in fullArticle: ManualArticle, proxy: ScrollViewProxy) {
        let identifier = ArticleAnchorResolver.scrollIdentifier(for: anchor, in: fullArticle) ?? anchor
        highlightedAnchor = anchor
        if UIAccessibility.isReduceMotionEnabled {
            proxy.scrollTo(identifier, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(identifier, anchor: .top) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if highlightedAnchor == anchor { highlightedAnchor = nil }
        }
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
