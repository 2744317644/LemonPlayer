# LemonPlayer 进度日志

> 更新：2026-11-03 21:50 · 维护规则：每次迭代结束必须更新「当前状态」与「日志」；里程碑结束补「复盘」。

---

## 1. 当前状态

| 项目 | 值 |
|---|---|
| 当前里程碑 | **M2 · 登录 + 网盘浏览** |
| 当前阶段目标 | 扫码登录链路已完成编码（设备码 → 二维码 → 轮询 → Keychain），待 CI 验证 |
| 整体进度 | M0 ✅ · M1 ✅ · M2 ▓▓▓░░░░░░░ 30%（登录层完成，目录层未开始） |
| 构建状态 | 🔴 **CI 被阻塞**：GitHub 账号未验证邮箱，`git push` 与 API 提交均 403 |
| 单测覆盖率 | 新增 LemonNetwork / LemonGuangya 单测（设备码解码、轮询结果、异常兜底） |
| 最新产物 | 本地 commit `ff60534`（登录链路）待推送；远程仍停在 `d7fecd3` |
| 下一步 | ① 用户验证邮箱 → 推送 → 修 CI ② 目录列表 API + 浏览页 |
| 阻塞项 | **GitHub 账号 email 验证**（外部阻塞，需用户操作） |

---

## 2. 里程碑进度

| 里程碑 | 主题 | 状态 | 完成度 | 计划完成 |
|---|---|---|---|---|
| M0 | 立项与文档 | ✅ 已完成 | 100% | 2026-11 |
| M1 | 可编译骨架 + CI 出包 | ✅ 已完成 | 100% | 2026-11 |
| M2 | 登录 + 网盘浏览 | 🚧 进行中 | 30% | 2026-12 |
| M3 | 播放内核 + 直链播放 | ⬜ 未开始 | 0% | 2026-12 |
| M4 | 外挂字幕 | ⬜ 未开始 | 0% | 2027-01 |
| M5 | 媒体库 + 剧集 | ⬜ 未开始 | 0% | 2027-01 |
| M6 | 离线缓存 | ⬜ 未开始 | 0% | 2027-02 |
| M7 | 打磨与发布 v1.0 | ⬜ 未开始 | 0% | 2027-02 |

---

## 3. 进度日志

> 一行一条，日期精确到分钟；「产物」列写可点击的仓库路径；CI 列填 Actions run 链接。

