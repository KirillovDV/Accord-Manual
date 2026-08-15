import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(ManualStore.self) private var store
    @Query private var bookmarks: [Bookmark]
    @Query private var profiles: [VehicleProfile]
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var filters = SearchFilters()
    @State private var searchTask: Task<Void, Never>?
    @State private var router = NavigationRouter(storageKey: "searchNavigationState")
    @AppStorage("searchHistory") private var storedHistory = "[]"
    private var queryHistory: [String] { (try? JSONDecoder().decode([String].self, from: Data(storedHistory.utf8))) ?? [] }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            List {
                if query.isEmpty {
                    if !queryHistory.isEmpty { Section("Недавние запросы") { ForEach(queryHistory.prefix(10), id: \.self) { phrase in Button(phrase, systemImage: "clock.arrow.circlepath") { query = phrase } }; Button("Очистить историю", role: .destructive) { storedHistory = "[]" } } }
                    Section("Популярные запросы") {
                        ForEach(["замена масла", "P0420", "ABS", "момент затяжки"], id: \.self) { phrase in
                            Button(phrase) { query = phrase }
                        }
                    }
                } else {
                    ForEach(SearchResult.SearchGroup.allCases, id: \.self) { group in
                        let groupResults = results.filter { $0.group == group }
                        if !groupResults.isEmpty {
                            Section(group.rawValue) {
                                ForEach(groupResults) { result in
                                    NavigationLink(value: ManualRoute.article(articleID: result.article.id, anchor: result.article.blocks.first(where: { $0.text.localizedCaseInsensitiveContains(result.matchedText ?? "") })?.anchor)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.article.title)
                                            Text(result.article.breadcrumbs.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
                                            HighlightedText(text: result.excerpt.replacingOccurrences(of: "⟦", with: "").replacingOccurrences(of: "⟧", with: ""), query: result.matchedText ?? "").font(.caption).lineLimit(3).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "DTC, момент, деталь или тема")
            .onSubmit(of: .search) { saveQuery() }
            .navigationDestination(for: ManualRoute.self) { route in
                if route.kind == .article, let article = store.summary(id: route.value) {
                    ArticleView(article: article, initialAnchor: route.anchor)
                } else {
                    ContentUnavailableView("Материал недоступен", systemImage: "doc.badge.exclamationmark")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Фильтры", systemImage: "line.3.horizontal.decrease.circle") {
                        Toggle("Только с изображениями", isOn: $filters.imagesOnly)
                        Toggle("Только сохранённые", isOn: $filters.savedOnly)
                        Picker("Кузов", selection: $filters.bodyCode) {
                            Text("Все").tag(String?.none)
                            ForEach(["CL7", "CL9", "CM1", "CM2", "CN1", "CN2"], id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        Picker("Год", selection: $filters.year) { Text("Все").tag(Int?.none); ForEach(2003...2008, id: \.self) { Text(String($0)).tag(Optional($0)) } }
                        Picker("Двигатель", selection: $filters.engineCode) { Text("Все").tag(String?.none); ForEach(["K20A6", "K20Z2", "K24A3", "N22A1"], id: \.self) { Text($0).tag(Optional($0)) } }
                        Picker("Трансмиссия", selection: $filters.transmission) { Text("Все").tag(String?.none); Text("АКП").tag(Optional("AT")); Text("МКП").tag(Optional("MT")) }
                        Picker("Тип материала", selection: $filters.manualType) { Text("Все").tag(String?.none); Text("Диагностика / DTC").tag(Optional("diagnostic")); Text("Процедуры").tag(Optional("procedure")); Text("Характеристики").tag(Optional("specification")) }
                    }
                }
            }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .onChange(of: filters.imagesOnly) { _, _ in scheduleSearch() }
            .onChange(of: filters.savedOnly) { _, _ in scheduleSearch() }
            .onChange(of: filters.bodyCode) { _, _ in scheduleSearch() }
            .onChange(of: filters.year) { _, _ in scheduleSearch() }
            .onChange(of: filters.engineCode) { _, _ in scheduleSearch() }
            .onChange(of: filters.transmission) { _, _ in scheduleSearch() }
            .onChange(of: filters.manualType) { _, _ in scheduleSearch() }
        }.environment(router)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await store.search(query, filters: filters, savedIDs: Set(bookmarks.map(\.articleID)))
            let profile = profiles.first
            let preference = SearchFilters(year: profile?.year, bodyCode: profile?.bodyCode, engineCode: profile?.engineCode, transmission: profile?.transmission)
            results = found.enumerated().sorted { lhs, rhs in
                let left = ManualStore.compatibilityScore(lhs.element.article, preference: preference)
                let right = ManualStore.compatibilityScore(rhs.element.article, preference: preference)
                return left == right ? lhs.offset < rhs.offset : left > right
            }.map(\.element)
        }
    }
    private func saveQuery() { let value = query.trimmingCharacters(in: .whitespacesAndNewlines); guard value.count > 1 else { return }; var history = queryHistory.filter { $0.localizedCaseInsensitiveCompare(value) != .orderedSame }; history.insert(value, at: 0); storedHistory = String(data: (try? JSONEncoder().encode(Array(history.prefix(20)))) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
}
