import Foundation
import WebKit

enum AdBlocking {
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
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "AdAway-20261023", encodedContentRuleList: rules(hosts: hosts)) { list, error in
                DispatchQueue.main.async {
                    if let list { webView.configuration.userContentController.add(list) }
                    completion(error ?? (list == nil ? NSError(domain: "AdBlocking", code: 2) : nil))
                }
            }
    }
}
