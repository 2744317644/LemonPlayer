# 播放内核选型（iOS）

> 版本：v0.1 · 更新：2026-11-03 · 对应任务 T-006 / ADR-003
> 目标：为 LemonPlayer 选择能播 MKV/HEVC、完整渲染 ASS 特效、且能在 GitHub Actions（Xcode 26）中稳定构建的内核。

---

## 0. 结论（TL;DR）

| 决策 | 内容 |
|---|---|
| **主选** | **MobileVLCKit 3.7.5**（CocoaPods，LGPLv2.1+，自带 libass） |
| **备选** | **MPVKit**（SPM，LGPLv3，自带 libass；集成更简单但作者自述"仅适合学习、不频繁维护"，且 Metal 支持是非官方补丁） |
| **观察** | **AetherEngine**（LGPL-3.0 + App Store 例外，FFmpeg demux + VideoToolbox + AVPlayer 原生渲染，能效/画质/PiP 最好，但字幕只输出 cue、不渲染 ASS 特效；且官方要求 **Xcode 27 / Swift 6.4**） |
| **不选** | AVPlayer（不支持 MKV 容器与 DTS/AC3 音轨，无法满足核心需求） |

**推荐理由**：用户核心需求是"MKV 全格式 + ASS 特效字幕"，这要求内核内置 **libass**。VLCKit 是唯一同时满足"libass 完整渲染 + 长期维护（3.7.5 于 2026-10-31 发布）+ 生产级验证"的方案；代价是只能走 CocoaPods、无原生 PiP/AirPlay。

**风险与回退**：若 CocoaPods 在 CI 上不可接受，切 MPVKit（纯 SPM）；若未来接受"ASS 只渲染文本样式"并且 CI 有 Xcode 27，可重新评估 AetherEngine（能效与 PiP 是它的强项）。

---

## 1. 候选方案对比

### 1.1 能力对比

| 维度 | MobileVLCKit 3.7.5 | MPVKit 1.1.0 (mpv 0.41 / FFmpeg 9.0.2) | AetherEngine 7.x |
|---|---|---|---|
| 集成方式 | CocoaPods（`pod 'MobileVLCKit'`） | **SPM**（GitHub binaryTarget） | SPM |
| 最低 iOS | 支持 iOS 12+（当前版本仍兼容低版本） | **iOS 15**（Package.swift 声明） | **iOS 18** |
| 容器 | MKV/MP4/TS/AVI/FLV/RM/WMV/OGG…（libavformat） | 同左 | MKV/MP4/TS/AVI/WMV/OGG/FLV/RM/3GP + DVD/Blu-ray ISO |
| 视频解码 | VideoToolbox 硬解 + 软解回退 | VideoToolbox 硬解 + FFmpeg 软解 | **VideoToolbox 硬解为主**，AV1 硬解可选，dav1d 软解兜底 |
| HDR | 软件 tone-map（不切系统 HDR） | libplacebo/MoltenVK tone-map（不切系统 HDR） | **原生 HDR10/DV/HDR10+/HLG 显示切换** |
| 杜比视界 | 仅 tone-map | 仅 tone-map（libdovi 解析元数据） | **P5/P8 原生、P7 可选双层** |
| 音频 | AAC/AC3/EAC3/DTS/TrueHD/FLAC…（软解到 PCM） | 同左 | 同左 + EAC3+JOC（Atmos）透传 |
| **ASS/SSA 特效** | ✅ **libass 完整渲染**（字体/定位/卡拉OK） | ✅ **libass 完整渲染** | ❌ 只输出 `SubtitleCue`/`CGImage`，ASS 样式需自绘 |
| 外挂字幕注入 | `addPlaybackSlave(url:type:)` 一行接入 | `sub-add` 命令 | `externalSubtitles` 声明为轨道 |
| 内嵌字幕轨 | ✅（含 PGS 位图） | ✅ | ✅（含 PGS OCR 转 vtt 供 PiP 使用） |
| 画中画 PiP | ❌（无 AVPlayer 管线） | ❌ | ✅（原生 + 软件层 `AVSampleBufferDisplayLayer`） |
| AirPlay | ❌（视频不走 AVPlayer） | ❌ | ✅（原生路径） |
| 后台音频 | ✅（需自行配置 AVAudioSession） | ✅ | ✅ |
| 能效（4K HDR HEVC，第三方基准） | 266 mW / 15% CPU | **887 mW / 21% CPU** | **41 mW / 4.4% CPU** |
| 二进制体积 | ~80–120MB（xcframework） | ~150–300MB（下载解压；IPA 增量大） | 中（动态 FFmpeg 框架 + 引擎） |
| 许可 | LGPLv2.1+（VLCKit） | LGPLv3（GPL 变体额外含 samba） | LGPL-3.0 **+ App Store 例外** |
| 维护状态 | ✅ 活跃（3.7.5，2026-10-31） | ⚠️ 作者注明"仅适合学习、不频繁维护"；Metal 为非官方补丁 | ✅ 活跃，多个 App Store 应用在用 |
| CI 构建 | 需要 `pod install`（macos-26 预装 CocoaPods 1.17.0） | 纯 SPM，最省心 | 需要 **Xcode 27**（26.3 仅 best-effort 兼容） |