| 日期时间 | 阶段 | 内容 | 产物 | 结果 |
|---|---|---|---|---|
| 2026-11-03 21:42 | M0 | 环境侦察：工作区空目录、Windows 无 Xcode/Swift、gh 已登录 GitHub 账号 `2744317644`（含 repo/workflow 权限） | — | ✅ |
| 2026-11-03 21:45 | M0 | 需求对话：确认 iOS 端、官方 API 直连、FFmpeg 系内核、全量字幕+媒体库、GitHub Actions 出包、docs 进度管理 | 对话结论 | ✅ |
| 2026-11-03 21:48 | M0 | 输出需求清单（F/N/C/R/J 编号） | [`docs/REQUIREMENTS.md`](REQUIREMENTS.md) | ✅ |
| 2026-11-03 21:50 | M0 | 输出目标列表与里程碑（M0-M7、G-01~G-10） | [`docs/GOALS.md`](GOALS.md) | ✅ |
| 2026-11-03 21:52 | M0 | 初始化任务看板（60+ 任务卡，M0-M7 全量拆分） | [`docs/TASKS.md`](TASKS.md) | ✅ |
| 2026-11-03 21:54 | M0 | 并行启动两项调研：光鸭 API 逆向、播放内核与 CI 方案 | `docs/api`、`docs/tech` | 🚧 |
| 2026-11-03 21:56 | M0 | 架构设计（分层/8 个 SPM 包/领域模型/四条链路）与 ADR-001~011 | [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)、[`docs/DECISIONS.md`](DECISIONS.md) | ✅ |
| 2026-11-03 22:02 | M0 | 光鸭 API 调研完成：22 接口、直链链路、gcid、错误码、10 项待验证；纠正 client_id 与 API 域名 | [`docs/api/GUANGYA_API.md`](api/GUANGYA_API.md) | ✅ |
| 2026-11-03 22:08 | M0 | 第二轮需求确认：private 仓库、iOS 26.0+、未签名 IPA 自签、Bundle ID `com.lemonplayer.ios`、TMDB 后补、仅自签分发、先用官方 token 联调 | 对话结论 → ADR-012/013 | ✅ |
| 2026-11-03 22:12 | M0 | 评估 swift-ios-skills（86 技能）：质量通过、许可 PolyForm Perimeter；因 DSH 不能热装 + shell 无法直连 GitHub，改为"索引 + 按需 web_fetch" | [`docs/tech/SKILLS.md`](tech/SKILLS.md) | ✅ |
| 2026-11-03 22:20 | M0 | 创建私有仓库并推送成功（gh 账号 2744317644），3 次提交上云 | https://github.com/2744317644/LemonPlayer | ✅ |
| 2026-11-03 22:30 | M0 | 核实 CI 环境：macos-26 镜像预装 **Xcode 26.6（默认）**、iOS 26.5 SDK、CocoaPods 1.17.0 | `docs/tech/CI_BUILD.md` | ✅ |
| 2026-11-03 22:36 | M0 | 播放内核定案：**MobileVLCKit 3.7.5 主选**（libass、LGPL、2026-10-31 发布），MPVKit 备选，AetherEngine 列为观察（Xcode 27 + 不渲染 ASS） | [`docs/tech/PLAYER_KERNEL.md`](tech/PLAYER_KERNEL.md)、ADR-003 | ✅ |
| 2026-11-03 22:40 | M0 | 验证本机代理 `127.0.0.1:7890` 可用（github.com / raw 均 200），写入 Windows 开发说明 | `docs/tech/CI_BUILD.md` §4 | ✅ |
| 2026-11-03 22:45 | M0 | **M0 收口**：文档 9 份齐备、ADR-001~013 定稿、仓库上云 | 全部 `docs/` | ✅ |
| 2026-11-03 22:48 | M1 | 用户提供 token 探针失败：`oidc: malformed jwt`（非 JWT）→ 需扫码登录获取真 token | — | ⚠️ 阻塞真机联调 |
| 2026-11-03 22:50 | M1 | 决策调整：媒体库改为 **Bangumi 优先 + TMDB 兜底**（用户主力动漫），新增 ADR-014 与 F-LIB-10~12、C-07、R-09/R-10、J-05 | `docs/DECISIONS.md`、`docs/REQUIREMENTS.md` | ✅ |
| 2026-11-03 22:52 | M1 | 骨架落地：`project.yml`（XcodeGen）+ 8 个 SPM 包 + 三页占位 UI + `build.yml`，提交 `81b8a62` 推送 | `project.yml`、`Packages/**`、`.github/workflows/build.yml` | ✅ |
| 2026-11-03 22:53 | M1 | Actions 首跑 `41650264063` 触发（macos-26 / Xcode 26.6），后台监控中 | CI | 🚧 |
| 2026-11-03 22:55 | M1 | 并行启动 Bangumi API 接入调研（`docs/api/BANGUMI_API.md`） | — | 🚧 |
| 2026-11-03 22:59 | M1 | **CI 首跑全绿**（run 41650264063，1m16s）：XcodeGen 生成、8 包编译、包内单测、未签名 IPA 归档、artifact 上传 | GitHub Actions | ✅ |
| 2026-11-03 23:02 | M1 | 内核/CI 调研 v0.2 合并（后台 agent 迟到产出：768 行，补充 SwiftVLC、MPVKit 1.1.0 预发布校正、xcode-27 镜像、CocoaPods 缓存策略） | `docs/tech/*.md` | ✅ |
| 2026-11-03 23:05 | M1 | **M1 收口**：构建链闭环，进入 M2 | — | ✅ |
| 2026-11-03 23:15 | M2 | **设备码流程实测通过**：`device/code` 返回 200，字段为 `verification_url`（非 `verification_uri`）、`expires_in=120`、`interval=2`；轮询未扫码返回 HTTP 400 + `authorization_pending` | `docs/api/GUANGYA_API.md` | ✅ |
| 2026-11-03 23:25 | M2 | 登录链路编码完成：LemonNetwork（HTTP 封装）、LemonGuangya（设备码/轮询/刷新/探针）、LemonPersistence（Keychain/TokenStore）、SessionStore、二维码登录页 + 单测 | commit `ff60534`（本地） | 🟡 待 CI |
| 2026-11-03 23:32 | M2 | CI 失败：包默认 macOS 10.13，`URLSession.data(for:)` 需 macOS 12+；已给所有本地包补 `platforms` | commit `ff60534` | ✅ 已修 |
| 2026-11-03 23:36 | M2 | **推送被 GitHub 403 拦截**：`You must verify your email address.`；尝试 API 提交同样 403（`At least one email address must be verified`） | `scripts/push-via-api.ps1` | 🔴 阻塞 |
| 2026-11-03 23:40 | M2 | Bangumi API 调研完成（1380 行）：20 个端点实测、剧集接口实为 `/v0/episodes?subject_id=`、`sort` 跨季续编号、无 PKCE 等结论 | [`docs/api/BANGUMI_API.md`](api/BANGUMI_API.md) | ✅ |
| 2026-11-03 21:54 | M0 | 并行启动两项调研：光鸭 API 逆向、播放内核与 CI 方案 | `docs/api`、`docs/tech` | 🚧 |

