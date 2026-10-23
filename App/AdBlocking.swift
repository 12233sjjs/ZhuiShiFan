import Foundation
import WebKit

enum AdBlocking {
    private static var compiled: WKContentRuleList?
    private static var pending: [(WKContentRuleList?, Error?) -> Void] = []

    static func rules(hosts: String) -> String {
        let domains = Set(hosts.components(separatedBy: .newlines).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "127.0.0.1" || fields[0] == "0.0.0.0" else { return nil }
            let domain = String(fields[1]).lowercased()
            guard domain != "localhost", domain.contains("."),
                  domain.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) })
            else { return nil }
            return domain
        }).sorted()
        let rules: [[String: Any]] = domains.map { domain in
            ["trigger": ["url-filter": "^https?://([^/]+\\.)?" +
                         NSRegularExpression.escapedPattern(for: domain) + "[:/]"],
             "action": ["type": "block"]]
        }
        return String(data: try! JSONSerialization.data(withJSONObject: rules), encoding: .utf8)!
    }

    static func install(on webView: WKWebView, completion: @escaping (Error?) -> Void) {
        guard let url = Bundle.main.url(forResource: "adaway-hosts", withExtension: "txt"),
              let hosts = try? String(contentsOf: url, encoding: .utf8) else {
            completion(NSError(domain: "AdBlocking", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "广告过滤规则缺失"]))
            return
        }
        if let compiled {
            webView.configuration.userContentController.add(compiled)
            completion(nil)
            return
        }
        pending.append { [weak webView] list, error in
            if let list { webView?.configuration.userContentController.add(list) }
            completion(error)
        }
        guard pending.count == 1 else { return }
        do {
            let encoded = try bundledRules(hosts: hosts)
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "ZhuiShiFan-Ads-v2", encodedContentRuleList: encoded) { list, error in
                DispatchQueue.main.async {
                    finish(list, error: error)
                }
            }
        } catch {
            finish(nil, error: error)
        }
    }

    private static func finish(_ list: WKContentRuleList?, error: Error?) {
        compiled = list
        let callbacks = pending
        pending = []
        callbacks.forEach { $0(list, error ?? (list == nil ? NSError(domain: "AdBlocking", code: 2) : nil)) }
    }

    static func bundledRules(hosts: String) throws -> String {
        var result = try JSONSerialization.jsonObject(with: Data(rules(hosts: hosts).utf8)) as! [[String: Any]]
        guard let url = Bundle.main.url(forResource: "ka-block", withExtension: "json") else {
            throw NSError(domain: "AdBlocking", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "扩展广告规则缺失"])
        }
        let extra = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        result += extra
        result.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": "ins.adsbygoogle, .adsbygoogle, [data-ad-slot], [data-ad-client], [id^='div-gpt-ad'], .advertisement, .ad-banner, .ad-overlay, iframe[src*='doubleclick.net']"
            ]
        ])
        return String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
    }
}