> 能效数据取自 AetherEngine 的公开基准（MacBookAir10,1 / macOS 27，4K HDR HEVC 38Mbit/s），仅作相对参考，不代表 iPhone 实测。

### 1.2 关键事实来源

- MobileVLCKit 版本与发布时间：[CocoaPods Trunk](https://trunk.cocoapods.org/api/v1/pods/MobileVLCKit)（3.7.5 = 2026-10-31；4.0 仅有 2023 年的 alpha）
- VLCKit 文档与集成：[code.videolan.org VLCKit](https://code.videolan.org/videolan/VLCKit)
- MPVKit 版本/平台/许可/组件：[MPVKit README](https://github.com/mpvkit/MPVKit) + [Package.swift](https://raw.githubusercontent.com/mpvkit/MPVKit/main/Package.swift)（mpv 0.41.0、FFmpeg 9.0.2、Libass 0.17.5、libdav1d、libplacebo、MoltenVK、libdovi）
- AetherEngine 能力/许可/工具链：[AetherEngine README](https://github.com/superuser404notfound/AetherEngine)（iOS 18+、Swift 6.4、Xcode 27.0；LGPL-3.0 + 商店例外）
- GitHub runner 环境：[macos-26-arm64 Readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)（Xcode 26.6 默认，iOS 26.5 SDK）

---

## 2. 为什么不是 AVPlayer

| 限制 | 影响 |
|---|---|
| 不支持 MKV 容器（AVFoundation 无 demuxer） | 光鸭影视资源绝大多数是 MKV，直接不可用 |
| 不支持 DTS / TrueHD / DTS-HD 等音轨 | 大量蓝光转制资源无声 |
| 不能渲染 ASS 特效 | 字幕需求不达标 |
| 无法软解 AV1/特殊 profile | 兼容性差 |

> AVPlayer 唯一的优势是 PiP/AirPlay/HDR 原生，但前提是"能播"。作为兜底仅用于 MP4/HLS 播放。

---

## 3. 主选：MobileVLCKit 3.7.5

### 3.1 集成方式（CocoaPods）

```ruby
# Podfile
platform :ios, '26.0'
use_frameworks! :linkage => :static   # VLCKit 建议静态链接，避免动态库签名问题

target 'LemonPlayer' do
  pod 'MobileVLCKit', '~> 3.7'
end
```

- 工程由 XcodeGen 生成（`project.yml`），CI 流程：`xcodegen generate` → `pod install` → `xcodebuild -workspace LemonPlayer.xcworkspace ...`。
- 需要给 `libvlc` 的资源（如 `VLCKit.bundle`）确认打包进 App；静态链接时注意 `-all_load` 相关告警。

### 3.2 能力与接口要点

| 需求 | 实现 |
|---|---|
| 播放 | `VLCMediaPlayer(player:)`、`media = VLCMedia(url:)`、`drawable = UIView` |
| 硬解 | `media.addOption(":codec=all")` + 默认 VideoToolbox 可用；可通过 `VLCAudio`/统计接口检测 |
| 外挂字幕 | `player.addPlaybackSlave(url, type: .subtitle, exclusive: false)` —— **一行接入**，ASS 交给 libass |
| 内嵌字幕轨 | `player.videoSubTitlesIndexes` / `selectSubtitleTrack`（API 名称以头文件为准，M3 验证） |
| 倍速 | `player.rate = 1.5` |
| 音轨 | `player.audioTrackIndexes` / `selectAudioTrack` |
| 进度/时长 | `player.time`、`player.media.length`、`player.position` |
| 状态事件 | `VLCMediaPlayerDelegate`（`mediaPlayerStateChanged`、`mediaPlayerTimeChanged`、`mediaPlayerBuffering`） |
| 画中画 | ❌ 不支持；M7 处理为"置灰 + 说明"或 P2 |
| AirPlay 视频 | ❌（无 AVPlayer 管线）；仅音频可走系统路由 |

### 3.3 已知风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| CocoaPods 依赖 | CI 需要 `pod install`，首次拉取 ~100MB；Podfile 锁版本 | 用 `Podfile.lock` 提交 + `actions/cache` 缓存 `Pods/` 与 `~/.cocoapods` |
| 静态链接体积 | IPA 增大 80–120MB | 可接受（目标 < 300MB） |
| 线程模型 | VLCKit 回调在后台线程 | 统一桥接到 `@MainActor` 或 `AsyncStream` |
| 无 PiP | 与 F-PLAY-10 冲突 | ADR 记录：v1 置灰，需求降级为 P2 |
| 未来上架 | LGPL 需动态链接/可重链接，本文场景只自签，风险低 | 若上架需重新评估（改用 AetherEngine 或购买例外方案） |

---

## 4. 备选：MPVKit（纯 SPM）

### 4.1 包结构（已核实 Package.swift）

- 平台：iOS 15 / macOS 12 / tvOS 15 / visionOS 1
- 产品：`MPVKit`（LGPL）与 `MPVKit-GPL`（含 samba）
- LGPL 版依赖已包含：Libmpv、FFmpeg（Libav*）、**Libass 0.17.5**、libfreetype/fribidi/harfbuzz、libdav1d、libplacebo、MoltenVK、libshaderc、libdovi、libbluray、openssl/gnutls、libuchardet、libuauvs3d
- 体积：binaryTarget 数量多（~30 个 xcframework），首次解析下载量大

### 4.2 集成

```swift
.package(url: "https://github.com/mpvkit/MPVKit", from: "1.1.0")
```

- 渲染：`libmpv` render API → `CAMetalLayer`（`MPVKit` 提供 `MPVPlayer` 示例，需自行封装 `UIView`）
- 字幕：`mpv` 命令 `sub-add <url>`，ASS 由内置 libass 渲染；也可 `sub-fonts-dir` 注入字体
- 优势：无 CocoaPods、包管理干净、CI 简单
- 劣势：作者自述维护频率低；Metal 支持依赖未合并的 mpv patch，可能存在渲染问题；能效较差（约 3 倍于 VLCKit）

### 4.3 何时切到 MPVKit

- M1 验证时 CocoaPods 在 CI 上失败/过慢（> 10 分钟）
- 或 VLCKit 3.7.x 在 iOS 26 上有阻塞性 bug

---

## 5. 观察：AetherEngine（为什么值得关注但不作首选）

**优势**：架构最先进——FFmpeg 只负责 demux，解码交给 VideoToolbox，渲染走 AVPlayer/`AVSampleBufferDisplayLayer`，因此：
- 能效接近系统播放器（41mW vs VLCKit 266mW vs libmpv 887mW）
- HDR/杜比视界/Atmos 走系统能力，画质最好
- 原生 PiP、AirPlay、后台音频
- 外挂字幕是一等公民（注册为轨道）

**不选的原因**（硬约束）：
1. **ASS 特效不渲染**：引擎输出 `SubtitleCue`（文本/CGImage），由宿主自绘。用户要求的"字体/定位/卡拉OK"无法直接满足；若自绘需要额外集成 libass 渲染器，工作量与风险都不小。
2. **工具链要求 Xcode 27 / Swift 6.4**：我们的 CI 计划是 macos-26 + Xcode 26.6（当前 runner 只预装 26.0~26.6）。作者声明 26.3 为 weekly best-effort 兼容，不保证。
3. 只支持 iOS 18+（我们要求 26+，不是问题）。

**触发条件**：如果将来接受"ASS 只做基础样式（字号/颜色/描边）"，或 CI 升级到 Xcode 27 且需要 PiP/能效，可以按 ADR 重新评估。

---

## 6. 落地计划（M1 / M3）

| 阶段 | 动作 | 验收 |
|---|---|---|
| M1 | 工程骨架 + CocoaPods 接入（先不写播放逻辑），CI 跑通 `pod install` + 构建 | Actions 绿，IPA 能出 |
| M1 | 同时建一个"内核隔离"空协议 `PlaybackEngine`，避免 App 层直接依赖 VLCKit 类型 | 编译通过 |
| M3 | 封装 `VLCKitEngine`：加载/播放/暂停/seek/倍速/音轨/字幕轨/事件流 | 能播 4K MKV |
| M3 | 外挂 SRT/ASS 通过 `addPlaybackSlave` 加载，验证 libass 渲染 | ASS 特效正确 |
| M3 | 验证 CJK 字体：内置 Noto Sans SC + 系统字体回退，避免方块字 | 中文/日文字幕正常 |
| M4 | 字幕解析层（SRT/VTT）与 VLCKit 的 ASS 轨道并存：默认 ASS 走内核，SRT/VTT 走自绘 | 样式面板可控 |
| M7 | PiP/AirPlay 结论落地（预计置灰 + 设置里说明） | 文档与 UI 一致 |

---

## 7. 待验证清单（M1/M3 必须回填）

- [ ] MobileVLCKit 3.7.5 在 iOS 26 SDK 下编译无警告/错误（Xcode 26.6）
- [ ] 静态链接方式（`use_frameworks! :linkage => :static`）与 XcodeGen 生成的工程兼容
- [ ] `addPlaybackSlave` 对 ASS 的渲染是否受 `:sub-autodetect-fuzzy` 等参数影响
- [ ] 中文与日语字体回退：iOS 系统字体是否被 libass 正确找到（需 `sub-fonts-dir` 或 `VLCMedia.addOption`）
- [ ] 4K HEVC 10bit HDR 的硬件解码是否生效、色彩是否过暗（tone-map 参数）
- [ ] 网络流 seek 的稳定性（Range 支持已在 API 文档确认，但 VLC 自带缓存策略需调）
- [ ] PiP 是否存在 VLCKit 社区方案（如 `AVSampleBufferDisplayLayer` 转发），M7 再查
