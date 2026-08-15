import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(ManualStore.self) private var store
    @Query private var profiles: [VehicleProfile]
    @Query private var settings: [AppSettings]
    @Query private var bookmarks: [Bookmark]
    @Query private var notes: [UserNote]
    @Environment(\.modelContext) private var context
    @State private var showDiagnostics = false
    @State private var exportDocument: ExportDocument?
    @AppStorage("appearance") private var selectedAppearance = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section("Автомобиль") {
                    Picker("Год", selection: year) {
                        Text("Не выбран").tag(Int?.none)
                        ForEach(2003...2008, id: \.self) { Text(String($0)).tag(Optional($0)) }
                    }
                    Picker("Кузов", selection: bodyCode) {
                        Text("Не выбран").tag(String?.none)
                        ForEach(["CL7", "CL9", "CM1", "CM2", "CN1", "CN2"], id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Двигатель", selection: engineCode) {
                        Text("Не выбран").tag(String?.none)
                        ForEach(["K20A6", "K20Z2", "K24A3", "N22A1"], id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Трансмиссия", selection: transmissionCode) {
                        Text("Не выбрана").tag(String?.none)
                        Text("Автоматическая").tag(Optional("AT"))
                        Text("Механическая").tag(Optional("MT"))
                    }
                }

                Section("Оформление") {
                    Picker("Тема", selection: appearance) {
                        Text("Системная").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    }
                }

                Section("Данные руководства") {
                    LabeledContent("Страниц", value: "\(store.metadata?.pageCount ?? store.articles.count)")
                    LabeledContent("Изображений", value: "\(store.metadata?.imageCount ?? 0)")
                    LabeledContent("Размер пакета", value: packageSize)
                    LabeledContent("Версия пакета", value: "\(store.metadata?.formatVersion ?? 0)")
                    Button("Локальная диагностика", systemImage: "stethoscope") { showDiagnostics = true }
                    Button("Экспорт заметок и избранного", systemImage: "square.and.arrow.up") { exportDocument = makeExport() }
                }

                Section {
                    if let emailURL = URL(string: "mailto:\(AppConfiguration.supportEmail)") {
                        Link(destination: emailURL) {
                            ContactRow(
                                title: "Email",
                                value: AppConfiguration.supportEmail,
                                systemImage: "envelope.fill"
                            )
                        }
                        .accessibilityIdentifier("feedback-email")
                        .accessibilityHint("Открывает установленный почтовый клиент")
                    }

                    if let telegramURL = URL(string: AppConfiguration.telegramWebURLString) {
                        Link(destination: telegramURL) {
                            ContactRow(
                                title: "Telegram",
                                value: "@\(AppConfiguration.telegramUsername)",
                                systemImage: "paperplane.fill"
                            )
                        }
                        .accessibilityIdentifier("feedback-telegram")
                        .accessibilityHint("Открывает Telegram или его веб-версию")
                    }
                } header: {
                    Text("Обратная связь")
                } footer: {
                    Text("Если Telegram не установлен, ссылка откроется в браузере.")
                }

                Section("Правовая информация") {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Политика конфиденциальности", systemImage: "hand.raised")
                    }
                    .accessibilityHint("Открывает сведения о локальном хранении и передаче данных")
                    Text("Источник: локальный Honda ESM ACCORD, русская документация 2003–2008 годов.")
                        .font(.footnote)
                    Text("Материалы предназначены для справочного использования. Соблюдайте заводские требования безопасности; владелец приложения не связан с Honda Motor Co., Ltd.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Ещё")
            .task { ensureModels() }
            .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
            .sheet(item: $exportDocument) { document in ShareSheet(items: [document.url]) }
        }
    }
    private var profile: VehicleProfile { profiles.first ?? VehicleProfile() }; private var appSettings: AppSettings { settings.first ?? AppSettings() }
    private var year: Binding<Int?> { Binding { profile.year } set: { profile.year = $0 } }; private var bodyCode: Binding<String?> { Binding { profile.bodyCode } set: { profile.bodyCode = $0 } }; private var engineCode: Binding<String?> { Binding { profile.engineCode } set: { profile.engineCode = $0 } }; private var transmissionCode: Binding<String?> { Binding { profile.transmission } set: { profile.transmission = $0 } }; private var appearance: Binding<String> { Binding { selectedAppearance } set: { selectedAppearance = $0; appSettings.appearance = $0 } }
    private func ensureModels() { if profiles.isEmpty { context.insert(VehicleProfile()) }; if settings.isEmpty { context.insert(AppSettings()) } }
    private var packageSize: String { guard let url = Bundle.main.url(forResource: "manual", withExtension: "sqlite", subdirectory: "ManualBundle"), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "—" }; return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    private func makeExport() -> ExportDocument? { var text = "Accord Manual — экспорт\n\nИзбранное:\n"; for bookmark in bookmarks { if let article = store.summary(id: bookmark.articleID) { text += "• \(article.title)\n" } }; text += "\nЗаметки:\n"; for note in notes { let title = store.summary(id: note.articleID)?.title ?? note.articleID; text += "\n## \(title)\n\(note.body)\n" }; let url = FileManager.default.temporaryDirectory.appendingPathComponent("Accord-Manual-Export.txt"); do { try text.write(to: url, atomically: true, encoding: .utf8); return ExportDocument(url: url) } catch { return nil } }
}

