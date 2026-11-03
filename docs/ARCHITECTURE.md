# LemonPlayer 架构设计

> 版本：v0.1 · 更新：2026-11-03 · 状态：随 ADR 演进
> 本文是工程结构的唯一真相源；播放内核与构建方式的具体结论见 [`docs/DECISIONS.md`](DECISIONS.md)。

---

## 1. 设计目标与约束

| 约束 | 对架构的影响 |
|---|---|
| 开发机为 Windows，无 Xcode | 工程必须"小步可编译"；模块边界清晰才能单独验证；CI 是唯一编译真相源 |
| 光鸭 API 为逆向接口，可能变更 | API 层做**防腐层**：领域模型与 DTO 分离，接口变更只改 Adapter |
| 第三方播放内核为二进制依赖 | 用 `PlaybackEngine` 协议隔离，内核可插拔（AVPlayer / MPVKit / VLCKit） |
| 字幕要求高（ASS 特效 + 自绘样式） | 字幕解析与渲染分离：解析产出统一 `SubtitleCue` 模型；渲染分两条管线 |
| 无 Mac 真机调试 | 关键路径必须有可观测日志与自动化测试；真机验证靠 TestFlight/自签 |

---

## 2. 总体分层

```
┌─────────────────────────────────────────────────────────────────────┐
│  App 层（SwiftUI Features）                                          │
│   Login · Browse · Player · Library · Downloads · Settings           │
│   @Observable ViewModel + 导航（NavigationStack / SplitView）          │
└───────────────┬─────────────────────────────────────────────────────┘
                │ 只依赖 Domain 协议，不直接依赖网络/内核实现
┌───────────────▼─────────────────────────────────────────────────────┐
│  Domain 层（包内纯 Swift，无 UI/无网络/无平台 API）                    │
│   Entity · ValueObject · UseCase（PlayMedia / LoadSubtitle / Scrape） │
│   协议：FileRepository / AuthRepository / PlaybackURLProviding ...    │
└───────┬───────────────────────┬───────────────────────┬─────────────┘
        │                       │                       │
┌───────▼────────┐   ┌──────────▼──────────┐   ┌────────▼──────────┐
│  Data 层        │   │  Platform 层         │   │  Persistence 层   │
│  Network        │   │  Player（内核适配）   │   │  Keychain         │
│  GuangyaAPI     │   │  SubtitleRenderer    │   │  SwiftData        │
│  Media(TMDB)    │   │  Downloads(BGTask)   │   │  FileCache        │
└────────────────┘   └─────────────────────┘   └───────────────────┘
```

**依赖规则**：App → Domain ← Data/Platform/Persistence。Data 层不得反向依赖 App；Domain 不得 import UIKit/AVFoundation（保持可跨平台测试）。

---

## 3. 模块划分（SPM 本地包）

| 模块 | 职责 | 依赖 | 关键类型 | 写入范围 |
|---|---|---|---|---|
| `LemonCore` | 基础工具：日志、错误定义、时间/字符串扩展、Result 辅助 | 无 | `AppError`、`Logger`、`Clock` | `Packages/LemonCore/**` |
| `LemonNetwork` | URLSession 封装、拦截器链（鉴权/重试/日志脱敏）、限流 | LemonCore | `HTTPClient`、`RequestBuilder`、`RetryPolicy` | `Packages/LemonNetwork/**` |
| `LemonGuangya` | 光鸭 API 客户端：Auth、Files、Playback URL；DTO ↔ Domain 映射 | LemonCore, LemonNetwork | `GuangyaAuthClient`、`GuangyaFileService`、`PlayURLProvider` | `Packages/LemonGuangya/**` |
| `LemonSubtitle` | SRT/VTT/ASS 解析、编码检测、同名匹配、时间轴校准模型 | LemonCore | `SubtitleParser`、`SubtitleCue`、`SubtitleMatcher`、`EncodingDetector`、`SubtitleTimeline` | `Packages/LemonSubtitle/**` |
| `LemonPlayback` | `PlaybackEngine` 协议与内核适配、轨道模型、播放器状态机 | LemonCore, LemonSubtitle | `PlaybackEngine`、`PlayerState`、`TrackInfo`、`VLCKitEngine`（主）/`MPVEngine`（备） | `Packages/LemonPlayback/**` |
| `LemonMedia` | **Bangumi** 客户端（番剧库）、文件名解析、刮削编排 | LemonCore, LemonNetwork | `BangumiClient`、`MediaNameParser`、`LibraryScraper` | `Packages/LemonMedia/**` |
| `LemonPersistence` | Keychain、SwiftData 模型、策略（字幕记忆/历史/缓存索引） | LemonCore | `CredentialStore`、`PlaybackHistoryStore`、`SubtitlePreferenceStore` | `Packages/LemonPersistence/**` |
| `LemonDownloads` | 后台下载任务、断点续传、容量管理 | LemonCore, LemonNetwork | `DownloadTask`、`DownloadManager`、`StoragePolicy` | `Packages/LemonDownloads/**` |
| `LemonPlayer` | App target：入口、依赖装配、Feature UI | 以上全部 | `AppDependencies`、各 Feature View/ViewModel | `Sources/LemonPlayer/**` |

