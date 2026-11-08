# Flutter 跨端方案（评估 + 迁移计划）

> 结论：**可行，但这是一条新客户端线，不是"把 Swift 翻译成 Dart"**。
> 建议保留 Swift 版作为稳定版，Flutter 版并行开发、分阶段追平；先做 Phase 0 技术验证，再决定是否全面切换。

## 一、能复用什么、不能复用什么

| 资产 | 复用方式 |
|---|---|
| `docs/api/GUANGYA_API.md`、登录/token 规则 | ✅ 直接复用知识，Dart 重写客户端 |
| 刮削规则（目录→番剧、NCOP/NCED 排除、季数/相似度、分集标题） | ✅ 规则可 1:1 移植到 Dart 包，测试用例照搬 |
| `docs/MODULES.md` 模块拆分与依赖图 | ✅ 直接作为 Flutter 工程分层 |
| `scripts/guangya_scrape.py` / 接口探测经验 | ✅ 用于校验 Dart 实现 |
| UI 设计（VidHub 风格、面板、手势、字幕面板） | ✅ 设计复用，SwiftUI 代码不复用 |
| Packages/*.swift 代码 | ❌ 无法直接复用（需 Dart 重写） |
| MobileVLCKit 播放内核 | ❌ iOS 原生，Flutter 需换内核 |

## 二、技术选型建议

| 能力 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter stable + Dart 3 | 目标 iOS / Android / Windows 桌面 |
| 状态管理 | Riverpod | 与现有 @Observable 思路接近，可测试 |
| 网络 | `dio` + 自定义拦截器 | 对应现有 HTTPClient/重试/UA |
| 安全存储 | `flutter_secure_storage` | 对应 Keychain |
| 本地存储 | `shared_preferences` + `path_provider` | 对应 UserDefaults/Application Support |
| 网页登录 | `webview_flutter` | 抓 localStorage 的 token（同 Swift 方案） |
| 二维码 | `qr_flutter` | 扫码登录页 |
| 播放内核 | **`media_kit`（libmpv）** | MKV/HEVC/DTS、外挂 ASS（libass）最接近现有 VLCKit 能力 |
| 备用播放 | `video_player`（系统 AVPlayer/ExoPlayer） | 仅用于 MP4/HLS 轻量场景 |
| 后台下载 | `background_downloader` | iOS/Android 后台任务 + 断点续传 |
| 画中画/AirPlay | `floating` / 原生插件 | 需要单独评估，短期可缺省 |
| 路由 | `go_router` | 对应 NavigationStack |

### 播放内核风险（必须 Phase 0 验证）

1. `media_kit` 依赖 libmpv：**包体积明显增大**（每 ABI 数十 MB），需确认可接受。
2. 许可证：libmpv/FFmpeg 的 LGPL/GPL 组合需按发布方式确认（与现有 VLCKit 类似，但要单独核对）。
3. iOS 后台音频、锁屏控制、画中画、AirPlay 需要额外插件或原生桥接。
4. ASS 渲染依赖 libass（libmpv 内置），需实测中日文字体与特效。
5. 硬解/HDR 在 Android 机型差异大，需要真机覆盖。

## 三、目标工程结构

```
flutter_app/
  lib/
    main.dart
    app/                 # 壳、路由、主题、启动
    features/
      login/             # 扫码 / 网页登录 / 账号
      browse/            # 网盘浏览
      player/            # 播放器 UI + 手势 + 面板
      subtitles/         # 字幕面板/样式
      library/           # 媒体库
      downloads/         # 下载
      settings/          # 设置/诊断
  packages/ (Dart path packages，对应现有 Packages)
    lemon_core/          # 错误、日志、格式化
    lemon_network/       # HTTP、重试、限流、UA
    lemon_guangya/       # 光鸭 API、auth、文件、播放地址
    lemon_media/         # 文件名解析、目录规则、匹配、分集标题
    lemon_subtitle/      # SRT/VTT/ASS 解析、样式、偏移
    lemon_playback/      # 播放引擎抽象 + media_kit 实现
    lemon_downloads/     # 下载任务
  test/                  # 纯 Dart 单测（对齐现有 122 用例思路）
```

## 四、分阶段计划

### Phase 0：技术验证（1–2 天）
**只验证 4 个高风险点，不写业务 UI：**
1. Flutter SDK 安装 + 空白 App 能在 CI 产出 Android APK（本机无 Android SDK/Java，先走 GitHub Actions）。
2. `media_kit` 播放 HLS + MKV，外挂 ASS 字幕能显示（Windows/Android 任一可跑即可）。
3. Dart 侧用光鸭开发者 API（签名）或网页登录 token 拉取文件列表成功。
4. 确认包体积与许可证可接受。

**验收**：CI 绿 + 一段实拍/截图 + 结论写回本文件；任一项失败则调整选型（如播放改 video_player + 服务端转码、或改用 KMP）。

### Phase 1：地基 + 登录 + 浏览
- Dart 包：core/network/guangya（对照现有 M1/M2/M4 + A2/A3）
- 登录：扫码、网页登录（webview 抓 token）、token 刷新
- 浏览：骨架/空态/排序/搜索/同目录队列

### Phase 2：播放器 + 字幕
- media_kit 封装（状态机、seek、轨道、ASS 挂载）
- 播放器 UI：VidHub 对齐（手势、面板、锁屏、选集）
- 字幕：自动匹配、延迟、字号/边距、字体导入

### Phase 3：媒体库 + 下载 + 设置
- 目录规则/匹配/分集标题（直接移植 Dart）
- background_downloader 后台下载/断点续传/离线播放
- 诊断页（错误/启动/内存/日志导出）

### Phase 4：跨端发布与 CI
- GitHub Actions：`flutter.yml`
  - ubuntu：`flutter test` + Android APK
  - macos：iOS 模拟器构建（无签名）
  - windows：桌面构建（可选）
- 发布：Android APK / iOS 未签名 IPA 流程（需 macos runner + Xcode）
- 平台差异：后台任务、音频会话、PiP/AirPlay 专项

## 五、本机环境现状（2026-11-07）

| 工具 | 状态 |
|---|---|
| Flutter SDK | ❌ 未安装 |
| Dart | ❌ 未安装 |
| Java / Android SDK | ❌ 未安装 |
| Visual Studio BuildTools | ⚠️ 存在，但 Windows 桌面目标需要 Desktop C++ 工作负载，未确认 |
| Node / pnpm | ✅ 存在 |
| 磁盘 | E: 剩余 278GB，足够 |

**本机可先做**：Flutter Web/Dart 单测、纯 Dart 包逻辑（不需要 Android SDK）。
**需要 CI**：Android APK、iOS 构建。

## 六、已确认决策（2026-11-07）

1. **第一目标平台**：**Windows 桌面先验证**（本机可跑通 media_kit 与光鸭 API，再上 Android/iOS）。
2. **Swift 现有版本**：**保留双轨**，v2.0.x 继续维护，Flutter 作为新客户端并行推进。
3. **播放内核**：**media_kit（libmpv）**，Phase 0 重点验证 MKV/HEVC + 外挂 ASS。

## 七、Phase 0 执行记录（进行中）

- [x] Flutter SDK 安装：stable **3.47.9**（`E:\App\flutter`，Dart 3.13.7）
- [x] flutter doctor：Windows 桌面工具链 OK（VS BuildTools 2026 + Windows SDK 10.0.26100）
- [x] `flutter_app/` 骨架（Windows 平台，media_kit + media_kit_video + libs_windows_video）
- [x] `flutter analyze` 无问题、`flutter test` 通过
- [x] Dart 侧光鸭开发者 API：签名 + `/userres/v1/file/get_file_list` → **HTTP 200**，返回根目录 4 项
- [x] media_kit 播放 MKV + 外挂 ASS：**通过**（H.264 MKV，H/W 渲染；`PlayerConfiguration(libass: true)` + ASCII 路径 `.ass` + `SubtitleTrack.uri`）
- [x] media_kit 内置截图（含 libass 字幕）可用：`player.screenshot(includeLibassSubtitles: true)`，OCR 已识别到画面字幕
- [ ] HLS 验证：Apple HLS 样例在 Windows 上位置一直 0/0（未播放），待排查（网络/TLS/HLS demux）
- [ ] 包体积/许可证结论（构建后记录）

### Windows 构建踩坑记录

| 现象 | 解决 |
|---|---|
| `Building with plugins requires symlink support` | 打开 Windows 开发人员模式 |
| CMake INSTALL 试图写 `C:\Program Files\lemon_player` | 显式设置 `CMAKE_INSTALL_PREFIX=build/windows/x64/runner/<Config>` |
| media_kit 下载 mpv/ANGLE 7z 偶发 Integrity check failed | 预下载到 `build/windows/x64` 并校验 MD5（见 `scripts/build-flutter-windows.ps1`） |
| 中文字体/字幕路径 | 字幕临时文件放 ASCII 路径（如 `C:\LemonPhase0\demo.ass`），中文用户名路径下 sub-add 可能失败 |
| 桌面截图全黑（锁屏 session） | 用媒体层截图 `player.screenshot(includeLibassSubtitles: true)` + OCR；flutter-skill `inspect` 通过 ws VM URI |

### Phase 0 结论

- Flutter + media_kit 在 Windows 上**可播放 MKV（含 ASS 特效字幕）**，截图证据：`docs/screenshots/flutter/phase0-mkv-ass.png`
- flutter-skill 可用（`inspect` 需显式 `ws://127.0.0.1:50000/.../ws`；native 截图仍用 media_kit 自带 screenshot 更稳）
- HLS 样例暂未跑通，后续单独排查；光鸭网盘主要是直链 MP4/MKV，不阻塞 Phase 1

## 八、Phase 1 进展（Dart 包）

已完成首批纯 Dart 包（与 Swift Packages 分层对应）：

| 包 | 内容 | 测试 |
|---|---|---|
| `packages/lemon_core` | 统一错误 LemonError、诊断日志、脱敏 | 3 |
| `packages/lemon_network` | dart:io HTTP 客户端、重试策略、UA、限流 | 3 |
| `packages/lemon_guangya` | 开发者签名、文件列表、递归扫描、播放地址 | 4 |

- `dart test` 全部通过；`tool/guangya_probe.dart` 走包级 API 实测 **HTTP 200 / total=4**（Live、来自：云添加、番剧、来自：TOKEN订阅）
### Phase 1 UI（第一版）

- 登录：设备码扫码（真实请求 `account.guangyapan.com/v1/auth/device/code`）、二维码/授权码展示、轮询 pending/authorized/expired、自动刷新；另提供「粘贴 access_token」临时入口
- 网盘浏览：用户态 API `/userres/v1/file/get_file_list`，文件夹进入/返回、刷新、加载骨架、空态、错误重试、退出登录
- 播放：点视频取 `get_res_download_url`，media_kit 播放（libass 开启）
- 已实测：登录页成功获取授权码（`AWrvLZzmqGogA1S_-g`，状态「等待扫码确认」），二维码与授权页 URL 正常显示
- ✅ 扫码登录成功并持久化（SharedPreferences，重启自动登录）
- ✅ 网盘浏览实测：根目录 4 个目录 → 番剧 → 孤独摇滚！ → 剧集列表（08/06/11/04/12…）
- ✅ 播放实测：点 `[DBD-Raws][孤独摇滚!][08][1080P][BDRip][HEVC-10bit][FLAC].mkv` 成功播放（状态「播放：true 13s / …」，窗口截图 `docs/screenshots/flutter/phase1-play-mkv.png`）
- 验证方式：`PrintWindow` 抓窗口 + Windows OCR；DPR-aware 坐标点击（见 `.tmp/click_flutter_text.py`，仅开发脚本）

### flutter-skill 接入（AI 自动化验证）

- 已安装 `flutter-skill` CLI **0.9.36**（npm），并修复 Windows 原生二进制命名 bug（见 `scripts/install-flutter-skill.ps1`）
- `flutter_app` 已加入 `flutter_skill` 依赖，入口在 `kDebugMode` 下初始化 `FlutterSkillBinding`
- 用途：应用跑起来后，CLI/MCP 可执行 `launch / inspect / screenshot / tap`，让 AI 直接看 Flutter 画面并操作，无需写 XCUITest
- 当前同样被 Windows 开发者模式阻塞（launch 需要先能 `flutter run`）

### 当前阻塞

`flutter build windows` 提示：
`Building with plugins requires symlink support. Please enable Developer Mode.`
本进程没有管理员权限，注册表 `HKLM\...\AppModelUnlock` 写入被拒绝。
需要你在 Windows「设置 → 系统 → 开发者选项 → 开发人员模式」打开（或管理员执行）：

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1
```

开启后即可继续：`cd flutter_app && flutter build windows --release` 并运行验证 ASS。
