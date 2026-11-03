# 播放内核选型（iOS，2026-11 版）

> 版本：v0.2 · 更新：2026-11-03 · 对应 ADR-003（内核）、ADR-008（字幕双管线）、ADR-012（分发形态）
> 结论一句话：**主选 MobileVLCKit 3.7.5（CocoaPods + libass）**；MPVKit 作为「字幕样式/双语 ASS 必须达标」时的升级路径；SwiftVLC（libVLC 4 + SPM + 内置 PiP）列为重点观察；AVPlayer 只能兜底。

---

## 0. 结论（TL;DR）

| 项 | 决策 |
|---|---|
| **主选内核** | **MobileVLCKit 3.7.5**（CocoaPods 精确锁版本，LGPLv2.1，内置 libass，tag 发布于 2026-10-30） |
| 分发方式 | **CocoaPods**（VLCKit 3.x 官方**没有** SPM；`pod install` 后再 `xcodebuild -workspace`） |
| 备选（可 30 分钟切换） | **MPVKit 1.0.0**（SPM，mpv v0.41.0，LGPLv3；当前 master/1.1.0 预发布版内置 libass 0.17.5 + FFmpeg n9.0.2，**但 1.1.0 只有 prerelease**，生产应锁 1.0.0） |
| 观察（若 PiP 变为 P0） | **SwiftVLC**（MIT 包装 libVLC 4，SPM，iOS 18+，README 声明 iOS 上支持系统 PiP，但仍是 beta） |
| 不选 | **AVPlayer**：无 MKV demuxer、不能渲染 ASS 特效 → 连"能播"都不满足 |
| 许可前提 | v1 只出未签名 IPA 自签分发（ADR-012）→ GPL 也可接受；**一旦要上架 App Store**，MPVKit（LGPLv3）必须先解决「安装信息」条款，MobileVLCKit（LGPLv2.1）需满足可重链接 |

**为什么是 MobileVLCKit**（4 条理由，按权重排序）：

1. **libass 是真的**：VLC 的 ASS/SSA 由 libass 渲染，字幕脚本自带的字体/定位/卡拉OK 能还原——这是本项目最核心的差异化需求（F-PLAY-07 / F-SUB）。
2. **生产验证最充分**：3.7.5 是 3.x 线的最新稳定 tag（2026-10-30），上一代 3.5/3.6 已在大量上架 App 里跑了多年；`addPlaybackSlave` 外挂字幕是官方一等 API。
3. **许可最干净**：LGPLv2.1（不是 v3），没有 LGPLv3 §6「安装信息」那种与 App Store 冲突的条款；FOSS 社区对 iOS 闭源 App 使用 LGPLv2.1 已有长期共识。
4. **CI 可控**：macos-26 镜像预装 CocoaPods 1.17.0，`pod install` + `actions/cache` 是成熟路径（见 `CI_BUILD.md`）。

**代价（必须写进产品预期）**：无原生 PiP、无视频 AirPlay、无法做"双语 ASS 同时显示"、字号/颜色/描边的用户覆盖能力弱于 mpv、IPA 增大明显（下载包 222 MB，单架构安装增量估算 50–90 MB）、HDR 只能软件 tone-map 不切系统 HDR。

---

## 1. 事实基线（均核实到 2026-11-03）

### 1.1 MobileVLCKit / VLCKit

| 事实 | 数据 | 来源 |
|---|---|---|
| CocoaPods 最新稳定版 | **3.7.5**（3.7.x 线：3.7.0 → 3.7.5；另有 4.0.0a1 / 4.0.0a2 两个早期 alpha） | CocoaPods CDN `all_pods_versions_b_f_7.txt` |
| 3.7.5 tag 时间 | 2026-10-30（tag 说明：`VLCKit 3.7.5 - fix Chromecast on IPv6`） | GitHub `videolan/vlckit` tag |
| podspec 声明的最低 iOS | `platforms.ios = "9.0"` | `MobileVLCKit.podspec.json` |
| 分发形态 | `vendored_frameworks = MobileVLCKit.xcframework`，源包 `MobileVLCKit-3.7.5-<hash>.tar.xz` | 同上 |
| 下载包体积 | **222.1 MB**（tar.xz，含 device+simulator 全切片） | `download.videolan.org` HTTP HEAD |
| 许可 | **LGPL v2.1**（podspec `license.type`） | podspec |
| 依赖的系统库 | QuartzCore/CoreText/AVFoundation/Security/CFNetwork/AudioToolbox/OpenGLES/CoreGraphics/VideoToolbox/CoreMedia + `c++ xml2 z bz2 iconv` | podspec |
| VLCKit 3.x 有 SPM 吗 | **没有**：`3.7.5` tag 下无 `Package.swift`（404） | GitHub raw |
| VLCKit 4 有 SPM 吗 | **有，但只到 alpha**：`master` 与 `4.0.0-a25` 的 `Package.swift` 用 `binaryTarget` 指向 `download.videolan.org/cocoapods/unstable/VLCKit-4.0-20260929-1631.zip`（**879.9 MB**），声明 iOS 12 / macOS 10.13 / tvOS 12 / visionOS 1 | GitHub raw + HEAD |
| 社区 SPM 镜像 `vlckit-spm` | **已停更**：最后 push 2025-02-23，最新 tag `v3.6.0.b10`（67 stars，LGPL-2.1） | GitHub API |
| VLCKit 4 稳定版 | 尚未发布（4.0.0-a1 … a25 全是 alpha，MobileVLCKit 侧只有 a1/a2） | GitHub tags / CocoaPods |

