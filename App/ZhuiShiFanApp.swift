import SwiftUI

@main
struct ZhuiShiFanApp: App {
    @UIApplicationDelegateAdaptor(PlayerOrientationDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            BrowseView()
                .tint(.mint)
                .preferredColorScheme(.dark)
        }
    }
}

final class PlayerOrientationDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

struct BrowseView: View {
    @StateObject private var model = BrowseModel()
    @StateObject private var browserSession = BrowserSession()
    @State private var text = ""
    @State private var query = ""
    @State private var showAccount = false
    @State private var showBrowser = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.usingBackup { BackupNotice() }
                    if model.loading {
                        ProgressView("正在加载影片…").frame(maxWidth: .infinity).padding(.top, 60)
                    } else if query.isEmpty {
                        ForEach(model.sections) { section in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(section.title).font(.title3.bold())
                                MovieGrid(movies: section.cards ?? [])
                            }
                        }
                        if model.sections.isEmpty && model.message == nil {
                            EmptyNotice(title: "暂无影片", symbol: "film", detail: "下拉刷新，再试一次。")
                        }
                    } else {
                        Text("搜索结果").font(.title3.bold())
                        MovieGrid(movies: model.results)
                        if model.results.isEmpty && model.message == nil {
                            EmptyNotice(title: "没有找到影片", symbol: "magnifyingglass", detail: "试试更短的片名或其他关键词。")
                        }
                    }
                    if let message = model.message {
                        ErrorNotice(message: message) {
                            Task {
                                if model.sections.isEmpty && model.results.isEmpty { await model.load(query) }
                                else { await model.loadMore() }
                            }
                        }
                    }
                    if model.hasMore {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            if model.loadingMore { ProgressView() } else { Text("加载更多影片") }
                        }
                        .buttonStyle(.bordered).disabled(model.loadingMore)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.035, green: 0.045, blue: 0.065))
            .navigationTitle("追视番通用")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showBrowser = true } label: { Label("浏览器", systemImage: "globe") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAccount = true } label: { Label("网站账户", systemImage: "person.crop.circle") }
                        .accessibilityIdentifier("accountButton")
                }
            }
            .sheet(isPresented: $showAccount, onDismiss: { Task { await model.load(query) } }) { SiteAccountView() }
            .sheet(isPresented: $showBrowser, onDismiss: { browserSession.hide() }) {
                BrowserView(session: browserSession)
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索电影、电视剧、动漫")
            .onSubmit(of: .search) { query = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .onChange(of: text) { if $0.isEmpty { query = "" } }
            .task(id: query) { await model.load(query) }
            .refreshable { await model.load(query) }
        }
    }
}

struct MovieGrid: View {
    let movies: [Movie]
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 12)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(movies) { movie in
                NavigationLink { DetailView(movie: movie) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        PosterView(url: movie.posterUrl)
                            .aspectRatio(2 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .bottomLeading) {
                                if let remarks = movie.remarks, !remarks.isEmpty {
                                    Text(remarks).font(.caption2).lineLimit(1)
                                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.black.opacity(0.65))
                                        .clipShape(RoundedRectangle(cornerRadius: 5)).padding(4)
                                }
                            }
                        Text(movie.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            .frame(height: 40, alignment: .topLeading)
                        Text([movie.year.map(String.init), movie.area].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(movie.title)，\(movie.remarks ?? "查看详情")")
            }
        }
    }
}

struct PosterView: View {
    let url: String?
    var body: some View {
        Color.white.opacity(0.06).overlay {
            AsyncImage(url: url.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
            }
        }.clipped()
    }
}

struct BackupNotice: View {
    var body: some View {
        Label("已连接备用站 kanju21.com", systemImage: "network")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct ErrorNotice: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            Button("重试", action: retry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EmptyNotice: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle)
            Text(title).font(.headline)
            Text(detail).font(.subheadline)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}
