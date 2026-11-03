# Swift/iOS 技能集评估与使用索引

> 更新：2026-11-03 · 来源：[dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills)（经 [allagent.wiki 词条](https://www.allagent.wiki/skills/swift-ios-skills/) 发现）
> 结论：**可作为开发参考使用，但不 vendor 全文、不装进 DSH 技能目录**，采用"按需抓取 + 索引"模式。

---

## 1. 这是什么

- 86 个自包含 Agent Skill，面向 **iOS 26 / Swift 6.3**，覆盖 SwiftUI、Core Swift、App 框架、数据框架、AI、工程化、硬件、平台、游戏。
- 每个技能 = `SKILL.md`（YAML frontmatter + 指令）+ 可选 `references/`。
- 主题 bundle：`swiftui-skills`、`swift-core-skills`、`ios-app-framework-skills`、`ios-data-framework-skills`、`ios-engineering-skills` 等。
- 质量抽查（`avkit`）：内容真实、指向 iOS 26 现行 API（`AVPlaybackSpeed`、`AVPictureInPictureController`、`isReadyForDisplay` 等），并列出 Common Mistakes 与 Review Checklist，可用。

## 2. 许可与合规（必须先读）

- 许可证：**PolyForm Perimeter 1.0.0**（非 OSI 开源）。
- 允许：用于开发自己的 App、闭源商用、fork 与回馈、分享给同事。
- 禁止：改头换面作为"Premium iOS Agent Skills"出售或提供**竞争性产品**（许可证里的 Noncompete 针对"与软件功能/value 构成替代"的产品）。
- 分发要求：分发任何副本必须附带许可证条款与 `Required Notice: Copyright (c) 2025 dpearson2699`。
- **本项目的用法**：不复制内容进仓库、不重新分发；只在文档里放链接，Agent 需要时用 `web_fetch` 读取。这样最干净，也避免仓库体积膨胀。

## 3. 为什么不做成 DSH Skill / 不 vendor

| 方案 | 可行性 | 结论 |
|---|---|---|
| `npx skills add` 装进本会话 | DSH 的技能目录在会话启动时固定，第三方 skills 不会进入本会话的 `skill` 工具目录 | ❌ 不可用 |
| `git clone` 到仓库 | 本机 shell 网络**无法直连 github.com:443**（web_fetch 可用，git/pwsh 不可） | ❌ 不可行 |
| vendor 全文进仓库 | 受许可约束（需附条款+Notice），且 86 个技能会污染上下文与仓库 | ⚠️ 不推荐 |
| **索引 + 按需 web_fetch** | 每个 SKILL.md 都是稳定 raw URL，Agent 可按需拉取，读完即用 | ✅ 采用 |

## 4. LemonPlayer 精选映射表（按里程碑）

> 读取方式：`web_fetch("https://raw.githubusercontent.com/dpearson2699/swift-ios-skills/main/skills/<name>/SKILL.md")`
> 只在对应任务开工时读，读完把"与我们的差异"提炼进实现，不要照抄。

| 里程碑 | 技能 | 用途 | 什么时候读 |
|---|---|---|---|
| M1 骨架/CI | `swift-architecture` | MV/MVVM/TCA 决策框架，验证我们的分层 | 搭 App 层时 |
| M1 | `swiftlint` | CI 接入 SwiftLint、规则取舍 | 写 build.yml 时 |
| M1 | `ios-simulator` | `xcrun simctl`、模拟器生命周期、`xcodebuild test` 目标 | 配 CI 测试时 |
| M1/M4 | `swift-testing` | `@Test`/`@Suite`/`#expect`、参数化测试、mock | 写单测时 |
| M2 | `ios-networking` | async URLSession、分页、重试、缓存、后台传输 | 写 `LemonNetwork` 时 |
| M2 | `swift-security` | Keychain、CryptoKit、凭据存储、OWASP | 写 `CredentialStore` 时 |
| M2/M3 | `swift-concurrency` | Swift 6 数据竞争安全、actor、结构化并发 | 写 TokenStore/内核桥接时 |
| M2/M5 | `swift-codable` | 两套响应信封的解码、嵌套 JSON、容错解码 | 写 DTO 时 |
| M3 | `avkit` | 音频会话、PiP、AirPlay、字幕轨、Now Playing | 内核封装 & 系统集成时 |
| M3 | `swiftui-gestures` | 双击/滑动/长按手势组合（播放器交互） | 播放器 UI 时 |
| M3 | `swiftui-uikit-interop` | `UIViewRepresentable` 承载内核渲染视图 | 接 MPV 渲染层时 |
| M3/M7 | `swiftui-performance` | 视图更新优化、布局抖动、Instruments | 播放器卡顿时 |
| M4/M5 | `swiftui-patterns` | `@Observable` 所有权、环境注入、异步加载 | 字幕面板/首页时 |
| M2/M5 | `swiftui-navigation` | `NavigationStack`、`NavigationSplitView`、深链 | 路由设计时 |
| M5 | `swiftdata` | `@Model`/`@Query`/`#Predicate`/迁移/`@ModelActor` | 写持久化时 |
| M6 | `background-processing` | `BGTaskScheduler`、后台 `URLSession` 传输 | 写下载器时 |
| M7 | `ios-accessibility` | VoiceOver、动态字体、焦点 | 无障碍改造时 |
| M7 | `ios-localization` | String Catalog、复数、RTL | 文案抽取时 |
| M7 | `debugging-instruments` | Instruments、os_signpost、MetricKit、崩溃符号化 | 性能/崩溃排查时 |
| M7 | `app-store-review` | 隐私清单、审核风险（本次只自签，作知识储备） | 若改走 App Store 时 |
| M1/UI | `swiftui-liquid-glass` | iOS 26 Liquid Glass，打造原生质感 | 视觉定稿时 |

## 5. 已知差异（哪些建议**不能**照搬）

| 技能建议 | 我们的情况 | 处理 |
|---|---|---|
| `avkit` 的 PiP 默认基于 `AVPlayerViewController` | 内核是 MPVKit（自定义渲染层），不是 AVPlayer | PiP 需走 `AVPictureInPictureController` + `AVSampleBufferDisplayLayer` 路径（见 `references/avkit-patterns.md`），M3 先做可行性验证 |
| `avkit` 的 AirPlay 依赖 AVPlayer 外部播放 | 第三方内核输出的帧无法走 `AVPlayer` 外部播放 | AirPlay 可能只能"音频走系统路由"或降级；结论写入 M7 |
| `avkit` 的字幕选择基于 `AVMediaSelectionGroup` | 外挂字幕走我们自己的解析 + libass | 只用它的系统级音频会话/Now Playing 建议 |
| `swiftdata` 默认 CloudKit 同步 | 我们不需要 iCloud 同步（且 GPL 内核不能上架） | 关闭 CloudKit，纯本地 |
| 所有技能默认 iOS 26 API | 与 ADR-001 一致 | 无冲突 |

## 6. 使用规则（给后续 Agent）

1. **按需读**：只读与当前任务相关的 1-2 个技能，不要批量拉取（上下文成本高）。
2. **读完提炼**：把结论写进对应 `Packages/*/` 的代码注释或 `docs/tech/` 笔记，而不是把整段 SKILL.md 贴进仓库。
3. **以 ADR 为准**：技能内容是通用最佳实践，与 `docs/DECISIONS.md` 冲突时以 ADR 为准（例如内核选型、CloudKit）。
4. **不复制**：许可证允许使用，但仓库不转载第三方内容；引用时给链接。
5. **质量抽查**：若发现某技能内容与 Apple 现行文档冲突，记录到对应任务的 `docs/PROGRESS.md` 日志里。

## 7. 后续动作

- [x] 评估完成，建立索引（本文）
- [ ] M1 开工时：读 `swift-architecture` + `swiftlint` + `ios-simulator`，把 CI 配置写出来
- [ ] M2 开工时：读 `ios-networking` + `swift-security` + `swift-concurrency`
- [ ] M3 开工时：读 `avkit` 的 `references/avkit-patterns.md`（PiP 自定义渲染路径），先出可行性结论
