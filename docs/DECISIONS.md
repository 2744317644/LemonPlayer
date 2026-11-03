# 架构决策记录（ADR）

> 规则：每个"难以回退"的决定都写一条 ADR。状态：`提案` → `已接受` / `已废弃`（不删除，保留历史）。
> 编号不复用；新决策追加在末尾。

---

## ADR-001 · 目标平台锁定 iOS 26.0+（iPhone / iPad）

- **状态**：已接受
- **日期**：2026-11-03
- **背景**：用户环境为 Windows + GitHub Actions；构建链使用 Xcode 26。需要决定最低系统版本与设备形态。
- **决策**：仅支持 iOS/iPadOS **26.0 及以上**，iPhone + iPad 双端；不向下兼容旧系统；暂不覆盖 macOS/tvOS/visionOS。
- **理由**：
  - Xcode 26 默认 SDK 为 iOS 26，最低版本过低会引入大量条件编译与 UI 兼容分支；
  - 目标用户是自建影视库玩家，设备更新率高；
  - 26 的 SwiftUI/观察框架能力（`@Observable`、新导航、`NavigationSplitView`）可减少自研状态管理。
- **后果**：
  - ✅ 代码干净、少兼容分支、CI 简单；
  - ❌ 排除旧设备用户；若未来要兼容，需要重新评估（Domain 层已与 UI 解耦，成本可控）。
- **备选**：iOS 17+（兼容面广，但 UI 兼容分支多）；iOS 18+（折中）。

---

## ADR-002 · 光鸭云盘接入方式：官方（逆向）API 直连，不做 WebDAV 客户端

- **状态**：已接受
- **背景**：光鸭云盘无公开开发者 API；社区已有 OAuth2 设备码扫码登录、目录、签名直链的成熟实现（ShukeBta/Guangyadisk、AList guangyapan 驱动）。另一条路是走 WebDAV（需用户自建 MoviePilot/alist 网关）。
- **决策**：v1 直接对接光鸭 REST API，在 `LemonGuangya` 模块内实现 Auth / Files / PlaybackURL 三个服务；不实现 WebDAV 客户端。
- **理由**：
  - 用户明确要求"扫码登录直接挂载"，减少外部依赖；
  - 直连可拿到 CDN 签名直链，播放性能最好；
  - WebDAV 需要额外部署服务，与"一个 App 看片"的产品目标冲突。
- **后果**：
  - ✅ 用户体验闭环、无外部服务；
  - ❌ API 为非官方逆向接口，可能变更/限流/风控 → 必须做防腐层与可观测日志；预留 `FileRepository` 协议以便未来接 WebDAV。
- **风险缓解**：DTO 与领域模型分离；接口路径/参数集中在一个 `GuangyaEndpoint` 枚举；失败时给出明确诊断信息；跟踪社区实现的接口变更。

---

## ADR-003 · 播放内核：FFmpeg 系内核（提案：MPVKit，待调研结论确认）

- **状态**：提案（调研中）
- **背景**：光鸭片源以 MKV 为主（H.264/HEVC，常见 DTS/AC3 音轨、PGS/ASS 内嵌字幕）。AVPlayer 不支持 MKV 容器与多数非 MP4 音频，无法满足"全格式"要求。
- **决策（提案）**：引入 **MPVKit**（mpv + FFmpeg，SPM 分发，自带 libass），通过 `PlaybackEngine` 协议封装；备选 **MobileVLCKit**（CocoaPods，libass 同样内置）。最终以 [`docs/tech/PLAYER_KERNEL.md`](tech/PLAYER_KERNEL.md) 的对比结论为准。
- **理由**：MKV/HEVC/AV1/DTS 全解码；libass 免费提供 ASS 完整特效；SPM 集成符合无 CocoaPods 的 CI 偏好。
- **后果**：
  - ✅ 格式覆盖与字幕能力达标；
  - ❌ 二进制体积大（FFmpeg 全量）；画中画/AirPlay 需自行桥接（`AVSampleBufferDisplayLayer`）；GPL/LGPL 合规需声明。
- **备选**：MobileVLCKit（成熟、但 CocoaPods 依赖与 GPL 风险）；AVPlayer + 自研 MKV demux（工作量过大，不现实）。

---

## ADR-004 · 工程文件由 XcodeGen 生成（project.yml 为唯一真相源）

- **状态**：提案（待 M1 验证）
- **背景**：无本地 Xcode，无法用 GUI 维护 `.xcodeproj`（二进制 pbxproj 冲突、手写易错）。
- **决策**：仓库只提交 `project.yml`，CI 里 `brew install xcodegen` 后生成工程再构建。
- **后果**：
  - ✅ 工程配置可读、可 diff、CI 可复现；避免 pbxproj 合并冲突；
  - ❌ 需要 XcodeGen 依赖；少数设置（如 capability）需在 yml 中声明。