> 包名带前缀避免与系统模块冲突；每个包内含 `Tests/` target。

---

## 4. 领域模型（核心）

```swift
// 光鸭文件（领域模型，不含 API 字段细节）
struct CloudFile: Identifiable, Hashable, Sendable {
    let id: String            // file_id
    let name: String
    let path: String          // 规范化绝对路径
    let size: Int64
    let modifiedAt: Date
    let kind: FileKind        // .folder / .video / .subtitle / .audio / .image / .other
    let parentID: String?
}

// 播放地址（带过期时间，供续签）
struct PlaybackSource: Sendable {
    let url: URL
    let expiresAt: Date
    let headers: [String: String]   // Range / Referer / UA 等
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-30) }
}

// 字幕条目（统一模型，SRT/VTT/ASS 解析后共享）
struct SubtitleCue: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String              // 纯文本（含换行）
    let style: SubtitleStyle?     // VTT/ASS 内联样式（可选）
}

// 字幕轨道（外挂 or 内嵌）
enum SubtitleTrackSource: Sendable {
    case embedded(id: Int)        // 内核内嵌轨
    case external(SubtitleFile)   // 文件
}

// 播放数据包
struct MediaItem: Sendable {
    let file: CloudFile
    let source: PlaybackSource
    let subtitles: [SubtitleCandidate]
    let resumePosition: TimeInterval?
}
```

**状态机**（播放器）：

```
idle → resolvingURL → preparing → ready ↔ buffering → paused
                                 ↓  error → recovering → retry(≤3) → failed
```

---

## 5. 关键流程

### 5.1 登录（OAuth2 设备码）

```
LoginView ──► AuthUseCase.requestDeviceCode() ──► 展示二维码 + 倒计时
         └──► 每 2s 轮询 pollDeviceCode()
                ├─ pending  → 继续
                ├─ expired  → 刷新二维码
                ├─ success  → TokenStore.save(Keychain)
                └─ denied   → 提示可操作错误
冷启动：TokenStore.load() → 有效则直进 Browse；过期则静默 refresh（单飞 actor）
```

### 5.2 播放链路

```
Browse 点击文件
   └─► PlayMediaUseCase.prepare(fileID)
         ├─ PlayURLProvider.fetch(fileID)         → PlaybackSource（含过期）
         ├─ SubtitleResolver.autoMatch(file)      → [SubtitleCandidate]
         ├─ HistoryStore.resumePosition(fileID)   → Double?
         └─ PlayerView + PlaybackEngine.load(MediaItem)
播放中：
   ├─ 每次 seek / 定时（60s）检查 source.isExpired → 静默续签并热切换（不打断播放）
   ├─ 每 5s 落盘进度（节流写 SwiftData）
   └─ 错误 → 403/过期 → 重取 URL 重试；解码失败 → 切软解；网络断 → 指数退避重连
```

### 5.3 字幕链路

```
① 发现：同目录同名自动匹配（规范化 + 语言后缀 + 多候选排序）
② 选择：字幕面板（网盘文件 / 本地导入 / 内嵌轨）
③ 加载：Downloader → Data → EncodingDetector → SubtitleParser
④ 校准：SubtitleTimeline（offset 0.1s 步进，实时预览）
⑤ 渲染：
   - SRT/VTT → 自绘 overlay（CoreText/SwiftUI，样式可配）
   - ASS     → 内核 libass（原生特效/定位/字体），支持"强制覆盖样式"
⑥ 记忆：SubtitlePreferenceStore 按 fileID 保存选择/偏移/样式覆盖
```

### 5.4 下载链路

```
下载请求 → DownloadManager.createTask
  ├─ 后台 URLSession（background configuration）
  ├─ 分片/断点（Range + 已下载偏移记录）
  ├─ 状态机：pending → downloading ↔ paused → completed / failed(可重试)
  ├─ 完成后校验（大小比对 + 可选 hash）→ 写入离线索引
  └─ 离线播放：Player 优先命中本地索引，否则走远程直链
```

---

## 6. 并发模型（Swift 6 严格并发）

- **UI 层**：`@MainActor` 的 `@Observable` ViewModel；`Task` 绑定生命周期（`.task {}` / `@State` 持有）。
- **网络层**：`actor HTTPClient`；请求合并（单飞去重）用于 token 刷新与直链续签。
- **TokenStore**：`actor`，保证 refresh 只发一次；其他协程 await 同一个刷新任务。
- **下载**：`actor DownloadManager` + 独立后台会话；进度通过 `AsyncStream` 推给 UI。
- **内核回调**：C 回调（mpv/VLC）在后台线程 → 通过 `@Sendable` 闭包投递到 `AsyncStream`/`MainActor`，禁止在回调里直接摸 UI。
- **取消**：所有长任务（刮削/下载/字幕解析）接受 `Task.isCancelled`，防止播放页退出后继续跑。

