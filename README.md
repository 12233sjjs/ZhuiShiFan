# 追视番通用

iPhone 原生视频客户端，最低 iOS 16.0，目标设备为 iOS 16.6.1，通过 TrollStore 安装。

包含网站推荐列表、片名搜索、影片详情、选集、线路切换及系统原生播放控件（暂停、拖动、全屏）。界面使用 SwiftUI，视频使用 AVPlayer，不是网站套壳。

默认数据源为 `https://kanju17.com/`，连接或服务器故障时自动切换 `https://kanju21.com/`。备用站在本次应用运行期间保持生效，重新启动后优先尝试主站。登录、额度不足、无资源、限流等业务错误不会触发切站。播放解析 POST 在超时后不会自动重放，以避免重复消耗网站额度；界面提示切站后手动重试。

## 编译与安装

1. 在 GitHub 的 Actions 中打开 **Build TrollStore IPA**，点击 **Run workflow**。推送到 main 也会自动编译。
2. 构建成功后下载 **ZhuiShiFan-TrollStore** artifact，解压得到 `ZhuiShiFan-TrollStore.ipa`。
3. 在 iPhone 的“文件”中分享该 IPA 到 TrollStore 并安装。

无需 Apple 开发者证书。构建流程先运行接口解析、请求签名、故障切站和不重复提交播放请求的测试，再编译 arm64 应用、进行 ad-hoc 签名和 IPA 打包。TrollStore 安装时重新签名。应用不申请私有权限。

本机 macOS/Xcode 开发：安装 XcodeGen **2.46.0**，执行 `xcodegen generate`，打开生成的工程。CI 校验固定版本的下载 SHA-256，第三方 Actions 固定到 commit。

## 接口和限制

2026-10-22 实测两个域名的首页数据、主站搜索/详情/选集/播放解析及视频 Range 请求。网站使用公开网页客户端的 HMAC 请求签名，并通过一次性播放票据解析媒体地址。签名协议集中在 `App/KanjuAPI.swift`；其中的网页签名常量不是用户账户凭据。

网站的登录、访问权限和额度限制仍然有效，影片是否可播取决于服务端和片源。播放报错时可进入网站账户页面完成登录，再返回重试。网站改版、签名常量更新、视频编码不被 AVPlayer 支持时可能需要更新适配；应用不提供 DRM 解密。

测试使用经过脱敏的响应结构快照，不会请求真实播放接口或消耗额度。Windows 无法运行 iOS 应用，编译与模拟器验证由 GitHub Actions 执行；iOS 16.6.1 真机播放和 TrollStore 安装需实际设备验证。

## 开源方案取舍

制作前查找了 Yattee、BMPlayer、KSPlayer 等开源视频客户端/播放器。它们没有该网站的数据适配，整套移植会带来不必要的功能和依赖。本项目采用系统 SwiftUI/AVKit，并复用成熟的 XcodeGen 构建工具。

参考项目：`github.com/yonaskolb/XcodeGen`、`github.com/opa334/TrollStore`、`github.com/yattee/yattee`、`github.com/BrikerMan/BMPlayer`、`github.com/kingslay/KSPlayer`。

本项目与上述网站及开源项目无隶属关系。不存储或分发视频文件；请仅使用你有权访问的内容。