- **备选**：Tuist（更重，Swift 配置）；直接提交 pbxproj（合并冲突风险，放弃）。

---

## ADR-005 · 本地持久化使用 SwiftData

- **状态**：提案
- **背景**：需存播放历史、字幕记忆、媒体库元数据、下载索引。
- **决策**：v1 用 SwiftData；Keychain 存凭据；大文件与海报走文件缓存目录（不进数据库）。
- **理由**：iOS 26 环境下成熟稳定；与 SwiftUI 集成好；避免第三方依赖。
- **后果**：Schema 迁移能力有限，未来大改需写迁移；数据量小，风险可控。

---

## ADR-006 · 构建与分发：GitHub Actions（macos-26 + Xcode 26）产出未签名 IPA

- **状态**：已接受
- **背景**：开发机为 Windows；用户要求"直接在 GitHub 构建工作流出包"。
- **决策**：
  - 每次 push 到 `main` / PR：模拟器构建 + 单测 + 未签名 IPA（`CODE_SIGNING_ALLOWED=NO`），artifact 上传；
  - 打 tag：Release 工作流附 IPA 与校验和；
  - 签名由用户侧完成（Sideloadly/AltStore/自签），或提供可选 secrets 走 `-exportArchive` 自动签名。
- **后果**：
  - ✅ 零机器依赖，任何提交都可验证；
  - ❌ macOS runner 计费/排队；无签名 IPA 安装有 7 天限制（免费账号）；GPL 内核不能上 App Store（需评估 App Store 路线）。
- **细节**：见 [`docs/tech/CI_BUILD.md`](tech/CI_BUILD.md)。

---

## ADR-007 · 仓库与提交规范

- **状态**：已接受
- **决策**：
  - 主干 `main` 受保护（CI 必须绿）；
  - 功能分支 `feat/<模块>-<简述>`；
  - Conventional Commits（`feat:`/`fix:`/`docs:`/`chore:`/`refactor:`/`test:`）；
  - 每个里程碑打 tag（`m1`、`m2`…），v1.0 打 `v1.0.0`。
- **理由**：便于按里程碑回溯与自动生成 changelog。

---

## ADR-008 · 字幕渲染双管线：ASS 走内核 libass，SRT/VTT 走自绘 overlay

- **状态**：已接受
- **背景**：ASS 特效（字体、定位、卡拉OK）依赖 libass 才能正确还原；而用户还要能改字号/颜色/位置，SRT/VTT 需要绝对可控。
- **决策**：
  - ASS/SSA：交给内核（mpv/VLC 自带 libass）渲染，额外提供"强制覆盖样式"开关；
  - SRT/VTT：自绘 overlay（CoreText / SwiftUI），样式面板完全生效；
  - 双语字幕：ASS 走内核第二字幕轨，SRT/VTT 走 overlay 双行布局。
- **后果**：两条渲染路径需统一时间轴与延迟模型（`SubtitleTimeline` 共用），保证 seek/暂停时一致。

---

## ADR-009 · v1 不做在线字幕搜索

- **状态**：已接受
- **理由**：第三方字幕源不稳定、合规风险高；用户未选。字幕来源限定：网盘同目录自动匹配、网盘任意文件、本地文件导入。

---

## ADR-010 · SPM 模块边界（8 个包）

- **状态**：已接受
- **决策**：`LemonCore`、`LemonNetwork`、`LemonGuangya`、`LemonSubtitle`、`LemonPlayer`、`LemonMedia`、`LemonPersistence`、`LemonDownloads`。依赖单向：App → Domain ← Data/Platform。
- **理由**：并行开发时写入范围互不重叠；纯逻辑包可在 CI 独立测试；内核可替换。
- **约束**：Domain 层禁止 import UIKit/AVFoundation。

---

## ADR-011 · 无本地 Xcode 的验证策略

- **状态**：已接受
- **决策**：
  1. CI 是编译的唯一定论；任何"本地能过"的说法不作为依据；
  2. 纯逻辑包优先做到 `swift test` 可独立运行（不依赖 iOS SDK），便于未来在 Windows/Linux 跑；
  3. 每次提交小步化，失败日志回写 `docs/PROGRESS.md`；
  4. 真机行为（后台播放/画中画/安装）通过 TestFlight 或自签包人工验证，记录到 `docs/qa/`。

---

## 待定 ADR 队列

| 候选 | 说明 |
|---|---|
| ADR-012 | 海报与元数据缓存策略（磁盘 LRU vs 数据库索引） |
| ADR-013 | 下载文件命名与目录布局 |
| ADR-014 | 日志与诊断上报（是否接第三方崩溃收集） |