### 1.2 MPVKit

| 事实 | 数据 |
|---|---|
| 最新稳定 release | **1.0.0**（2026-07-25，mpv v0.41.0） |
| 最新 prerelease | 1.1.0-n9.0.2（2026-10-07，mpv v0.41.0 + FFmpeg n9.0.2）——**`prerelease=True`，不要默认上生产** |
| 平台声明 | iOS 15 / macOS 12 / tvOS 15 / visionOS 1（`swift-tools-version:5.9`） |
| 产品 | `MPVKit`（LGPL）与 `MPVKit-GPL`（GPL，多一个 libsmbclient/SMB） |
| 内置字幕 | **Libass 0.17.5**（+ freetype / fribidi / harfbuzz / libunibreak），另有 libplacebo 7.360.1、MoltenVK 1.4.2、libdovi 3.3.2、libdav1d 1.5.3、FFmpeg n9.0.2 |
| 结构 | 30+ 个 `binaryTarget`（每条 FFmpeg 库一条，加 openssl/gnutls/moltenvk/shaderc/lcms2…） |
| 许可 | `MPVKit` 源码 LGPL-3.0；bundle 也 LGPL-3.0；用 `-GPL` 变体则 **GPL-3.0** |
| 作者自述 | 「MPVKit is only suitable for learning `libmpv` and will not be maintained too frequently. For production use, consider … AetherEngine」；「Metal support only a patch version (#7857) and does not officially support it yet」 |
| 实测过的二进制体积 | `Libmpv.xcframework.zip` 18.3 MB、`MoltenVK` 25.8 MB、`Libplacebo` 9.4 MB（单条，合计 30+ 条） |

### 1.3 新出现的两个值得知道的玩家

| 项目 | 关键事实 | 对 LemonPlayer 的意义 |
|---|---|---|
| **SwiftVLC**（`harflabs/SwiftVLC`，612 stars，MIT） | Swift 6 直包 libVLC **4.0**，SPM 分发（`libvlc.xcframework.zip` 由 release 提供，当前 pin `v1.1.0-beta.14`）；要求 **iOS 18+ / Xcode 26.4+ / Swift 6.3+**；README 明确写「iOS 上支持系统 PiP（libVLC 原生 AVKit-backed drawable 路径）」「Swift 6 严格并发安全」 | **它是"VLC 内核 + PiP + SPM"的唯一组合**，但因为上游 libVLC 4 还是 alpha、包装层还是 beta，只能作为 PiP 需求的候选，不作为 v1 主线 |
| **AetherEngine**（`superuser404notfound`，7.55.0，2026-11-03） | LGPL-3.0 **+ App Store 例外**；FFmpeg 只做 demux、VideoToolbox 解码、AVPlayer/`AVSampleBufferDisplayLayer` 渲染；原生 PiP/AirPlay/HDR/Atmos；**要求 Xcode 27 / Swift 6.4**；**不渲染 ASS**，只吐 `SubtitleCue`/`CGImage` 给宿主自绘 | 能力与许可都诱人，但"ASS 特效不渲染"+"要 Xcode 27"两条直接判死。列入 ADR 观察池，不当选 |

---

## 2. 三方案对比矩阵

| 维度 | **MobileVLCKit 3.7.5** | **MPVKit 1.0.0 / 1.1.0-n9.0.2** | **AVPlayer 自研** |
|---|---|---|---|
| 集成 | CocoaPods（必须 `pod install`） | SPM（`from: "1.0.0"`） | 系统框架 |
| 最低 iOS | podspec 写 9.0（实际按 Xcode 26 走，本项目统一 26.0） | 15.0 | 系统版本 |
| 容器 | MKV/MP4/TS/AVI/FLV/WMV/OGG/RM…（libavformat） | 同左（+ DVD/BD ISO、libbluray） | **MP4/MOV/M4V/HLS(fMP4)；MKV 不支持** |
| HEVC | VideoToolbox 硬解 + 软解回退 | 同左 | VideoToolbox（仅 MP4/HLS 内） |
| AV1 | libdav1d 软解（A17 Pro/A18/M3 有硬件但 VLC 3 不走） | libdav1d 软解（同上） | 仅 HLS/fMP4 内的 AV1（iOS 17+ 系统支持有限） |
| HDR10 / HLG | 软件 tone-map 到 SDR，**不切系统 HDR 模式** | libplacebo/MoltenVK tone-map（可 `target-colorspace-hint`，但 HDR 通路脆弱） | **原生 HDR 切换（正确）** |
| Dolby Vision | 只 tone-map，不是 DV 输出 | libdovi 解析 RPU + libplacebo tone-map（P5 效果可用，仍非 DV 输出） | 仅 P5/P8.1 且容器必须是 MP4/HLS |
| AC3/EAC3 | ✅ 软解到 PCM | ✅ | ✅（EAC3 可透传） |
| DTS / DTS-HD MA | ✅ dca 解码（HD 解到 PCM） | ✅ | ❌ 不支持 |
| TrueHD / Atmos | ✅ 解到 PCM（JOC 对象丢失） | ✅ 同左 | 部分（EAC3+JOC 可透传） |
| **ASS/SSA 特效** | ✅ **libass 渲染脚本样式** | ✅ **libass（0.17.5）+ 可强制覆盖样式** | ❌ 完全不支持 |
| 外挂字幕注入 | `addPlaybackSlave:type:enforce:` | `sub-add` 命令 | `AVMutableComposition` 只能塞 WebVTT，需自绘 |
| 字幕样式覆盖（字号/颜色/描边/位置） | ⚠️ 弱：只有全局 option，无法逐条覆盖 | ✅ 强：`sub-ass-override=force` + 全套 `sub-*` 选项 | 自绘，完全可控（但只对 SRT/VTT） |
| 双语字幕同显 | ❌ 无双字幕轨 | ✅ `secondary-sub-*` 第二字幕 | 自绘可做 |
| 后台播放 | ✅（配 `AVAudioSession` + `UIBackgroundModes: audio`） | ✅（需自己 `vid=no` 降级，官方 demo 就这么干） | ✅ 最稳 |
| 画中画 PiP | ❌ 无 AVPlayer/样本缓冲管线 | ❌ 需自建（render → CVPixelBuffer → `AVSampleBufferDisplayLayer`） | ✅ 原生 |
| AirPlay 视频 | ❌ 只能屏幕镜像 | ❌ 同左 | ✅ `AVRoutePickerView` + 外部播放 |
| 能耗（第三方基准，4K HDR HEVC 38Mbps） | 266 mW / 15% CPU | **887 mW / 21% CPU** | 41 mW / 4.4%（AetherEngine 数，仅供量级参考） |
| 二进制体积 | 下载 222 MB；**安装增量估算 50–90 MB** | 30+ 二进制包，**安装增量估算 80–150 MB** | ≈0 |
| 许可 | **LGPLv2.1** | **LGPLv3**（GPL 变体含 SMB） | 无 |
| 维护活跃度 | ✅ 3.7.5（2026-10），仓库 2026-11-01 仍有提交 | ⚠️ 作者明示"低频维护、仅适合学习" | — |
| CI | `pod install`（可缓存） | 纯 SPM，最省心 | — |

> 能耗/温度数据来自 [AetherEngine README 的公开基准](https://github.com/superuser404notfound/AetherEngine)（MacBookAir10,1 / macOS 27 / 4K HDR HEVC），**只是相对量级**，不是 iPhone 实测。但它和"libmpv 在 iOS 上重（MoltenVK + 全 FFmpeg）"的工程直觉一致，可作为选型参考，不作为验收指标。

---

## 3. 主选：MobileVLCKit 3.7.5

### 3.1 集成步骤（CocoaPods + XcodeGen）

```ruby
# Podfile
platform :ios, '26.0'

# 静态链接：避免未签名动态 dylib 在自签工具里被漏签（ADR-003 的选择）
use_frameworks! :linkage => :static

target 'LemonPlayer' do
  # 精确锁版本，配合提交 Podfile.lock，CI 才可复现
  pod 'MobileVLCKit', '3.7.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
    end
  end
end
```

CI/本地的顺序（**不能颠倒**）：

```bash
brew install xcodegen            # 镜像未预装
xcodegen generate --spec project.yml   # ① 生成 .xcodeproj
pod install                            # ② 在 .xcodeproj 之上注入 Pods
xcodebuild -workspace LemonPlayer.xcworkspace ...   # ③ 必须用 workspace
```

工程侧还要确认三件事（M1 验收项）：

1. `project.yml` 里 target 的 `dependencies` 不要手写 VLCKit；
2. `Podfile.lock` 提交进仓库（`pod install --deployment` 或直接校验 lock）；
3. 首次安装后检查 `.app` 内是否带上了 VLCKit 的 bundle/资源，以及 `Frameworks/` 是否为空（为空=静态链接成功）。

### 3.2 播放与视频输出

```swift
import MobileVLCKit

final class VLCKitEngine: NSObject, PlaybackEngine, VLCMediaPlayerDelegate {
    private let player = VLCMediaPlayer()

    func attach(to view: UIView) {
        player.drawable = view        // VLC 自己往这个 view 的 layer 上贴视频
        player.delegate = self
    }

    func load(url: URL, headers: [String: String]) {
        let media = VLCMedia(url: url)
        // 光鸭直链常需要带 Referer / User-Agent
        media.addOption(":http-referrer=\(headers["Referer"] ?? "https://www.guangyapan.com/")")
        media.addOption(":http-user-agent=\(headers["User-Agent"] ?? "Mozilla/5.0")")
        // ⚠️ VLC 3 没有通用的 :http-header=（任意 header 得靠 :http-forward-cookies
        //    或 VLC 4 的新接口）；M3 必须实测光鸭签名链接到底需要哪几个头
        media.addOption(":network-caching=2000")   // 网络盘建议 1.5~3s
        player.media = media
        player.play()
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) { /* 状态机 */ }
    func mediaPlayerTimeChanged(_ aNotification: Notification) { /* 进度 */ }
    func mediaPlayerBuffering(_ player: VLCMediaPlayer!) { }
}
```

要点：

- `drawable` 是一个 `UIView`，VLC 通过 `CAEAGLLayer`/`CALayer` 子层输出，**拿不到 `CMSampleBuffer`**——这直接决定了 PiP 与"自绘叠加视频"都做不了（见 §6.5）。
- 回调在后台线程，必须桥到 `@MainActor`（Swift 6.3 严格并发下这是编译期要求，不是建议）。
- 倍速/音轨/视频轨：`player.rate`、`player.audioTrackIndexes`（以 `VLCMediaPlayer.h` 为准）。

### 3.3 外挂字幕：官方 API 就一行

头文件里真实存在（**注意签名是 `enforce:`，不是网上很多文章写的 `content:`/`exclusive:`**）：

```objc
- (int)addPlaybackSlave:(NSURL *)slaveURL
                   type:(VLCMediaPlaybackSlaveType)slaveType
                enforce:(BOOL)enforceSelection;
```

Swift 用法：

```swift
// 本地字幕（先从光鸭下载/导出到 App 容器，再用 file URL）
let ret = player.addPlaybackSlave(localSubtitleURL, type: .subtitle, enforce: true)

// 内嵌字幕轨
for (i, name) in player.videoSubTitlesNames.enumerated() {
    print(i, name)                       // 语言/描述
}
player.currentVideoSubTitleIndex = player.videoSubTitlesIndexes[0] as! Int32
player.currentVideoSubTitleDelay = 500_000   // 单位：微秒（0.5s）
```

配套 API（同头文件）：

| 能力 | API |
|---|---|
| 当前字幕轨 | `currentVideoSubTitleIndex` |
| 轨道名 / 轨道 ID 列表 | `videoSubTitlesNames` / `videoSubTitlesIndexes` |
| 字幕轨数量 | `numberOfSubtitlesTracks` |
| 字幕延迟（微秒） | `currentVideoSubTitleDelay` |
| 从文件加载（已废弃） | `openVideoSubTitlesFromFile:` → 用 `addPlaybackSlave` 替代 |

**"外部字幕喂给内核"的落地细节**：

- 光鸭云盘的字幕文件在云端 → 先下到 `Caches/SubtitleCache/<hash>.ass`，再 `addPlaybackSlave` 传 **file URL**（VLC 对 `http(s)` 字幕支持不稳，且跨域头难带）。
- 编码：VLC 会用 `--subsdec-encoding` 自动探测；GBK 需要显式 `media.addOption(":subsdec-encoding=GB18030")`（M3 实测）。
- 换字幕不用重建 `VLCMediaPlayer`：`addPlaybackSlave` 可重复调用；切轨用 `currentVideoSubTitleIndex`。

### 3.4 字幕样式能做到什么程度（重要）

| 需求 | MobileVLCKit 能做到 | 说明 |
|---|---|---|
| ASS 脚本自带的字体/定位/特效 | ✅ 由 libass 还原 | 这是它的核心价值 |
| 字号/颜色/描边/阴影（全局覆盖） | ⚠️ 只能通过 `--freetype-*` / `--sub-margin` / `--sub-delay` 这类**全局 option**（`VLCMedia.addOption` 或 `VLCLibrary` 初始化参数） | 无 mpv 的 `sub-ass-override=force`；改一次要重载媒体 |
| 位置（垂直偏移） | ⚠️ `--sub-margin` 粗调 | 不能精确到像素 |
| 延迟 | ✅ `currentVideoSubTitleDelay`（微秒级、实时） | 完全够用 |
| 逐条字幕样式 / 按字号缩放 ASS | ❌ | libass 按脚本走，VLC 不给 override 开关 |
| 双语字幕同显 | ❌ | VLC 3 没有副字幕轨 |
| 自定义字体导入（TTF/OTF） | ⚠️ `--sub-fonts-dir` 之类需要实测 | F-SUB-13 是 P2，可延后 |

**落地建议（与 ADR-008 一致）**：ASS/SSA 一律交给内核 libass 渲染，样式面板对 ASS **只暴露"延迟 + 位置粗调 + 开关"**；SRT/VTT 走自绘 overlay（CoreText），样式面板的全部能力（字号/颜色/描边/背景/位置/双行）只对 SRT/VTT 生效。UI 上按格式自适应，不要承诺"ASS 也能改字号"。

### 3.5 后台播放 / PiP / AirPlay

| 能力 | 结论 | 实现要点 |
|---|---|---|
| 后台音频 | ✅ 可行 | `AVAudioSession` 设 `.playback` + `Info.plist` `UIBackgroundModes = audio`；进入后台时 VLC 会继续解码音频，但**视频层会被系统回收**，需要 `player.drawable = nil` 并在回前台重建，否则黑屏 |
| 后台下载 | ✅ 与内核无关 | `URLSession` background configuration + `BGTaskScheduler`；注意与播放抢带宽 |
| 画中画 | ❌ v1 不做 | 没有 `AVPlayerLayer`/`CMSampleBuffer` 通路；见 §6.5 的三条改造路径，成本 2–4 周起 |
| AirPlay 视频 | ❌ v1 不做 | `AVRoutePickerView` 选中的路由只接管 `AVPlayer`；第三方内核只能走系统"屏幕镜像" |
| AirPlay 音频 | ⚠️ 部分可行 | VLC 的音频输出走 `AVAudioSession`，切到 AirPlay 扬声器能出声，但延迟大、音画不同步 |
| 锁屏/控制中心 | ✅ | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` 自己实现，与内核无关 |
| 来电/中断 | ✅ | 监听 `AVAudioSession.interruptionNotification`，恢复时 `player.play()` |

### 3.6 许可（LGPLv2.1）与合规

- **LGPLv2.1 允许闭源 App 动态链接**；采用**静态链接**时，§6 要求向用户提供"可重新链接"的形式（目标文件或源码）。
- v1 只做**自签分发**（ADR-012），不构成"分发"，合规压力为零；**上架 App Store 前必须二选一**：
  1. 改回动态 framework（`use_frameworks!`，保持 `Frameworks/MobileVLCKit.framework`），并在"关于"页声明 LGPL 与源码地址；
  2. 或提供可重链接材料（打包 `.a` + `.o`），实操上没人这么干。
- 还要在"关于/开源许可"页列出：VLCKit（LGPLv2.1）、FFmpeg（LGPLv2.1+，注意其中某些组件是 GPL，若开启 `--enable-gpl` 编码器则整体 GPL——VLC 官方 iOS 构建的 FFmpeg 是 LGPL 配置）、libass（ISC）、FreeType（FTL/GPLv2 双许可，选 FTL）等。N-11 已要求这张清单。

---

## 4. 备选：MPVKit

### 4.1 什么时候该切过去

同时满足下面任意一条就该认真评估：

- 产品要求 **ASS 样式可覆盖**（用户改字号/颜色/描边）+ **双语 ASS 同显**——VLC 做不到；
- 需要 `sub-fonts-dir` 级别的自定义字体（F-SUB-13）；
- CocoaPods 在 CI 上出现无法解决的耗时/缓存问题。

### 4.2 集成

```swift
// project.yml（XcodeGen）或 Package.swift
dependencies:
  - package: MPVKit
    version: 1.0.0        # ← 用稳定 tag；1.1.0-n9.0.2 目前是 prerelease
```

首次解析会拉 30+ 个 xcframework（合计几百 MB），CI 必须缓存 `SourcePackages`（见 `CI_BUILD.md` §3、§7.3）。

### 4.3 渲染接入（这是它最贵的地方）

MPVKit 官方 iOS Demo 有三条路，全部要自己写 UIKit/SwiftUI 封装：

| 路线 | 做法 | 代价 / 风险 |
|---|---|---|
| **A. MoltenVK + `wid`**（官方 Demo 主路径） | `vo=gpu-next`、`gpu-api=vulkan`、`gpu-context=moltenvk`，把 `CAMetalLayer` 指针塞给 `wid` | HDR 播放与 Metal API Validation 冲突（Demo 注释直接要求关掉 validation），依赖未合并的 mpv Metal patch；`target-colorspace-hint` 只能在 create 前设 |
| **B. OpenGL ES render API** | `mpv_render_context_create(MPV_RENDER_API_TYPE_OPENGL)` + `CAEAGLLayer` | OpenGL ES 在 iOS 已弃用，10bit/HDR 通路受限 |
| **C. 自建样本缓冲** | render 到 IOSurface 支持的 `CVPixelBuffer` → `CMSampleBuffer` → `AVSampleBufferDisplayLayer` | 唯一能同时拿到 PiP 的路线，但工作量最大（见 §6.5） |

Demo 里的背景处理也说明问题：`enterBackground` 时直接 `pause()` + `vid=no`，回前台再恢复——**mpv 方案没有现成的后台视频通路**。

### 4.4 字幕（它最强的地方）

```swift
// 外挂字幕（注意路径转义，或改用 mpv_command 的 argv 形式）
mpv_command_string(mpv, "sub-add \"\(path)\" select")
// 更稳：const char *args[] = {"sub-add", path.c_str(), "select", NULL}; mpv_command(mpv, args);

// 第二字幕（双语字幕 P1 需求）
mpv_set_option_string(mpv, "secondary-sub-visibility", "yes");
// 播放中：mpv_command_string(mpv, "set secondary-sid \(trackId)");
```

样式能力（mpv manual 的 `sub-*` 选项族，几乎覆盖产品要的全部）：

| 产品需求 | mpv 选项 |
|---|---|
| 字号 | `sub-font-size` / `sub-scale` |
| 颜色 | `sub-color`、`sub-back-color` |
| 描边 | `sub-border-color`、`sub-border-size` |
| 阴影 | `sub-shadow-color`、`sub-shadow-offset` |
| 位置 | `sub-pos`（0–100 垂直百分比）、`sub-align-*` |
| 延迟 | `sub-delay`（秒，可负） |
| 强制覆盖 ASS 样式 | `sub-ass-override=force`（还有 `strip`/`scale`/`yes`/`no`） |
| 自定义字体 | `sub-fonts-dir`、`sub-font`、`embeddedfonts=yes` |
| 双语 | `secondary-sub-*` 全家族 + `secondary-sid` |

### 4.5 风险（为什么它不是主选）

| 风险 | 说明 |
|---|---|
| **许可** | LGPLv3。§6 的「Installation Information」条款针对 "User Product"，iPhone 属于 User Product → 闭源上架需要 App Store 例外条款，**MPVKit 没有**（AetherEngine 有）。v1 自签无所谓；上架前必须先解决（换 FFmpeg/VLC 路线，或自己 fork 加例外，或开源） |
| 稳定性 | 作者自述"仅适合学习、不频繁维护"；`1.1.0-n9.0.2` 仍是 prerelease |
| 渲染 | Metal 走 MoltenVK + 未合并 patch；HDR 需要关 Metal validation；`gpu-next` 参数脆弱 |
| 能效 | 第三方基准里 libmpv 的 GPU/CPU 功耗是 VLCKit 的 3 倍以上，长视频发热/掉电明显 |
| 体积 | 30+ 二进制包，IPA 增量大于 VLCKit |
| 后台/PiP | 都要自己写，官方 Demo 只演示 `vid=no` |

---

## 5. 为什么 AVPlayer 只能兜底

| 限制 | 后果 |
|---|---|
| **没有 MKV demuxer** | 光鸭片源以 MKV 为主 → 直接不可播。AVFoundation 只认 MP4/MOV/M4V/HLS(fMP4) |
| **不能渲染 ASS/SSA** | `AVPlayerItemLegibleOutput` 只给 WebVTT/文本 cue，ASS 特效无从谈起 |
| 不支持 DTS / DTS-HD / TrueHD | 大量蓝光 remux 无声 |
| 无法软解 AV1 GVC/特殊 profile | 兼容性差 |
| "自研"等于自研播放器 | 要自己 demux（FFmpeg）+ VideoToolbox 解码 + 音画同步 + 渲染层 + 字幕叠加，工期与风险远超引入现成内核；AetherEngine 走的就是这条路，用的还是 Xcode 27 |

**唯一该用 AVPlayer 的场合**：MP4/HLS 直链的"快速通道"（起播快、原生 HDR/PiP/AirPlay），作为**可选优化**而不是内核。v1 不做（复杂度不值得）。

---

## 6. 关键交叉问题（选型时最容易踩的）

### 6.1 外挂字幕怎么喂给内核（对照表）

| 内核 | API | 远程 URL 支持 | 编码控制 | 备注 |
|---|---|---|---|---|
| MobileVLCKit | `addPlaybackSlave:type:enforce:` | 弱（建议先落盘） | `:subsdec-encoding=` | 一行接入，最省事 |
| MPVKit | `sub-add <url> select` | ✅（mpv 自带 http） | `--sub-codepage` | 需要处理路径转义 |
| AVPlayer | — | — | — | 只能自绘 |

### 6.2 三种"字幕样式自定义"的实现层级

| 层级 | 能力 | 适用 |
|---|---|---|
| L1 内核渲染（ASS → libass） | 只还原脚本，覆盖能力弱（VLC）/强（mpv） | ASS/SSA |
| L2 自绘 overlay（CoreText/SwiftUI） | 完全可控：字号/颜色/描边/阴影/位置/双行/动画 | SRT/VTT |
| L3 预处理（把 SRT 转 ASS 再喂内核） | 借 libass 拿到"样式能力"，但样式要在转换时写死 | 想统一走内核时的折中，**不推荐**（改样式要重新生成文件） |

**结论**：ADR-008 的双管线是对的，L1+L2 并存；**不要**为了"统一样式面板"把 ASS 也搬到 overlay（特效会全丢）。

### 6.3 双语字幕（F-SUB-09，P1）

| 内核 | 可行性 |
|---|---|
| MobileVLCKit | ❌ 无双字幕轨。变通：主字幕走内核 ASS，副字幕用 L2 overlay 渲染 SRT（但副字幕若是 ASS，特效丢失） |
| MPVKit | ✅ `secondary-sid` + `secondary-sub-*` |
| AVPlayer | 自绘可做 |

→ **如果双语是硬需求，这就是切 MPVKit 的最强理由**。建议 v1 先把双语做成"主字幕内核 + 副字幕 overlay（仅 SRT/VTT）"，并在 UI 上说明限制；v1.1 再评估内核切换。

### 6.4 后台播放（三方案都要做的公共件）

```swift
// App 启动或首次播放时
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .moviePlayback, options: [])
try session.setActive(true)

// Info.plist
// UIBackgroundModes = ["audio"]
```

- 第三方内核**不会**自动帮你处理路由变化/中断，需要自己监听 `AVAudioSession.routeChangeNotification`、`interruptionNotification`、`mediaServicesWereResetNotification`。
- VLC 进后台后视频层失效（黑屏），**必须**在 `willResignActive` 保存 `player.time`、`drawable = nil`，回前台重建 drawable 并 seek 回去；否则回前台大概率黑屏（这是社区高频坑）。
- mpv 路线更麻烦：官方 Demo 直接 `vid=no`，等于"后台只听声音"。要"后台继续出画面"只能进 PiP 路径（§6.5）。

### 6.5 画中画（F-PLAY-10，P1）：三条路径与成本

| 路径 | 前提 | 工作量 | 结论 |
|---|---|---|---|
| **P1. AVPlayer 原生** | 必须是 AVPlayer 管线 | ≈0 | 与 VLC/mpv 内核不兼容 |
| **P2. `AVSampleBufferDisplayLayer` 转发**（第三方内核通用解） | 能把解码帧变成 `CMSampleBuffer`：A) mpv render API → `CVPixelBuffer`（IOSurface 支持）→ `CMSampleBufferCreateReadyWithImageBuffer`；B) VLC 无 render API，需改 libvlc 用 `libvlc_video_set_callbacks`（VLCKit 3 未暴露） | **2–4 周**（含 HDR/10bit 像素格式、timebase、字幕烧录进帧、PiP delegate） | mpv 可行；VLC 基本不可行 |
| **P3. 换 SwiftVLC（libVLC 4）** | README 声明 iOS 支持 PiP（libVLC 原生 AVKit-backed drawable） | **1–3 天验证 + 风险** | 若 PiP 升级为 P0，这是最短路径；但要用 beta 依赖 + iOS 18 下限 |

`AVSampleBufferDisplayLayer` 路线必须注意：

- `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`，配合 `AVSampleBufferDisplayLayer.sampleBufferRenderer`（iOS 17+）；
- 必须保持 `AVAudioSession` 处于播放态，否则 PiP 窗口会被系统关掉；
- 字幕**不会**自动出现在 PiP 窗口里——要么把字幕烧进帧（mpv 可以 `sub-visibility=yes` 后直接渲进画面），要么接受 PiP 无字幕；
- 10bit HDR 需要用 `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` 并为 display layer 设置正确的色彩附件，否则偏色。

### 6.6 AirPlay（F-PLAY-11，P1）

- `AVRoutePickerView` 本身只是"路由选择 UI"，**真正接管播放的是 `AVPlayer`**（`allowsExternalPlayback`）。第三方内核选中 AirPlay 路由后，系统不会把 VLC/mpv 的画面送过去。
- 第三方内核的现实能力：
  - **音频**可以走（`AVAudioSession` 的 `currentRoute` 变成 AirPlay 扬声器），但延迟 2s 上下，音画不同步；
  - **视频**只能靠"屏幕镜像"（控制中心 → 屏幕镜像），锁屏即断、画质降级、耗电。
- 结论：v1 对第三方内核**置灰 AirPlay 视频按钮**并写明原因（与 ADR 一致）；"音频投到 HomePod"可作为 P2 小功能。

### 6.7 App Store 审核风险（只在"要上架"时才成立）

| 风险 | 具体条款/后果 | 缓解 |
|---|---|---|
| **GPL 传染** | MPVKit-GPL / 自编译开 GPL 的 FFmpeg → 整个 App 必须 GPL 开源 | 永远用 LGPL 变体；CI 里加校验（见下） |
| **LGPLv3 安装信息** | MPVKit 的 LGPLv3 在 iPhone（User Product）上要求提供"安装修改版本"的能力 → 与 App Store 的签名模型冲突 | 用带 App Store 例外的库，或改用 LGPLv2.1（VLCKit），或开源 |
| **LGPLv2.1 可重链接** | 静态链接 VLCKit 时必须提供可重链接材料 | 改动态 framework；"关于"页给源码地址 |
| **私有 API** | 例如用私有 `_AVPictureInPictureController` 强行给第三方内核开 PiP → 拒审 | 只用公开 API（`AVSampleBufferDisplayLayer` 路线） |
| **后台常驻** | 无 `UIBackgroundModes` 却持续播放/下载 | 老老实实声明 `audio` + `fetch`/`processing`，并在审核备注里说明用途 |
| **二进制体积** | >200MB 触发 cellular 下载提示，影响转化 | App Thinning + 只保留 arm64 + 剥离 dSYM；必要时 On-Demand Resources |
| **隐私清单** | 缺 `PrivacyInfo.xcprivacy`（required reason API）会被拒 | 项目已计划（N-11）；VLC/FFmpeg 自身也需补 |
| **版权内容** | 播放器本身合规，但"云盘直连 + 影视库"容易被审核问"内容来源" | 上架版本去掉任何内置片源/刮削默认源，仅保留网盘挂载 |

CI 里可以加一条 GPL 守卫（防手滑）：

```bash
# 出现这些符号/包名，说明混入了 GPL 配置
! grep -R "MPVKit-GPL\|libsmbclient" Package.resolved Podfile.lock 2>/dev/null || {
  echo "::error::检测到 GPL 变体依赖，请改用 LGPL 构建"; exit 1; }
```

---

## 7. 最终推荐与落地

### 7.1 决策表

| 项 | 决定 |
|---|---|
| 内核 | **MobileVLCKit 3.7.5**（`pod 'MobileVLCKit', '3.7.5'`，精确锁版本） |
| 分发 | CocoaPods + 提交 `Podfile.lock`；CI `pod install` |
| 链接方式 | `use_frameworks! :linkage => :static`（M1 实测 `.app/Frameworks/` 为空即确认静态） |
| 模块归属 | 封装在 **`LemonPlayback`** 包内的 `VLCKitEngine`（App target 仍叫 `LemonPlayer`），**只有这一层可以 `import MobileVLCKit`**（ADR-010 的依赖约束） |
| 字幕策略 | ASS/SSA → 内核 libass（只给延迟/位置/开关）；SRT/VTT → 自绘 overlay（全样式） |
| PiP / AirPlay | v1 置灰 + 说明；PiP 升级为 P0 时按 §6.5 的 P2/P3 方案评估 |
| 备选触发 | ①需要 ASS 样式覆盖或双语 ASS；②CocoaPods 在 CI 不可用 → 切 **MPVKit 1.0.0** |
| 上架触发 | 任何"要上 App Store"的决定 → 重开 ADR-003，按 §6.7 逐条过 |

### 7.2 内核抽象（第一次提交就落地，别等）

```swift
// LemonPlayer/PlaybackEngine.swift —— App 层只认这个协议
public protocol PlaybackEngine: AnyObject {
    var state: AsyncStream<PlaybackState> { get }
    var time: AsyncStream<TimeInterval> { get }
    func attach(to host: UIView)
    func load(url: URL, headers: [String: String]) async throws
    func play(); func pause(); func seek(to: TimeInterval)
    func setRate(_ rate: Float)
    var audioTracks: [Track] { get }; var subtitleTracks: [Track] { get }
    func selectAudioTrack(_ id: String)
    func selectSubtitleTrack(_ id: String)
    func addExternalSubtitle(_ url: URL) throws       // 外挂字幕统一入口
    func setSubtitleDelay(_ seconds: Double)
}
```

有了它，VLCKit ↔ MPVKit 的切换成本是"一个新实现 + 一次回归"，而不是"重写播放页"。

### 7.3 验收（M1 / M3）

| 阶段 | 动作 | 通过标准 |
|---|---|---|
| M1 | `project.yml` + Podfile 接入，空 App 编译 | CI 绿；`.app` 能出；`pod install` 耗时被缓存到 <1 分钟 |
| M1 | 内核隔离协议 + 一个假实现 | App 能编译不依赖 VLCKit 类型 |
| M3 | 真机播 4K HEVC MKV（含 DTS） | 起播 <3s；seek 可用；音轨切换不崩 |
| M3 | 外挂 ASS（含特效）+ 内嵌 ASS | 特效正确；中文/日文字体不缺字 |
| M3 | 字幕延迟 ±5s、位置调整 | 实时生效、不重启播放 |
| M3 | 后台播放 10 分钟 + 回前台 | 音频不断；回前台画面恢复（不黑屏） |

### 7.4 回填与待验证（写回 `docs/PROGRESS.md`）

- [ ] MobileVLCKit 3.7.5 在 Xcode 26.6 / iOS 26 SDK 下编译是否干净（Swift 6.3 严格并发）
- [ ] 静态链接后 `.app/Frameworks/` 是否为空；IPA 实际增量（估算 50–90 MB）
- [ ] `addPlaybackSlave(enforce:)` 对 `http(s)` 字幕的实际表现（决定是否必须先落盘）
- [ ] GBK/UTF-16 字幕：`:subsdec-encoding` 的有效取值
- [ ] 中文/日文字体回退：libass 是否找得到系统字体；缺字时的 fallback
- [ ] 4K HDR10 HEVC 的 tone-map 观感（是否需要传参数调亮度/对比）
- [ ] 后台→回前台重建 `drawable` 的时序（黑屏复现率）
- [ ] 光鸭直链带 Referer/UA/cookie 时的真实写法（`:http-referrer` / `:http-user-agent` / `:http-forward-cookies` 哪个生效）
- [ ] MPVKit 1.0.0 的可选验证：`sub-ass-override=force` + 双语在真机上的表现（决定 v1.1 是否切换）
- [ ] SwiftVLC 的 PiP 验证（仅当 PiP 升级为 P0）

---

## 8. 事实来源（抓取时间 2026-11-03）

- MobileVLCKit 版本清单（含 3.7.5 为最新稳定、4.0.0a1/a2）：<https://cdn.cocoapods.org/all_pods_versions_b_f_7.txt>
- MobileVLCKit 3.7.5 podspec（iOS 9.0、LGPL v2.1、vendored xcframework、依赖）：<https://cdn.jsdelivr.net/cocoa/Specs/b/f/7/MobileVLCKit/3.7.5/MobileVLCKit.podspec.json>
- 3.7.5 tag 与提交时间（2026-10-30）、`VLCMediaPlayer.h`（`addPlaybackSlave:type:enforce:`、`currentVideoSubTitleIndex/Delay`）：<https://github.com/videolan/vlckit>
- VLCKit 3.7.5 无 `Package.swift`（SPM 不支持）；`master` / `4.0.0-a25` 的 SPM `binaryTarget`（VLCKit 4.0 unstable，879.9 MB）：<https://raw.githubusercontent.com/videolan/vlckit/master/Package.swift>
- 社区 SPM 镜像停更（最后 push 2025-02-23，最新 tag v3.6.0.b10）：<https://github.com/tylerjonesio/vlckit-spm>
- MPVKit `Package.swift`（iOS 15、Libass 0.17.5、MoltenVK、libplacebo、FFmpeg n9.0.2、LGPL/GPL 双产品）：<https://raw.githubusercontent.com/mpvkit/MPVKit/master/Package.swift>
- MPVKit releases（1.0.0 稳定 / 1.1.0-n9.0.2 prerelease）与 README（"仅适合学习"、Metal 非官方、许可）：<https://github.com/mpvkit/MPVKit>
- MPVKit iOS Metal 接入（`vo=gpu-next` + `gpu-api=vulkan` + `gpu-context=moltenvk` + `wid`、后台 `vid=no`）：<https://github.com/mpvkit/MPVKit/blob/main/Demo/Demo-iOS/Demo-iOS/Player/Metal/MPVMetalViewController.swift>
- SwiftVLC（MIT、libVLC 4、SPM、iOS 18+/Xcode 26.4+、iOS PiP 声明）：<https://github.com/harflabs/SwiftVLC>
- AetherEngine（LGPL-3.0 + App Store 例外、Xcode 27、能效对比表、ASS 不自渲染）：<https://github.com/superuser404notfound/AetherEngine>
