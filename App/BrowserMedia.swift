import AVKit
import WebKit
import SwiftUI

struct BrowserVideo: Identifiable {
    let url: URL
    let title: String
    let pageURL: URL
    let frame: WKFrameInfo?
    let area: Double
    var id: String { url.absoluteString }
}

enum BrowserMedia {
    static func mediaURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func cookies(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let base = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let hostMatches = host == base || (domain.hasPrefix(".") && host.hasSuffix("." + base))
            let path = url.path.isEmpty ? "/" : url.path
            let cookiePath = cookie.path
            let pathMatches = path == cookiePath ||
                (path.hasPrefix(cookiePath) && (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
            return hostMatches && pathMatches && (!cookie.isSecure || url.scheme == "https") &&
                (cookie.expiresDate.map { $0 > now } ?? true)
        }
    }

    // Observe HTML5 media only; encrypted/blob sources remain in the webpage.
    static let script = """
    (() => {
      if (window.__zsfScanVideos) { window.__zsfScanVideos(); return; }
      window.__zsfScanVideos = () => {
        const videos = Array.from(document.querySelectorAll('video')).map(v => ({
          url: v.currentSrc || v.src || v.querySelector('source')?.src || '',
          title: v.title || document.title || '网页视频',
          page: location.href,
          area: v.clientWidth * v.clientHeight
        }));
        window.webkit.messageHandlers.browserMedia.postMessage(videos);
      };
      let pending;
      new MutationObserver(() => {
        clearTimeout(pending);
        pending = setTimeout(window.__zsfScanVideos, 250);
      }).observe(document.documentElement, {childList:true, subtree:true, attributes:true, attributeFilter:['src']});
      ['loadedmetadata', 'canplay', 'durationchange'].forEach(name =>
        document.addEventListener(name, window.__zsfScanVideos, true));
      window.__zsfScanVideos();
    })();
    """
}

final class BrowserPlayback: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let player: AVPlayer
    @Published var error: String?
    private var observation: NSKeyValueObservation?

    init(video: BrowserVideo, cookies: [HTTPCookie], userAgent: String?) {
        title = video.title
        var headers: [String: String] = [:]
        headers["Referer"] = video.pageURL.absoluteString
        if let userAgent { headers["User-Agent"] = userAgent }
        let asset = AVURLAsset(url: video.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            AVURLAssetHTTPCookiesKey: BrowserMedia.cookies(cookies, for: video.url)
        ])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "此视频无法使用系统解码"
            DispatchQueue.main.async { self?.error = "解码或加载失败：\(message)" }
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        observation = nil
    }
}

struct BrowserPlaybackView: View {
    @ObservedObject var playback: BrowserPlayback
    let close: () -> Void
    var body: some View {
        PlaybackWindow(player: playback.player, title: playback.title, close: close)
            .overlay {
                if let error = playback.error {
                    Text(error).font(.callout).padding().background(.black.opacity(0.85))
                        .padding(60).allowsHitTesting(false)
                }
            }
    }
}
