import SwiftUI

@MainActor
final class AccountModel: ObservableObject {
    @Published var profile: AccountProfile?
    @Published var busy = false
    @Published var message: String?
    @Published var host = "kanju17.com"

    func refresh() async {
        busy = true
        message = nil
        do { profile = try await KanjuAPI.shared.account() }
        catch {
            if (error as? SiteError)?.status == 401 { profile = nil }
            else if !Task.isCancelled { message = error.localizedDescription }
        }
        host = await KanjuAPI.shared.origin.host ?? ""
        busy = false
    }

    func login(account: String, password: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        do { profile = try await KanjuAPI.shared.login(account: account, password: password) }
        catch { if !Task.isCancelled { message = error.localizedDescription } }
        host = await KanjuAPI.shared.origin.host ?? ""
        busy = false
    }
}

struct SiteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AccountModel()
    @State private var account = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let profile = model.profile, profile.authenticated {
                        Label("已登录：\(profile.displayName ?? "网站账户")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.mint)
                        Text("返回影片页面，点击重试播放。").font(.subheadline)
                    } else {
                        TextField("网站账号", text: $account)
                            .textContentType(.username).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().accessibilityIdentifier("accountField")
                        SecureField("密码", text: $password).textContentType(.password)
                            .accessibilityIdentifier("passwordField")
                        Button("登录") {
                            Task {
                                await model.login(account: account.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                                password = ""
                            }
                        }
                        .disabled(model.busy || account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    }
                } header: { Text("网站账户") } footer: {
                    Text("使用看剧网站的账号密码。登录通过 HTTPS 直接提交到当前站点；应用不会保存密码。")
                }
                if model.busy { ProgressView("正在连接网站…") }
                if let message = model.message {
                    Section {
                        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("重新检查连接") { Task { await model.refresh() } }.disabled(model.busy)
                    }
                }
                Section("连接") {
                    LabeledContent("当前站点", value: model.host)
                    if model.host != "kanju21.com" {
                        Button("切换备用站 kanju21.com") {
                            Task { await KanjuAPI.shared.useBackup(); await model.refresh() }
                        }.disabled(model.busy)
                    }
                    Text("无需加载整站网页或开启 VPN。若当前网络无法连接两个站点，请更换网络后重试。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("网站账户").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { password = ""; dismiss() }.disabled(model.busy)
                }
            }
        }
        .task { await model.refresh() }
    }
}
