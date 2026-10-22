import Foundation

@MainActor
final class BrowseModel: ObservableObject {
    @Published var sections: [FeedSection] = []
    @Published var results: [Movie] = []
    @Published var loading = false
    @Published var loadingMore = false
    @Published var message: String?
    @Published var hasMore = false
    @Published var usingBackup = false
    private var query = ""
    private var cursor: String?
    private var nextPage = 1
    private var revision = UUID()

    func load(_ text: String) async {
        let revision = UUID()
        self.revision = revision
        let newQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if newQuery != query { sections = []; results = [] }
        query = newQuery
        loading = true
        loadingMore = false
        message = nil
        cursor = nil
        hasMore = false
        nextPage = 1
        do {
            if query.isEmpty {
                let feed = try await KanjuAPI.shared.home()
                try Task.checkCancellation()
                guard self.revision == revision else { return }
                sections = feed.sections.filter { !($0.cards ?? []).isEmpty }
                cursor = feed.cursor
                hasMore = cursor != nil
            } else {
                let page = try await KanjuAPI.shared.search(query)
                try Task.checkCancellation()
                guard self.revision == revision else { return }
                apply(page, append: false)
            }
        } catch {
            guard self.revision == revision else { return }
            if !Task.isCancelled { message = error.localizedDescription }
            else if sections.isEmpty && results.isEmpty { message = "加载已中断，请点击重试。" }
        }
        guard self.revision == revision else { return }
        usingBackup = await KanjuAPI.shared.origin == KanjuAPI.backupOrigin
        loading = false
    }

    func loadMore() async {
        guard hasMore, !loading, !loadingMore else { return }
        let revision = revision
        loadingMore = true
        message = nil
        do {
            if query.isEmpty {
                let feed = try await KanjuAPI.shared.home(cursor: cursor)
                try Task.checkCancellation()
                guard self.revision == revision else { return }
                for section in feed.sections {
                    guard let cards = section.cards, !cards.isEmpty else { continue }
                    if let index = sections.firstIndex(where: { $0.id == section.id }) {
                        var seen = Set((sections[index].cards ?? []).map(\.id))
                        let merged = (sections[index].cards ?? []) + cards.filter { seen.insert($0.id).inserted }
                        sections[index] = FeedSection(id: section.id, title: section.title, cards: merged)
                    } else { sections.append(section) }
                }
                hasMore = feed.cursor != nil && feed.cursor != cursor
                cursor = feed.cursor
            } else {
                let page = try await KanjuAPI.shared.search(query, page: nextPage, cursor: cursor)
                try Task.checkCancellation()
                guard self.revision == revision else { return }
                apply(page, append: true)
            }
        } catch {
            guard self.revision == revision else { return }
            if !Task.isCancelled { message = error.localizedDescription }
        }
        guard self.revision == revision else { return }
        usingBackup = await KanjuAPI.shared.origin == KanjuAPI.backupOrigin
        loadingMore = false
    }

    private func apply(_ page: BrowsePage, append: Bool) {
        var seen = Set(append ? results.map(\.id) : [])
        let cards = page.cards.filter { seen.insert($0.id).inserted }
        results = append ? results + cards : cards
        hasMore = page.pagination.hasMore && (!append || !cards.isEmpty)
        nextPage = page.pagination.nextPage ?? page.pagination.page + 1
        cursor = page.pagination.nextCursor
    }
}