---

## 4. 关键指标跟踪（每个里程碑结束更新）

| 指标 | 目标 | 当前值 | 上次测量 |
|---|---|---|---|
| 冷启动耗时 | < 2.0s | — | — |
| 1GB MKV 起播 | < 3.0s | — | — |
| seek 响应 | < 1.5s | — | — |
| 单测覆盖率（纯逻辑） | ≥ 80% | — | — |
| IPA 体积 | < 300MB | — | — |
| CI 成功率 | ≥ 95% | — | — |
| P0 需求完成率 | 100% | 0%（M0 文档阶段） | 2026-11-03 |

---

## 5. 决策与变更记录

| 日期 | 编号 | 内容 | 原因 | 影响 |
|---|---|---|---|---|
| 2026-11-03 | CHG-001 | 项目范围由"通用 Swift 播放器"收敛为"iOS 端直连光鸭云盘" | 用户确认平台与接入方式 | 无需 WebDAV 服务端；API 客户端成为核心模块 |
| 2026-11-03 | CHG-002 | 播放内核从"纯 AVPlayer"改为"FFmpeg 系内核（MPVKit/VLCKit）" | 用户要求支持 MKV 全格式 | 引入二进制依赖；ASS 渲染依赖 libass；体积与许可风险上升 |
| 2026-11-03 | CHG-003 | 构建验证改为 GitHub Actions（macos-26 + Xcode 26） | 开发机为 Windows，无 Xcode | CI 成为唯一编译真相源；小步提交策略 |
| 2026-11-03 | CHG-004 | 发布 v1 不含在线字幕搜索 | 用户未选；合规/稳定性风险 | 字幕来源限定本地 + 网盘文件 |

---

## 6. 里程碑复盘

> 每个里程碑结束时填写：做对了什么 / 做错了什么 / 下次怎么改。

### M0（进行中）
- **做对了**：先固定文档与编号体系，再动手写码；并行调研避免串行等待。
- **待观察**：调研结论是否足以支撑架构文档；仓库托管方式尚未确认。

---

## 7. 下一次会话的入口清单

1. 读 `docs/PROGRESS.md`（本文件）第 1、3 节 → 知道现在在哪。
2. 读 `docs/TASKS.md` 的 Doing / Ready 列 → 知道接下来做什么。
3. 读 `docs/GOALS.md` 当前里程碑的验收标准 → 知道做到什么程度算完成。
4. 读 `docs/DECISIONS.md` → 知道哪些方案已定、不要再讨论。
