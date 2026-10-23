import WebKit
import Combine

final class BrowserState: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView
    @Published var address: String
    @Published var title = "新标签页"
    @Published var error: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var filterReady = false
    @Published var findingVideo = false
    @Published var playback: BrowserPlayback?
    var lastURL: URL?
    var networkAllowed = false {
        didSet {
            if !networkAllowed {
                generation = UUID()
                findingVideo = false
                webView.stopLoading()
                pauseWebMedia()
                stopPlayback()
            }
        }
    }
    var onChange: (() -> Void)?
    var onOpenTab: ((URL) -> Void)?
    private var restoredURL: URL?
    private var observations: [NSKeyValueObservation] = []
    private(set) var videos: [BrowserVideo] = []
    private var unsupportedMedia = false
    private var mediaBridge: BrowserMediaBridge?
    private var generation = UUID()

    init(id: UUID = UUID(), restoredURL: URL? = nil) {
        self.id = id
        self.lastURL = restoredURL
        self.restoredURL = restoredURL
        self.address = restoredURL?.absoluteString ?? ""
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(source: BrowserMedia.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let bridge = BrowserMediaBridge(owner: self)
        mediaBridge = bridge
        webView.configuration.userContentController.add(bridge, name: "browserMedia")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in self?.canGoBack = view.canGoBack },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in self?.canGoForward = view.canGoForward },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                if let title = view.title, !title.isEmpty { self?.title = title }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                guard let self, let url = view.url, BrowserMedia.mediaURL(url.absoluteString) != nil else { return }
                self.lastURL = url
                self.address = url.absoluteString
                self.onChange?()
            }
        ]
        AdBlocking.install(on: webView) { [weak self] error in
            self?.filterReady = error == nil
            if let error { self?.error = "广告过滤加载失败：" + error.localizedDescription }
            self?.restoreIfNeeded()
        }
    }

    func openAddress() {
        guard networkAllowed, filterReady else { return }
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = input.contains("://") ? input : "https://" + input
        guard let url = BrowserMedia.mediaURL(value) else {
            error = "请输入有效的 http 或 https 网址"
            return
        }
        error = nil
        restoredURL = nil
        webView.load(URLRequest(url: url))
    }

    func restoreIfNeeded() {
        guard networkAllowed, filterReady, let url = restoredURL else { return }
        restoredURL = nil
        webView.load(URLRequest(url: url))
    }

    func receiveMedia(_ message: WKScriptMessage) {
        guard message.name == "browserMedia", let entries = message.body as? [[String: Any]] else { return }
        if let page = message.frameInfo.request.url { videos.removeAll { $0.pageURL == page } }
        for entry in entries.prefix(50) {
            guard let value = entry["url"] as? String else { continue }
            if value.hasPrefix("blob:") { unsupportedMedia = true }
            guard let url = BrowserMedia.mediaURL(value),
                  let page = message.frameInfo.request.url ?? lastURL else { continue }
            let video = BrowserVideo(url: url, title: entry["title"] as? String ?? title,
                                     pageURL: page, frame: message.frameInfo,
                                     area: (entry["area"] as? Double) ?? 0)
            if let index = videos.firstIndex(where: { $0.id == video.id }) { videos[index] = video }
            else { videos.append(video) }
        }
        if videos.count > 100 { videos = Array(videos.suffix(100)) }
    }

    func requestPlayback() {
        guard networkAllowed, filterReady, !findingVideo else { return }
        findingVideo = true
        error = nil
        let token = generation
        webView.evaluateJavaScript("window.__zsfScanVideos && window.__zsfScanVideos()") { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let self, self.generation == token, self.networkAllowed else { return }
                self.findingVideo = false
                if self.videos.isEmpty, let url = self.lastURL,
                   ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased()) {
                    self.videos = [BrowserVideo(url: url, title: self.title, pageURL: url, frame: nil, area: 0)]
                }
                guard let video = self.videos.max(by: { $0.area < $1.area }) else {
                    self.error = self.unsupportedMedia
                        ? "此页面使用 blob 媒体，无法直接交给系统解码，请使用网页播放器。"
                        : "当前页面尚未提供可解码的视频地址。"
                    return
                }
                self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self, self.generation == token, self.networkAllowed else { return }
                    self.webView.evaluateJavaScript("navigator.userAgent") { [weak self] agent, _ in
                        guard let self, self.generation == token, self.networkAllowed else { return }
                        self.webView.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.pause())",
                                                       in: video.frame, in: .page) { _ in }
                        self.playback = BrowserPlayback(video: video, cookies: cookies, userAgent: agent as? String)
                    }
                }
            }
        }
    }

    func stopPlayback() {
        generation = UUID()
        findingVideo = false
        playback?.stop()
        playback = nil
    }

    func pauseWebMedia() { webView.pauseAllMediaPlayback(completionHandler: nil) }

    func dispose() {
        generation = UUID()
        stopPlayback()
        pauseWebMedia()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "browserMedia")
        observations = []
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard networkAllowed, filterReady,
              let url = navigationAction.request.url, ["http", "https", "about"].contains(url.scheme ?? "") else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if networkAllowed, filterReady, navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") {
            onOpenTab?(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        error = nil
        generation = UUID()
        findingVideo = false
        videos = []
        unsupportedMedia = false
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error.localizedDescription
    }
}

private final class BrowserMediaBridge: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserState?
    init(owner: BrowserState) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receiveMedia(message)
    }
}