---

## 7. 状态管理与依赖注入

- **DI**：`AppDependencies` 值类型在 App 启动时装配（网络、Store、内核工厂），通过 `.environment()` 注入；测试用 Mock 协议替换。
- **Feature 状态**：每个 Feature 一个 `@Observable` Store，暴露 `state: ViewState<Model>`（loading / empty / error / content）。
- **导航**：`NavigationStack(path:)` + 枚举 Route；iPad 用 `NavigationSplitView` 复用同一 Route。
- **持久化**：SwiftData（历史、字幕记忆、下载索引、媒体库元数据）+ 文件缓存目录（海报/字幕/下载文件）。

---

## 8. 错误处理与可观测性

| 层级 | 策略 |
|---|---|
| 网络 | `AppError.network(URLError)`；429/5xx 指数退避重试（≤3 次）；401 → 触发 refresh → 重放请求（单次） |
| API | 响应码 + 业务码映射为 `AppError.api(code:)`，UI 给"重试/重新登录/稍后再试"三选一 |
| 播放 | 内核错误事件 → `PlayerError` → 自动恢复策略表（见 5.2），失败后给"用外部播放器打开 / 下载后播放" |
| 字幕 | 解析失败不影响播放；提示"字幕加载失败（格式/编码）"并给手动指定编码入口 |
| 日志 | `Logger` 分级（debug/info/error），**脱敏规则**：URL 去掉签名参数、token 打码；滚动日志文件 ≤ 2MB |

---

## 9. 测试策略

| 层 | 方式 | 覆盖率要求 |
|---|---|---|
| 纯逻辑（解析/匹配/编码/状态机/文件名） | XCTest（`swift test` 可跑） | ≥ 80%（字幕解析 ≥ 90%） |
| 网络客户端 | URLProtocol 打桩 + 固定 JSON fixture | 关键路径全覆盖 |
| 内核桥接 | 模拟内核桩（`MockPlaybackEngine`），验证状态机与恢复策略 | 状态迁移全覆盖 |
| UI | XCUITest 冒烟（登录页/浏览页/播放器页可打开） | 冒烟即可 |
| 手工回归 | `docs/qa/REGRESSION.md`（J-01~J-04） | 发布前必跑 |

> 无 Mac 环境时：纯逻辑层可以在 CI（macos-26）与本地（若装 Swift for Windows）双跑；UI 测试只在 CI。

---

## 10. 目录结构（目标形态）

```
LemonPlayer/
├── project.yml                 # XcodeGen 配置（唯一真相源，生成 .xcodeproj）
├── Package.swift               # 本地 SPM 包聚合（可选）
├── Sources/LemonPlayer/        # App target
│   ├── App/                    # 入口、DI、路由
│   ├── Features/               # Login / Browse / Player / Library / Downloads / Settings
│   ├── Common/                 # 通用 View（状态视图、按钮、弹窗）
│   └── Resources/              # Assets、String Catalog、PrivacyInfo.xcprivacy
├── Packages/
│   ├── LemonCore/
│   ├── LemonNetwork/
│   ├── LemonGuangya/
│   ├── LemonSubtitle/
│   ├── LemonPlayer/
│   ├── LemonMedia/
│   ├── LemonPersistence/
│   └── LemonDownloads/
├── Tests/                      # App 层测试（XCUITest 等）
├── scripts/                    # 打包/版本脚本（CI 用）
├── .github/workflows/          # build.yml / release.yml
└── docs/                       # 本文档体系
```

---

## 11. 架构风险与预留

| 风险 | 预留设计 |
|---|---|
| 光鸭 API 变更 | `LemonGuangya` 内 DTO 与领域模型分离；接口新增/修改只动 Adapter 与 fixture |
| 内核更换（MPVKit ↔ VLCKit） | `PlaybackEngine` 协议 + 工厂；App 层零感知 |
| 未来接入 WebDAV / 其他网盘 | `FileRepository` / `PlayURLProvider` 协议可在 Domain 层扩展实现 |
| 未来上 macOS | Domain 层不依赖 UIKit，可复用；Platform 层按平台条件编译 |

---

## 12. 待定项（随 ADR 落定）

- [x] 播放内核选型：MobileVLCKit 3.7.5 主选，MPVKit 备选（ADR-003，见 `docs/tech/PLAYER_KERNEL.md`）
- [x] 构建与出包：GitHub Actions macos-26 + Xcode 26.6，未签名 IPA（ADR-006，见 `docs/tech/CI_BUILD.md`）
- [x] 工程生成工具：XcodeGen（ADR-004）
- [x] 本地持久化：SwiftData（ADR-005）
- [ ] 分支与提交规范、Release 触发方式（ADR-007，待 M1 落地细节）