private struct ContactRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct ExportDocument: Identifiable { let id = UUID(); let url: URL }
private struct ShareSheet: UIViewControllerRepresentable { let items: [Any]; func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }; func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {} }
private struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManualStore.self) private var store
    @State private var report: LocalDiagnosticReport?
    @State private var exportDocument: ExportDocument?

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    Section("Состояние") {
                        LabeledContent("Пакет", value: report.packageStatus)
                        LabeledContent("Статей в каталоге", value: "\(report.catalogueArticleCount)")
                        LabeledContent("Разделов", value: "\(report.sectionCount)")
                        LabeledContent("Файлов медиа", value: "\(report.mediaFileCount)")
                    }
                    if !report.runtimeIssues.isEmpty {
                        Section("Проблемы текущей проверки") { ForEach(report.runtimeIssues, id: \.self) { Text($0) } }
                    }
                    Section("Диагностика импорта") {
                        if report.diagnostics.isEmpty { ContentUnavailableView("Проблем не найдено", systemImage: "checkmark.seal") }
                        else { ForEach(report.diagnostics) { diagnostic in VStack(alignment: .leading) { Text(diagnostic.message); Text(diagnostic.path).font(.caption).foregroundStyle(.secondary) } } }
                    }
                } else {
                    ContentUnavailableView("Проверка локальной базы", systemImage: "stethoscope", description: Text("Проверяем базу руководства и медиафайлы…"))
                }
            }
            .navigationTitle("Состояние базы")
            .task { refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Проверить снова", systemImage: "arrow.clockwise") { refresh() }
                        .accessibilityHint("Повторно проверяет локальную базу и медиафайлы")
                    Button("Экспортировать отчёт", systemImage: "square.and.arrow.up") { exportReport() }
                        .disabled(report == nil)
                        .accessibilityHint("Открывает системное меню для отправки текстового отчёта")
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $exportDocument) { document in ShareSheet(items: [document.url]) }
        }
    }

    private func refresh() { report = store.runLocalDiagnostics() }

    private func exportReport() {
        guard let report else { return }
        let formatter = ISO8601DateFormatter()
        let suffix = formatter.string(from: report.generatedAt).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Accord-Manual-Local-Diagnostics-\(suffix).txt")
        do {
            try report.formattedText.write(to: url, atomically: true, encoding: .utf8)
            exportDocument = ExportDocument(url: url)
        } catch { }
    }
}
