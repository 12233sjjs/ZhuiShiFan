import AVKit

@MainActor
final class PlayerModel: ObservableObject {
    @Published var movie: Movie
    @Published var episodes: [Episode] = []
    @Published var lines: [PlaybackLine] = []
    @Published var selectedEpisode: Episode?
    @Published var selectedLineID: String?
    @Published var player: AVPlayer?
    @Published var loading = false
    @Published var resolving = false
    @Published var loadingEpisodes = false
    @Published var message: String?
    @Published var playbackMessage: String?
    @Published var episodeMessage: String?
    @Published var hasMoreEpisodes = false
    @Published var usingBackup = false
    private var nextOffset = 0
    private var playbackTask: Task<Void, Never>?
    private var observation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var generation = UUID()

    init(movie: Movie) { self.movie = movie }

    deinit {
        playbackTask?.cancel()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }

    func load() async {
        guard !loading else { return }
        loading = true
        message = nil
        do {
            let detail = try await KanjuAPI.shared.detail(movie.id)
            try Task.checkCancellation()
            movie = detail
            episodes = detail.episodes ?? []
            nextOffset = detail.episodePagination?.nextOffset ?? episodes.count
            hasMoreEpisodes = detail.episodePagination?.hasMore ?? false
            if episodes.isEmpty {
                let page = try await KanjuAPI.shared.episodes(movie.id, offset: 0)
                try Task.checkCancellation()
                episodes = page.episodes
                nextOffset = page.episodePagination.nextOffset
                hasMoreEpisodes = page.episodePagination.hasMore ?? false
            }
        } catch {
            if !Task.isCancelled { message = error.localizedDescription }
        }
        usingBackup = await KanjuAPI.shared.origin == KanjuAPI.backupOrigin
        loading = false
    }

    func moreEpisodes() async {
        guard hasMoreEpisodes, !loadingEpisodes else { return }
        loadingEpisodes = true
        episodeMessage = nil
        do {
            let page = try await KanjuAPI.shared.episodes(movie.id, offset: nextOffset)
            try Task.checkCancellation()
            var seen = Set(episodes.map(\.id))
            episodes += page.episodes.filter { seen.insert($0.id).inserted }
            hasMoreEpisodes = (page.episodePagination.hasMore ?? false) && page.episodePagination.nextOffset > nextOffset
            nextOffset = page.episodePagination.nextOffset
        } catch {
            if !Task.isCancelled { episodeMessage = error.localizedDescription }
        }
        loadingEpisodes = false
    }

    func play(_ episode: Episode) {
        stop()
        let generation = generation
        selectedEpisode = episode
        selectedLineID = nil
        lines = []
        playbackMessage = nil
        resolving = true
        playbackTask = Task {
            do {
                let available = try await KanjuAPI.shared.lines(for: episode, movie: movie)
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                lines = available
                let line = available.first(where: { $0.selected == true }) ?? available[0]
                selectedLineID = line.id
                let resolved = try await KanjuAPI.shared.resolve(line)
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                install(resolved)
            } catch {
                guard self.generation == generation else { return }
                if !Task.isCancelled { playbackMessage = error.localizedDescription }
            }
            guard self.generation == generation else { return }
            usingBackup = await KanjuAPI.shared.origin == KanjuAPI.backupOrigin
            resolving = false
        }
    }

    func chooseLine(_ line: PlaybackLine) {
        stop()
        let generation = generation
        selectedLineID = line.id
        playbackMessage = nil
        resolving = true
        playbackTask = Task {
            do {
                let resolved = try await KanjuAPI.shared.resolve(line)
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                install(resolved)
            } catch {
                guard self.generation == generation else { return }
                if !Task.isCancelled { playbackMessage = error.localizedDescription }
            }
            guard self.generation == generation else { return }
            usingBackup = await KanjuAPI.shared.origin == KanjuAPI.backupOrigin
            resolving = false
        }
    }

    private func install(_ line: PlaybackLine) {
        guard let url = line.mediaURL else { return }
        let options: [String: Any] = line.headers.map { ["AVURLAssetHTTPHeaderFieldsKey": $0] } ?? [:]
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        let player = AVPlayer(playerItem: item)
        self.player = player
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, self.player?.currentItem === item else { return }
                if item.status == .failed {
                    self.playbackMessage = "此线路播放失败，请重试或选择其他线路。\n" + (item.error?.localizedDescription ?? "")
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.playbackMessage = "播放中断，请重试或切换线路。" }
            }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func stop() {
        generation = UUID()
        playbackTask?.cancel()
        playbackTask = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        observation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        resolving = false
    }
}
