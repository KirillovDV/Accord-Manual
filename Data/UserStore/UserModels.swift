import Foundation
import SwiftData
import Observation

@Model final class Bookmark { @Attribute(.unique) var articleID: String; var createdAt: Date; init(articleID: String, createdAt: Date = .now) { self.articleID = articleID; self.createdAt = createdAt } }
@Model final class UserNote { var id = UUID(); var articleID: String; var body: String; var createdAt: Date; var updatedAt: Date; init(articleID: String, body: String, createdAt: Date = .now) { self.articleID = articleID; self.body = body; self.createdAt = createdAt; self.updatedAt = createdAt } }
@Model final class ReadingHistoryEntry { @Attribute(.unique) var articleID: String; var lastOpenedAt: Date; var scrollAnchor: String?; init(articleID: String, scrollAnchor: String? = nil) { self.articleID = articleID; self.scrollAnchor = scrollAnchor; self.lastOpenedAt = .now } }
@Model final class ChecklistState { @Attribute(.unique) var key: String; var complete: Bool; init(key: String, complete: Bool = false) { self.key = key; self.complete = complete } }
@Model final class VehicleProfile { var year: Int?; var bodyCode: String?; var engineCode: String?; var transmission: String?; init(year: Int? = nil, bodyCode: String? = nil, engineCode: String? = nil, transmission: String? = nil) { self.year = year; self.bodyCode = bodyCode; self.engineCode = engineCode; self.transmission = transmission } }
@Model final class AppSettings { var appearance: String; var fontScale: Double; init(appearance: String = "system", fontScale: Double = 1) { self.appearance = appearance; self.fontScale = fontScale } }

struct ManualRoute: Hashable, Codable {
    enum Kind: String, Codable { case article, category, section }
    let kind: Kind
    let value: String
    let anchor: String?
    var articleID: String? { kind == .article ? value : nil }
    static func article(articleID: String, anchor: String?) -> Self { .init(kind: .article, value: articleID, anchor: anchor) }
    static func category(_ value: String) -> Self { .init(kind: .category, value: value, anchor: nil) }
    static func section(_ value: String) -> Self { .init(kind: .section, value: value, anchor: nil) }
}

struct ArticleReaderState: Equatable {
    var scrollAnchor: String?
    var expandedBlockIDs: Set<String>

    init(scrollAnchor: String? = nil, expandedBlockIDs: Set<String> = []) {
        self.scrollAnchor = scrollAnchor
        self.expandedBlockIDs = expandedBlockIDs
    }
}

@Observable @MainActor final class NavigationRouter {
    private let storageKey: String?
    var path: [ManualRoute] {
        didSet {
            guard !isUpdatingPath else { return }
            if path.count < oldValue.count, Array(oldValue.prefix(path.count)) == path {
                forwardPath.append(contentsOf: oldValue.dropFirst(path.count).reversed())
            } else if path != oldValue {
                forwardPath.removeAll()
            }
            persist()
        }
    }
    private(set) var forwardPath: [ManualRoute]
    private var readerStates: [String: ArticleReaderState] = [:]
    private var isUpdatingPath = false

    init(storageKey: String? = nil) {
        self.storageKey = storageKey
        let resetsStoredNavigation = ProcessInfo.processInfo.environment["ACCORD_UI_TEST_RESET_NAVIGATION"] == "1"
        if !resetsStoredNavigation, let storageKey, let data = UserDefaults.standard.data(forKey: storageKey),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            path = Array(state.path.suffix(100))
            forwardPath = Array(state.forwardPath.suffix(100))
        } else {
            path = []
            forwardPath = []
        }
    }

    var navigationPath: [ManualRoute] { path }
    var currentRoute: ManualRoute? { path.last }
    var canGoBack: Bool { !path.isEmpty }
    var canGoForward: Bool { !forwardPath.isEmpty }

    func open(_ route: ManualRoute) {
        guard path.last != route else { return }
        isUpdatingPath = true
        if route.kind == .article, path.last?.articleID == route.articleID {
            path[path.count - 1] = route
        } else {
            path.append(route)
        }
        if path.count > 100 { path.removeFirst(path.count - 100) }
        forwardPath.removeAll()
        isUpdatingPath = false
        persist()
    }

    func open(articleID: String, anchor: String? = nil) { open(.article(articleID: articleID, anchor: anchor)) }

    func saveReaderState(articleID: String, scrollAnchor: String?, expandedBlockIDs: Set<String>) {
        readerStates[articleID] = ArticleReaderState(scrollAnchor: scrollAnchor, expandedBlockIDs: expandedBlockIDs)
    }

    func readerState(for articleID: String) -> ArticleReaderState? {
        readerStates[articleID]
    }

    @discardableResult func goBack() -> ManualRoute? {
        guard !path.isEmpty else { return nil }
        setPath(Array(path.dropLast()))
        return path.last
    }

    @discardableResult func goForward() -> ManualRoute? {
        guard let route = forwardPath.popLast() else { return nil }
        isUpdatingPath = true
        path.append(route)
        isUpdatingPath = false
        persist()
        return route
    }

    func setPath(_ newPath: [ManualRoute]) {
        isUpdatingPath = true
        if newPath.count < path.count, Array(path.prefix(newPath.count)) == newPath {
            forwardPath.append(contentsOf: path.dropFirst(newPath.count).reversed())
        } else if newPath != path {
            forwardPath.removeAll()
        }
        path = Array(newPath.suffix(100))
        isUpdatingPath = false
        persist()
    }

    /// Starts a new root route while keeping the detail NavigationStack empty.
    /// A sidebar selection is not part of that stack, so its previous forward
    /// history must not be offered for the newly selected root material.
    func replacePath(_ newPath: [ManualRoute]) {
        isUpdatingPath = true
        path = Array(newPath.suffix(100))
        forwardPath.removeAll()
        isUpdatingPath = false
        persist()
    }

    private func persist() {
        guard let storageKey, let data = try? JSONEncoder().encode(PersistedState(path: path, forwardPath: forwardPath)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private struct PersistedState: Codable { let path: [ManualRoute]; let forwardPath: [ManualRoute] }
}
