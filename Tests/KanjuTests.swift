import XCTest
import UIKit
@testable import ZhuiShiFan

final class KanjuTests: XCTestCase {
    @MainActor
    func testFullscreenPresentationDoesNotCountAsNavigationExit() {
        let detail = UIViewController()
        let navigation = UINavigationController(rootViewController: detail)
        let fullscreen = UIViewController()
        detail.present(fullscreen, animated: false)
        XCTAssertFalse(NavigationExitObserver.ExitController.hasExited(owner: detail, navigation: navigation))
        navigation.setViewControllers([UIViewController()], animated: false)
        XCTAssertTrue(NavigationExitObserver.ExitController.hasExited(owner: detail, navigation: navigation))
    }

    func testNativeLoginConfirmsSessionBeforeReportingSuccess() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel(); StubProtocol.handler = nil }
        var paths: [String] = []
        StubProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("/login") {
                XCTAssertEqual(request.httpMethod, "POST")
                return (200, Data("{}".utf8))
            }
            return (200, Data("{\"authenticated\":true,\"display_name\":\"测试账户\"}".utf8))
        }
        let profile = try await KanjuAPI(session: session).login(account: "fixture", password: "fixture")
        XCTAssertTrue(profile.authenticated)
        XCTAssertEqual(profile.displayName, "测试账户")
        XCTAssertEqual(paths, ["/v1/users/password/login", "/v1/users/me"])
    }

    func testNativeLoginRejectsUnconfirmedSession() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel(); StubProtocol.handler = nil }
        StubProtocol.handler = { request in
            (200, Data((request.url!.path.hasSuffix("/login") ? "{}" : "{\"authenticated\":false}").utf8))
        }
        do {
            _ = try await KanjuAPI(session: session).login(account: "fixture", password: "fixture")
            XCTFail("Must not report successful login without confirmed session")
        } catch { XCTAssertTrue(error.localizedDescription.contains("会话尚未确认")) }
    }

    private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try KanjuAPI.decoder().decode(T.self, from: Data(contentsOf: url))
    }

    func testLiveCapturedResponseShapes() throws {
        let feed: Feed = try fixture("feed")
        XCTAssertFalse(feed.sections.isEmpty)
        XCTAssertFalse(feed.sections[0].cards?.isEmpty ?? true)
        let search: BrowsePage = try fixture("search")
        XCTAssertEqual(search.pagination.page, 1)
        XCTAssertFalse(search.cards.isEmpty)
        let detail: Movie = try fixture("detail")
        XCTAssertFalse(detail.episodes?.isEmpty ?? true)
        XCTAssertNotNil(detail.episodes?.first?.token)
        let episodes: EpisodePage = try fixture("episodes")
        XCTAssertEqual(episodes.episodePagination.nextOffset, episodes.episodes.count)
        let playback: Playback = try fixture("resolve")
        XCTAssertNotNil(playback.lineOptions.first?.ticket)
        XCTAssertNil(playback.lineOptions.first?.mediaURL)
        let resolved: ResolvedPlayback = try fixture("line")
        XCTAssertEqual(resolved.line.mediaURL?.scheme, "https")
        XCTAssertNil(resolved.line.ticket)
    }

    func testSigningMatchesWebProtocol() {
        XCTAssertEqual(KanjuAPI.signature(method: "GET",
            path: "/v1/browse/catalog?q=%E8%A5%BF%E6%B8%B8%E8%AE%B0",
            timestamp: "1792670000000", nonce: "0123456789abcdef"),
            "23940265519e0df30ad9058201eb9127cf70fae88ea6dc41c85e68e49d949b10")
        XCTAssertEqual(KanjuAPI.component("a&b +/中文"), "a%26b%20%2B%2F%E4%B8%AD%E6%96%87")
    }

    func testOnlyConnectivityAndServerFailuresTriggerFailover() {
        XCTAssertTrue(KanjuAPI.shouldFailover(URLError(.cannotFindHost)))
        XCTAssertTrue(KanjuAPI.shouldFailover(SiteError(message: "down", status: 503)))
        for status in [400, 401, 402, 403, 404, 429] {
            XCTAssertFalse(KanjuAPI.shouldFailover(SiteError(message: "business error", status: status)))
        }
        XCTAssertFalse(KanjuAPI.shouldFailover(URLError(.cancelled)))
        XCTAssertFalse(KanjuAPI.shouldFailover(CancellationError()))
    }

    func testGetRetriesBackupAndKeepsUsingIt() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel(); StubProtocol.handler = nil }
        var hosts: [String] = []
        StubProtocol.handler = { request in
            hosts.append(request.url!.host!)
            if request.url!.host == "kanju17.com" { throw URLError(.cannotFindHost) }
            return (200, Data("{\"sections\":[]}".utf8))
        }
        let api = KanjuAPI(session: session)
        _ = try await api.home()
        _ = try await api.home()
        XCTAssertEqual(hosts, ["kanju17.com", "kanju21.com", "kanju21.com"])
        let origin = await api.origin
        XCTAssertEqual(origin, KanjuAPI.backupOrigin)
    }

    func testAmbiguousPlaybackPostIsNotReplayed() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel(); StubProtocol.handler = nil }
        var calls = 0
        StubProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "POST")
            throw URLError(.timedOut)
        }
        let api = KanjuAPI(session: session)
        let playback: Playback = try fixture("resolve")
        do {
            _ = try await api.resolve(playback.lineOptions[0])
            XCTFail("Expected timeout error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("备用站")) }
        XCTAssertEqual(calls, 1)
        let origin = await api.origin
        XCTAssertEqual(origin, KanjuAPI.backupOrigin)
    }

    func testQuotaFailureDoesNotSwitchHost() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel(); StubProtocol.handler = nil }
        var calls = 0
        StubProtocol.handler = { _ in
            calls += 1
            return (402, Data("{\"error\":{\"message\":\"quota\"}}".utf8))
        }
        let api = KanjuAPI(session: session)
        do { _ = try await api.home(); XCTFail("Expected quota error") }
        catch { XCTAssertEqual((error as? SiteError)?.status, 402) }
        XCTAssertEqual(calls, 1)
        let origin = await api.origin
        XCTAssertEqual(origin, KanjuAPI.primaryOrigin)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let result = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: result.0,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
