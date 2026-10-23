import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCredits = false
    @State private var showTabs = false

    var body: some View {
        NavigationStack {
            BrowserPage(browser: session.active, session: session, showTabs: { showTabs = true })
                .id(session.active.id)
                .navigationTitle("浏览器").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") { session.hide(); dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showCredits = true } label: { Image(systemName: "shield.lefthalf.filled") }
                            .accessibilityLabel("广告过滤来源")
                    }
                }
                .alert("广告过滤", isPresented: $showCredits) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text("AdAway：Kicelo、Dominik Schuermann 及贡献者，CC BY 3.0。\nhttps://github.com/AdAway/adaway.github.io\nhttps://creativecommons.org/licenses/by/3.0/\nKa-Block：David Graham、Josh Peek，MIT。完整许可随应用打包。\nhttps://github.com/dgraham/Ka-Block\n已增加广告路径过滤和明确广告元素隐藏；无法删除视频内嵌广告。")
                }
                .sheet(isPresented: $showTabs) {
                    NavigationStack {
                        List {
                            ForEach(session.tabs) { tab in
                                BrowserTabRow(tab: tab, selected: session.selectedID == tab.id,
                                              select: { session.select(tab); showTabs = false },
                                              close: { session.close(tab) })
                            }
                        }
                        .navigationTitle("标签页")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { session.addTab(); showTabs = false } label: { Image(systemName: "plus") }
                                    .accessibilityLabel("新建标签页")
                            }
                            ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { showTabs = false } }
                        }
                    }
                }
                .onAppear { session.refreshVPN(); session.active.restoreIfNeeded() }
                .onDisappear { session.save() }
                .onChange(of: scenePhase) { if $0 == .active { session.refreshVPN() } }
        }
    }
}

private struct BrowserPage: View {
    @ObservedObject var browser: BrowserState
    @ObservedObject var session: BrowserSession
    let showTabs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("输入网址", text: $browser.address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { open() }
                if !browser.filterReady && browser.error == nil { ProgressView() }
                Button(action: open) { Image(systemName: "arrow.right.circle") }
                    .accessibilityLabel("打开网址").disabled(!browser.filterReady)
            }.padding()
            if session.vpn {
                BrowserWebView(state: browser)
            } else {
                Spacer()
                Text("请先连接 VPN").font(.headline)
                Text("检测可能无法识别部分 VPN").font(.caption).foregroundStyle(.secondary).padding(8)
                Button("重新检测") { session.refreshVPN(); browser.restoreIfNeeded() }
                Spacer()
            }
            if let error = browser.error {
                Text(error).font(.caption).foregroundStyle(.secondary).padding().textSelection(.enabled)
            }
            HStack {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("后退").disabled(!session.vpn || !browser.canGoBack)
                Spacer()
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("前进").disabled(!session.vpn || !browser.canGoForward)
                Spacer()
                Button {
                    session.refreshVPN()
                    if session.vpn { browser.webView.reload() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新").disabled(!session.vpn || !browser.filterReady)
                Spacer()
                Button(action: showTabs) { Label("\(session.tabs.count)", systemImage: "square.on.square") }
                    .accessibilityLabel("标签页，\(session.tabs.count) 个")
                Spacer()
                Button { session.addTab() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建标签页")
            }.padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    session.refreshVPN()
                    browser.requestPlayback()
                } label: { Label("窗口播放器", systemImage: "play.rectangle") }
                    .disabled(!session.vpn || !browser.filterReady || browser.findingVideo)
                    .accessibilityIdentifier("browserPlayerButton")
            }
        }
        .fullScreenCover(item: $browser.playback, onDismiss: { browser.stopPlayback() }) { playback in
            BrowserPlaybackView(playback: playback) { browser.stopPlayback() }
        }
        .onAppear { browser.restoreIfNeeded() }
        .onChange(of: session.vpn) { if $0 { browser.restoreIfNeeded() } }
    }

    private func open() {
        session.refreshVPN()
        browser.openAddress()
    }
}

private struct BrowserTabRow: View {
    @ObservedObject var tab: BrowserState
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack {
            Button(action: select) {
                HStack {
                    Image(systemName: selected ? "checkmark.circle.fill" : "globe")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tab.title).lineLimit(1)
                        Text(tab.lastURL?.host ?? "空白页").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("关闭此标签页")
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let state: BrowserState
    func makeUIView(context: Context) -> WKWebView { state.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
