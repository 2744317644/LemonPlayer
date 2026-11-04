# LemonPlayer 交付说明（v1.0.0）

> 更新：2026-11-05 · 状态：**v1.0.0 已发布**（功能冻结，真机验收中）
> 仓库：https://github.com/2744317644/LemonPlayer（private）
> 正式包：https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0

---

## 1. 这是什么

Swift / SwiftUI 原生 iOS 播放器：登录**光鸭云盘**后直接浏览、流式播放网盘里的 MKV/HEVC，外挂字幕（SRT/VTT/ASS 特效、自动匹配、GBK 识别、时间轴校准、样式、双语、按文件记忆、自定义字体）作为核心能力；附带 Bangumi 海报墙（TMDB 可选兜底）、剧集连播、断点续播、后台下载与离线播放。登录支持：账号密码 / 扫码（设备码）/ Token 直登 / 浏览器授权页兜底。

- 最低系统：iOS 26.0（iPhone / iPad）
- 构建：GitHub Actions（macos-26-intel + Xcode 26.6）→ 未签名 IPA
- 分发：自签（Sideloadly / AltStore / 任意签名工具）

---

## 2. 交付物

| 交付物 | 位置 |
|---|---|
| 源码（8 个 SPM 包 + App） | `Packages/**`、`Sources/LemonPlayer/**` |
| 需求/目标/看板/进度 | `docs/REQUIREMENTS.md`、`GOALS.md`、`TASKS.md`、`PROGRESS.md` |
| 架构与决策 | `docs/ARCHITECTURE.md`、`docs/DECISIONS.md`（ADR-001~017） |
| API 逆向参考 | `docs/api/GUANGYA_API.md`（22 接口 + 实测校正）、`docs/api/BANGUMI_API.md` |
| 内核/CI 调研 | `docs/tech/PLAYER_KERNEL.md`、`docs/tech/CI_BUILD.md` |
| 安装说明 | `docs/INSTALL.md` |
| 回归清单 | `docs/qa/REGRESSION.md` |
| 可安装包 | GitHub Releases（rc1~rc8），附件未签名 IPA + SHA256 |
| CI | `.github/workflows/build.yml`（单测 + 构建 + artifact）；`release.yml`（tag → Release） |

---

## 3. 功能清单（对照需求）

| 需求 | 状态 | 说明 |
|---|---|---|
| 扫码登录（设备码 OAuth2） | ✅ | 含二维码自动换码、切后台网络重试、回前台自动恢复 |
| 网页登录（推荐） | ✅ | App 内 WKWebView 打开官网 `/oauth/login`，手机验证码/密码登录后自动抓取 token |
| 账号密码（API 直连） | ⚠️ 受风控 | `/v1/auth/signin` 需 `x-captcha-token`，纯 API 会被拒；请用网页登录 |
| 浏览器授权页兜底 | ✅ | 显示/复制设备码，一键打开授权页 |
| Token 直登 | ✅ | 粘贴 JWT，`/user/me` 探测后落库（临时联调通道） |
| 登录态持久化 / 自动刷新 | ✅ | Keychain + single-flight refresh + 内存兜底 |
| 目录浏览（分页/面包屑/排序/搜索） | ✅ | 光鸭无服务端搜索，采用当前目录本地过滤 |
| 直链流播 + 失效自动重取 | ✅ | `get_res_download_url`，403/播放失败刷新 token 重取并 seek 回原位置 |
| MKV / HEVC / DTS 全格式 | ✅ | MobileVLCKit 3.7.5 |
| 外挂字幕自动匹配 | ✅ | 同名规范化 + 集号校验 + 语言后缀 + 格式优先级 |
| GBK / UTF-8 编码识别 | ✅ | BOM → UTF-8 → GB18030 → BIG5 → 兜底 |
| SRT/VTT 自绘样式 | ✅ | 字号/颜色/描边/背景/底边距实时生效 |
| ASS/SSA 特效渲染 | ✅ | 内核 libass（字体/定位/卡拉OK） |
| ASS 自定义字体导入 | ✅ | 播放页「字幕 → 导入 ASS 字体」，字体库经 `:sub-fonts-dir` 注入 |
| 字幕时间轴校准 | ✅ | ±0.1s；ASS 改时间戳保标签，SRT 重新序列化 |
| 双语字幕 | ✅ | 主/副字幕叠加 |
| 按文件记忆字幕与偏移 | ✅ | SubtitlePreferenceStore |
| 断点续播 | ✅ | 进度每 5s 落盘，重进跳转 |
| 海报墙 / 详情 / 剧集列表 | ✅ | Bangumi 优先，TMDB 可选兜底 |
| 剧集连播 | ✅ | 播放队列 + 结束自动下一集 |
| 继续观看 | ✅ | 媒体库首页横向卡片 |
| 倍速 / 音轨 / 字幕轨 | ✅ | 0.25~4x、音轨菜单、字幕轨开关 |
| 后台音频 / 锁屏控制 | ✅ | AVAudioSession + Now Playing + 远程命令 |
| 离线缓存 | ✅ | 后台 URLSession 下载、断点续传、容量上限、本地优先播放 |
| 手势 / 全屏 | ✅ | 双击 ±10s、上下滑亮度/音量、全屏锁横屏 |
| 网络自检 / 诊断日志 | ✅ | 连通性探测 + 设备码接口自检 + 环形日志（脱敏）导出 |
| 演示播放（无需登录） | ✅ | Apple HLS 样例 + 内嵌字幕：验证播放/字幕/画中画/AirPlay 链路 |
| 隐私清单 / 许可 / 免责声明 | ✅ | `PrivacyInfo.xcprivacy` + 许可页 |
| **画中画 / AirPlay** | ✅ 部分 | MP4/MOV/M4V 走 AVPlayer 内核：原生画中画 + AirPlay 路由；MKV 走 VLCKit 不支持（ADR-018，后续评估桥接/换内核） |
| iPad 分栏 | ✅ | regular 宽度下媒体库两栏（侧栏番剧/继续观看 + 右侧详情/播放） |

