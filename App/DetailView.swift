import SwiftUI
import AVKit
import WebKit

struct DetailView: View {
    @StateObject private var model: PlayerModel
    @State private var showSite = false
    @State private var showDescription = false

    init(movie: Movie) { _model = StateObject(wrappedValue: PlayerModel(movie: movie)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    Color.black
                    if let player = model.player {
                        NativePlayer(player: player)
                    } else if model.resolving {
                        ProgressView("正在连接播放线路…")
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "play.circle.fill").font(.system(size: 46)).foregroundStyle(.mint)
                            Text("选择下方剧集开始播放").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if model.usingBackup { BackupNotice() }
                if let message = model.playbackMessage {
                    ErrorNotice(message: message) {
                        if let episode = model.selectedEpisode { model.play(episode) }
                    }
                    Button("在网站中登录 / 查看额度") { showSite = true }.font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.movie.title).font(.title2.bold()).textSelection(.enabled)
                    Text(model.movie.metadata).font(.subheadline).foregroundStyle(.secondary)
                    if let description = model.movie.description, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(showDescription ? nil : 3)
                        Button(showDescription ? "收起简介" : "展开简介") { showDescription.toggle() }
                            .font(.caption)
                    }
                }

                if model.lines.count > 1 {
                    HStack {
                        Text("播放线路").font(.headline)
                        Spacer()
                        Menu {
                            ForEach(model.lines) { line in
                                Button {
                                    model.chooseLine(line)
                                } label: {
                                    if line.id == model.selectedLineID { Label(line.name, systemImage: "checkmark") }
                                    else { Text(line.name) }
                                }
                            }
                        } label: {
                            Label(model.lines.first(where: { $0.id == model.selectedLineID })?.name ?? "选择线路",
                                  systemImage: "arrow.triangle.swap")
                                .font(.subheadline).lineLimit(1)
                        }
                    }
                }

                if let seasons = model.movie.seasons, seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(seasons.filter { $0.id != model.movie.id }) { season in
                                NavigationLink {
                                    DetailView(movie: Movie(id: season.id, title: season.title, posterUrl: model.movie.posterUrl,
                                        year: season.year, area: nil, remarks: nil, contentKind: model.movie.contentKind,
                                        description: nil, episodes: nil, episodePagination: nil,
                                        availableEpisodeCount: nil, seasons: nil, availability: nil))
                                } label: {
                                    Text(season.title + (season.year.map { "（\($0)）" } ?? ""))
                                        .font(.caption).padding(10).background(.white.opacity(0.06), in: Capsule())
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text("选集").font(.headline)
                    Spacer()
                    if let episode = model.selectedEpisode { Text(episode.label).font(.caption).foregroundStyle(.mint) }
                }
                if model.loading { ProgressView("正在加载剧集…").frame(maxWidth: .infinity) }
                if let message = model.message { ErrorNotice(message: message) { Task { await model.load() } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                    ForEach(model.episodes) { episode in
                        Button { model.play(episode) } label: {
                            Text(episode.label).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 4)
                                .background(model.selectedEpisode?.id == episode.id ? Color.mint.opacity(0.2) : .white.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(episode.token == nil)
                        .foregroundStyle(model.selectedEpisode?.id == episode.id ? Color.mint : Color.white)
                    }
                }
                if !model.loading && model.message == nil && model.episodes.isEmpty {
                    EmptyNotice(title: "暂无可播放剧集", symbol: "film", detail: "影片可能尚未更新，请稍后再来。")
                }
                if let message = model.episodeMessage { ErrorNotice(message: message) { Task { await model.moreEpisodes() } } }
                if model.hasMoreEpisodes {
                    Button { Task { await model.moreEpisodes() } } label: {
                        if model.loadingEpisodes { ProgressView() } else { Text("加载后续剧集") }
                    }.buttonStyle(.bordered).disabled(model.loadingEpisodes).frame(maxWidth: .infinity)
                }
            }.padding()
        }
        .background(Color(red: 0.035, green: 0.045, blue: 0.065))
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.episodes.isEmpty { await model.load() } }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showSite) { SiteAccountView() }
    }
}

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}

struct SiteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var origin: URL?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Group {
                if let origin { AccountWebView(url: origin) }
                else { ProgressView() }
            }
            .navigationTitle("网站账户").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saving = true
                        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                            for cookie in cookies where ["kanju17.com", "kanju21.com"].contains(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                                HTTPCookieStorage.shared.setCookie(cookie)
                            }
                            DispatchQueue.main.async { dismiss() }
                        }
                    }.disabled(saving)
                }
            }
        }
        .interactiveDismissDisabled()
        .task { origin = await KanjuAPI.shared.origin }
    }
}

struct AccountWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
}
