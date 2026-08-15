import SwiftUI
import SwiftData

struct SavedView: View {
    @Environment(ManualStore.self) private var store; @Environment(\.modelContext) private var context; @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]; @Query(sort: \UserNote.updatedAt, order: .reverse) private var notes: [UserNote]; @Query(sort: \ReadingHistoryEntry.lastOpenedAt, order: .reverse) private var history: [ReadingHistoryEntry]; @State private var segment = 0; @State private var query = ""; @State private var router = NavigationRouter(storageKey: "savedNavigationState")
    var body: some View { @Bindable var router = router; NavigationStack(path: $router.path) { VStack { Picker("Сохранённое", selection: $segment) { Text("Избранное").tag(0); Text("Заметки").tag(1); Text("История").tag(2) }.pickerStyle(.segmented).padding([.horizontal, .top]); List { switch segment { case 0: savedRows(bookmarks.map(\.articleID), empty: "Нет избранных материалов", delete: deleteBookmark); case 1: ForEach(notes.filter { query.isEmpty || $0.body.localizedCaseInsensitiveContains(query) }) { note in if let article = store.summary(id: note.articleID) { NavigationLink(value: ManualRoute.article(articleID: article.id, anchor: nil)) { VStack(alignment: .leading) { Text(article.title); Text(note.body).lineLimit(2).foregroundStyle(.secondary) } }.swipeActions { Button(role: .destructive) { context.delete(note) } label: { Label("Удалить", systemImage: "trash") } } } }; case 2: savedRows(history.map(\.articleID), empty: "История пока пуста", delete: deleteHistory); default: EmptyView() } }.navigationDestination(for: ManualRoute.self) { route in if route.kind == .article, let article = store.summary(id: route.value) { ArticleView(article: article, initialAnchor: route.anchor) } else { ContentUnavailableView("Материал недоступен", systemImage: "doc.badge.exclamationmark") } } }.navigationTitle("Сохранённое").searchable(text: $query, prompt: "Поиск сохранённого") }.environment(router) }
    @ViewBuilder private func savedRows(_ ids: [String], empty: String, delete: @escaping (String) -> Void) -> some View { let articles = ids.compactMap { store.summary(id: $0) }.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }; if articles.isEmpty { ContentUnavailableView(empty, systemImage: "bookmark") } else { ForEach(articles) { article in NavigationLink(value: ManualRoute.article(articleID: article.id, anchor: nil)) { Text(article.title) }.swipeActions { Button(role: .destructive) { delete(article.id) } label: { Label("Удалить", systemImage: "trash") } } } } }
    private func deleteBookmark(_ articleID: String) { if let item = bookmarks.first(where: { $0.articleID == articleID }) { context.delete(item) } }
    private func deleteHistory(_ articleID: String) { if let item = history.first(where: { $0.articleID == articleID }) { context.delete(item) } }
}

struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let article: ManualArticle
    let existing: UserNote?
    @State private var noteBody = ""
    var body: some View {
        NavigationStack {
            TextEditor(text: $noteBody).padding().navigationTitle("Заметка")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            if let existing { existing.body = noteBody; existing.updatedAt = .now }
                            else if !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { context.insert(UserNote(articleID: article.id, body: noteBody)) }
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                }
                .onAppear { noteBody = existing?.body ?? "" }
        }
    }
}