---

## 4. 安装（给最终用户）

1. 打开 https://github.com/2744317644/LemonPlayer/releases ，下载最新 `LemonPlayer-unsigned.ipa`
2. 用 Sideloadly / AltStore 以你的 Apple ID 重签并安装
3. 「设置 → 通用 → VPN与设备管理」信任开发者证书
4. 打开 App → 扫码（或浏览器授权页 / Token 直登）→ 进入网盘

免费账号签名 7 天过期，重新自签覆盖安装即可（数据与登录态保留）。详见 `docs/INSTALL.md`。

---

## 5. 已验证 / 待验证

### 已验证（CI + 自动化）
- 7 个纯逻辑包 **75 个单测**（Linux 容器，每次 push）
- macOS 构建 + 未签名 IPA 归档 + Release 发布（rc1~rc8）
- 模拟器 UI 冒烟测试工程已就绪（手动触发 job）

### 待真机验证（需你操作）
- 三通道登录（rc1 曾出现「扫码后网络异常、刷新重扫」循环，rc2 起修复：等待网络 + 轮询重试 + 自动换码；rc3 起增加 Token 直登；rc4 起增加浏览器授权页）
- 直链播放稳定性 / seek / 字幕渲染与样式 / 后台下载续传

---

## 6. 已知限制

| 限制 | 影响 | 缓解 |
|---|---|---|
| 光鸭 API 为社区逆向接口 | 可能随时变更/限流/风控 | 防腐层 + 诊断日志 + WebDAV 预留 |
| 画中画/AirPlay | 不可用 | 记录 ADR；未来换内核或桥接 |
| Bangumi 限流（自律 1 req/s） | 首次扫描慢 | 匹配缓存（30 天），二次扫描快 |
| TMDB 需自备 API Key | 真人影视无兜底海报 | 设置页可填；不填仅用 Bangumi |
| 后台下载依赖系统调度 | 极低电量/强制退出可能暂停 | resumeData 持久化，恢复后续传 |
| IPA 未签名 | 需自签，7 天有效 | INSTALL.md 说明 |

---

## 7. 质量与流程

- 提交规范：Conventional Commits；每轮迭代更新 `docs/PROGRESS.md`
- CI 分层：Linux 单测（~1min）→ macOS 构建/归档（~5min）→ 手动 UI 测试
- 发布：`git tag v*` → `release.yml` 自动构建、校验和、GitHub Release
- 关键决策全部有 ADR（001~017）

---

## 8. 安全与隐私（v1.0.0 审查）

| 项 | 实现 |
|---|---|
| 凭据存储 | Keychain，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（仅本机、解锁后可用） |
| 密码 | 账号密码只在登录请求中使用，**不落盘**；仅保存 token |
| 日志 | 诊断日志仅记录 method/host/path/status/耗时；导出前统一脱敏 Bearer/签名参数；不记录 header/body |
| 网络出口 | 仅光鸭 API、Bangumi、TMDB（可选）、Apple 演示流；无第三方统计/广告 SDK |
| 隐私 | `PrivacyInfo.xcprivacy`（文件时间/磁盘空间/启动时间 API 声明），无数据收集 |
| 仓库 | 无 token/证书/密钥；`.gitignore` 排除本地探测脚本 |

## 9. 后续路线（v1.1+）

1. 真机问题修复 → v1.0.0 正式版
2. 画中画/AirPlay 技术预研（AetherEngine / 自绘渲染 + AVSampleBufferDisplayLayer）
3. iPad 分栏、字幕字体导入、Bangumi 追番进度同步
4. 扫描并发优化（Bangumi Archive 数据）

---

## 10. 免责声明

光鸭云盘未提供公开开发者 API，本项目使用社区逆向接口，存在失效/限流/风控风险；仅用于播放你有权访问的个人媒体内容，请勿传播侵权内容。第三方组件（VLCKit/FFmpeg/libass）按其各自许可分发。
