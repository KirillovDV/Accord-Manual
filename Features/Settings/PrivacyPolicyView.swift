import SwiftUI

enum PrivacyPolicy {
    static let appPrivacySummary = "Данные не собираются"
    static let tracksUsers = false
    static let inAppText = """
    Accord Manual работает офлайн. Содержимое руководства, изображения, поисковый индекс, избранное, заметки, история чтения, настройки и профиль автомобиля хранятся только на устройстве.

    Приложение не создаёт учётную запись, не использует аналитику или рекламу, не отслеживает действия пользователя и не отправляет персональные данные на серверы разработчика.

    Когда вы сами выбираете экспорт заметок, закладок или PDF, файл передаётся только выбранному вами системному действию «Поделиться». Содержание файла не отправляется разработчику.

    Для вопросов о конфиденциальности напишите: \(AppConfiguration.supportEmail)
    """
}

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Кратко") {
                Label(PrivacyPolicy.appPrivacySummary, systemImage: "hand.raised.fill")
                Label("Отслеживание пользователей не используется", systemImage: "eye.slash.fill")
            }

            Section("Какие данные остаются на устройстве") {
                Text("Избранное, заметки, история чтения, состояние чек-листов, профиль автомобиля и настройки оформления.")
                Text("Эти данные нужны только для работы функций приложения и не покидают устройство автоматически.")
            }

            Section("Передача данных") {
                Text("Приложение не обращается к сети для работы руководства и не передаёт разработчику данные пользователя.")
                Text("Экспорт PDF, заметок и избранного запускается только по вашему действию через системное меню «Поделиться».")
            }

            Section("Контакты") {
                if let emailURL = URL(string: "mailto:\(AppConfiguration.supportEmail)") {
                    Link(AppConfiguration.supportEmail, destination: emailURL)
                }
            }

            Section {
                Text("Дата вступления в силу: 15 августа 2026 г.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Политика конфиденциальности")
        .navigationBarTitleDisplayMode(.inline)
    }
}
