import XCTest
import WebKit
@testable import ZhuiShiFan

final class BrowserTests: XCTestCase {
    @MainActor
    func testTabsKeepWebViewsWhenHiddenAndSwitching() throws {
        let name = "BrowserTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = BrowserSession(defaults: defaults)
        let first = session.active
        first.address = "https://example.org/draft"
        let second = session.addTab()
        let firstWebView = first.webView
        session.hide()
        session.select(first)
        XCTAssertTrue(session.active.webView === firstWebView)
        XCTAssertEqual(first.address, "https://example.org/draft")
        XCTAssertEqual(session.tabs.map(\.id), [first.id, second.id])
        session.close(second)
        XCTAssertTrue(session.active === first)
    }

    @MainActor
    func testTabURLsAndSelectionRestoreWithoutLoadingOffline() throws {
        let name = "BrowserTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = BrowserSession(defaults: defaults)
        session.active.lastURL = URL(string: "https://example.org/one")
        let second = session.addTab()
        second.lastURL = URL(string: "https://example.org/two")
        session.save()
        let restored = BrowserSession(defaults: defaults)
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.selectedID, second.id)
        XCTAssertEqual(restored.active.address, "https://example.org/two")
        XCTAssertNil(restored.active.webView.url)
        restored.close(restored.active)
        XCTAssertEqual(restored.tabs.count, 1)
        restored.close(restored.active)
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertNil(restored.active.lastURL)
    }

    func testMediaURLsRejectNonNetworkSchemes() {
        XCTAssertNotNil(BrowserMedia.mediaURL("https://media.example.org/movie.m3u8?ticket=fixture"))
        for value in ["blob:https://example.org/123", "file:///tmp/video.mp4", "javascript:alert(1)", "about:blank", "https://"] {
            XCTAssertNil(BrowserMedia.mediaURL(value), value)
        }
    }

    func testPlaybackCookiesRespectDomainPathAndSecureFlag() throws {
        func cookie(_ name: String, domain: String, path: String = "/", secure: Bool = false) throws -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: path]
            if secure { properties[.secure] = "TRUE" }
            return try XCTUnwrap(HTTPCookie(properties: properties))
        }
        let cookies = try [
            cookie("domain", domain: ".example.org"),
            cookie("exact", domain: "video.example.org", path: "/media"),
            cookie("wrongHost", domain: "unrelated.org"),
            cookie("wrongPath", domain: "video.example.org", path: "/medi"),
            cookie("secure", domain: ".example.org", secure: true)
        ]
        let https = try XCTUnwrap(URL(string: "https://video.example.org/media/movie.mp4"))
        XCTAssertEqual(Set(BrowserMedia.cookies(cookies, for: https).map(\.name)), ["domain", "exact", "secure"])
        let http = try XCTUnwrap(URL(string: "http://video.example.org/media/movie.mp4"))
        XCTAssertEqual(Set(BrowserMedia.cookies(cookies, for: http).map(\.name)), ["domain", "exact"])
        let lookalike = try XCTUnwrap(URL(string: "https://notexample.org/media/movie.mp4"))
        XCTAssertTrue(BrowserMedia.cookies(cookies, for: lookalike).isEmpty)
    }

    @MainActor
    func testHTMLVideoDetectedBeforeWebpagePlayback() {
        let ready = expectation(description: "Ad rules ready")
        AdBlocking.install(on: WKWebView()) { error in
            XCTAssertNil(error)
            ready.fulfill()
        }
        wait(for: [ready], timeout: 60)
        let tab = BrowserState()
        tab.networkAllowed = true
        tab.webView.loadHTMLString("""
        <html><head><title>Fixture video</title></head><body>
        <video preload="none" width="640" height="360">
          <source src="https://media.example.org/movie.mp4" type="video/mp4">
        </video></body></html>
        """, baseURL: URL(string: "https://example.org"))
        let detected = expectation(for: NSPredicate { _, _ in !tab.videos.isEmpty }, evaluatedWith: nil)
        wait(for: [detected], timeout: 20)
        XCTAssertEqual(tab.videos.first?.url.absoluteString, "https://media.example.org/movie.mp4")
        let paused = expectation(description: "Webpage video was never played")
        tab.webView.evaluateJavaScript("document.querySelector('video').paused") { value, error in
            XCTAssertNil(error)
            XCTAssertEqual(value as? Bool, true)
            paused.fulfill()
        }
        wait(for: [paused], timeout: 10)
        tab.dispose()
    }
}
