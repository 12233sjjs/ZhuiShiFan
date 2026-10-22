import Foundation

struct AccountProfile: Decodable {
    let authenticated: Bool
    let displayName: String?
}
struct LoginResponse: Decodable {}

struct Movie: Decodable, Identifiable {
    let id: String
    let title: String
    let posterUrl: String?
    let year: Int?
    let area: String?
    let remarks: String?
    let contentKind: String?
    let description: String?
    let episodes: [Episode]?
    let episodePagination: EpisodePagination?
    let availableEpisodeCount: Int?
    let seasons: [Season]?
    let availability: Availability?

    var metadata: String {
        [year.map(String.init), area, remarks].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct Availability: Decodable {
    let playable: Bool?
    let label: String?
}

struct Season: Decodable, Identifiable {
    let variantId: String
    let title: String
    let year: Int?
    var id: String { variantId }
}

struct Episode: Decodable, Identifiable, Equatable {
    let id: String
    let number: Int?
    let title: String?
    let token: String?
    var label: String { title ?? number.map { "第\($0)集" } ?? "播放" }
}

struct EpisodePagination: Decodable {
    let offset: Int
    let limit: Int
    let returnedCount: Int
    let totalCount: Int?
    let hasMore: Bool?
    var nextOffset: Int { offset + returnedCount }
}

struct EpisodePage: Decodable {
    let episodes: [Episode]
    let episodePagination: EpisodePagination
}

struct Feed: Decodable {
    let sections: [FeedSection]
    let nextCursor: String?
    let meta: FeedMeta?
    var cursor: String? { nextCursor ?? meta?.nextCursor }
}

struct FeedMeta: Decodable { let nextCursor: String? }

struct FeedSection: Decodable, Identifiable {
    let id: String
    let title: String
    let cards: [Movie]?
}

struct BrowsePage: Decodable {
    let cards: [Movie]
    let pagination: BrowsePagination
}

struct BrowsePagination: Decodable {
    let page: Int
    let hasMore: Bool
    let nextPage: Int?
    let nextCursor: String?
}

struct Playback: Decodable {
    let lineOptions: [PlaybackLine]
}

struct ResolvedPlayback: Decodable { let line: PlaybackLine }

struct PlaybackLine: Decodable, Identifiable {
    let id: String
    let label: String?
    let displayLabel: String?
    let url: String?
    let urlKind: String?
    let resolveTicket: String?
    let resolveRequired: Bool?
    let selected: Bool?
    let headers: [String: String]?
    var name: String { displayLabel ?? label ?? "播放线路" }
    var ticket: String? {
        if let resolveTicket, !resolveTicket.isEmpty { return resolveTicket }
        if let url, url.hasPrefix("resolve://") { return String(url.dropFirst(10)) }
        if urlKind == "resolve_ticket" { return url }
        return nil
    }
    var mediaURL: URL? {
        guard let url, let value = URL(string: url),
              ["https", "http"].contains(value.scheme?.lowercased() ?? "") else { return nil }
        return value
    }
}

struct SiteError: LocalizedError {
    let message: String
    let status: Int?
    var errorDescription: String? { message }
}
