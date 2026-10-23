import Foundation
import CFNetwork
import Combine

final class BrowserSession: ObservableObject {
    @Published private(set) var tabs: [BrowserState] = []
    @Published var selectedID = UUID()
    @Published private(set) var vpn = false
    private let defaults: UserDefaults
    private var timer: Timer?
    private let storageKey = "BrowserTabs.v1"

    private struct SavedTab: Codable {
        let id: UUID
        let url: URL?
    }
    private struct SavedSession: Codable {
        let tabs: [SavedTab]
        let selectedID: UUID
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(SavedSession.self, from: $0) }
        let initial = saved?.tabs.map { BrowserState(id: $0.id, restoredURL: $0.url) } ?? []
        tabs = initial.isEmpty ? [BrowserState()] : initial
        selectedID = saved?.selectedID ?? tabs[0].id
        if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs[0].id }
        tabs.forEach(bind)
        refreshVPN()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshVPN() }
    }

    deinit { timer?.invalidate() }

    var active: BrowserState { tabs.first(where: { $0.id == selectedID }) ?? tabs[0] }

    @discardableResult func addTab(url: URL? = nil) -> BrowserState {
        let tab = BrowserState(restoredURL: url)
        bind(tab)
        tab.networkAllowed = vpn
        tabs.append(tab)
        select(tab)
        return tab
    }

    func select(_ tab: BrowserState) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        if active.id != tab.id { active.pauseWebMedia(); active.stopPlayback() }
        selectedID = tab.id
        active.restoreIfNeeded()
        save()
    }

    func close(_ tab: BrowserState) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.dispose()
        tabs.remove(at: index)
        if tabs.isEmpty {
            let replacement = BrowserState()
            bind(replacement)
            replacement.networkAllowed = vpn
            tabs = [replacement]
        }
        if selectedID == tab.id { selectedID = tabs[min(index, tabs.count - 1)].id }
        active.restoreIfNeeded()
        save()
    }

    func save() {
        let saved = SavedSession(tabs: tabs.map { SavedTab(id: $0.id, url: $0.lastURL) }, selectedID: selectedID)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: storageKey) }
    }

    func hide() {
        tabs.forEach { $0.pauseWebMedia(); $0.stopPlayback() }
        save()
    }

    func refreshVPN() {
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
        let scoped = settings?["__SCOPED__"] as? [String: Any] ?? [:]
        let connected = scoped.keys.contains { name in
            ["utun", "ipsec", "ppp", "tap", "tun"].contains { name.hasPrefix($0) }
        }
        if connected != vpn { vpn = connected }
        for tab in tabs {
            if tab.networkAllowed != connected { tab.networkAllowed = connected }
        }
    }

    private func bind(_ tab: BrowserState) {
        tab.onChange = { [weak self] in self?.save() }
        tab.onOpenTab = { [weak self] url in self?.addTab(url: url) }
    }
}
