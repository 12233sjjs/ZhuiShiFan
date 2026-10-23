import SwiftUI
import WebKit
import CFNetwork

struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var address = ""
    @State private var vpn = false
    @State private var showCredits = false
    @StateObject private var browser = BrowserState()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("输入网址", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(open)
                    Button(action: open) { Image(systemName: "arrow.right.circle") }
                        .accessibilityLabel("打开网址")
                        .disabled(!browser.filterReady)
                }.padding()
                if vpn {
                    BrowserWebView(state: browser)
                } else {
                    Spacer()
                    Text("请先连接 VPN").font(.headline)
                    Text("检测可能无法识别部分 VPN").font(.caption).foregroundStyle(.secondary).padding(8)
                    Button("重新检测") { checkVPN() }
                    Spacer()
                }
                if let error = browser.error {
                    Text(error).font(.caption).foregroundStyle(.secondary).padding()
                }
                HStack {
                    Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("后退").disabled(!vpn || !browser.canGoBack)
                    Spacer()
                    Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("前进").disabled(!vpn || !browser.canGoForward)
                    Spacer()
                    Button { if checkVPN() { browser.webView.reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新").disabled(!vpn)
                }.padding()
            }
            .navigationTitle("浏览器").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } } }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showCredits = true } label: { Image(systemName: "shield.lefthalf.filled") }
                        .accessibilityLabel("广告过滤来源")
                }
            }
            .alert("广告过滤", isPresented: $showCredits) {
                Button("好", role: .cancel) {}
            } message: {
                Text("AdAway 默认域名规则，作者 Kicelo、Dominik Schuermann 及项目贡献者。CC BY 3.0。规则转为 WebKit 过滤格式。\n来源：https://github.com/AdAway/adaway.github.io\n许可：https://creativecommons.org/licenses/by/3.0/\n无法移除视频内嵌广告。")
            }
            .onAppear { checkVPN() }
            .onChange(of: scenePhase) { if $0 == .active { checkVPN() } }
            .task {
                while !Task.isCancelled {
                    checkVPN()
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                }
            }
        }
    }

    @discardableResult private func checkVPN() -> Bool {
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
        let scoped = settings?["__SCOPED__"] as? [String: Any] ?? [:]
        vpn = scoped.keys.contains { name in
            ["utun", "ipsec", "ppp", "tap", "tun"].contains { name.hasPrefix($0) }
        }
        if !vpn { browser.webView.stopLoading() }
        return vpn
    }

    private func open() {
        guard checkVPN(), browser.filterReady else { return }
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = input.contains("://") ? input : "https://" + input
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else {
            browser.error = "请输入有效的 http 或 https 网址"
            return
        }
        browser.error = nil
        browser.webView.load(URLRequest(url: url))
    }
}

final class BrowserState: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var error: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var filterReady = false
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in self?.canGoBack = view.canGoBack },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in self?.canGoForward = view.canGoForward }
        ]
        AdBlocking.install(on: webView) { [weak self] error in
            self?.filterReady = error == nil
            if let error { self?.error = "广告过滤加载失败：" + error.localizedDescription }
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated,
           let scheme = navigationAction.request.url?.scheme, ["http", "https"].contains(scheme) {
            webView.load(navigationAction.request)
        }
        return nil
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error.localizedDescription
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let state: BrowserState
    func makeUIView(context: Context) -> WKWebView { state.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
