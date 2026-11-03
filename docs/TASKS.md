# LemonPlayer 任务看板

> 更新：2026-11-03 · 规则：任务卡以 `T-xxx` 编号，状态流转 `Backlog → Ready → Doing → Review → Done`。
> 每张卡开工前补"写入范围"（workspace 相对路径），避免并行冲突；跨模块改动由 Lead 执行。

## 图例
- 优先级：P0 必须 / P1 应有 / P2 可延后
- 负责：`Lead` / 模块 Agent（`sub:xxx`）/ 验证 Agent

---

## ✅ Done

| 编号 | 任务 | 里程碑 | 优先级 | 负责 | 交付物 |
|---|---|---|---|---|---|
| T-001 | 编写需求清单（F/N/C/R/J 编号体系） | M0 | P0 | Lead | `docs/REQUIREMENTS.md` |
| T-002 | 编写目标列表与里程碑 | M0 | P0 | Lead | `docs/GOALS.md` |
| T-003 | 任务看板建立与维护 | M0 | P0 | Lead | `docs/TASKS.md` |
| T-004 | 进度日志建立（快照 + 日志 + 变更记录） | M0 | P0 | Lead | `docs/PROGRESS.md` |
| T-005 | 光鸭云盘 API 逆向调研（22 接口 + 10 项待验证） | M0 | P0 | sub:api-recon | `docs/api/GUANGYA_API.md` |
| T-011 | Swift/iOS 技能集评估与按需索引（不 vendor） | M0 | P1 | Lead | `docs/tech/SKILLS.md` |
| T-007 | 架构设计文档（分层/SPM 包/领域模型/四条链路） | M0 | P0 | Lead | `docs/ARCHITECTURE.md` |
| T-008 | ADR 决策记录（ADR-001~013） | M0 | P0 | Lead | `docs/DECISIONS.md` |
| T-009 | 仓库初始化（git init / .gitignore / 首次提交） | M0 | P0 | Lead | `.gitignore`、3 个提交 |
| T-010 | 创建私有仓库并推送（2744317644/LemonPlayer） | M0 | P0 | Lead | https://github.com/2744317644/LemonPlayer |
| T-006 | 播放内核与 CI 出包调研（选型定案 + 构建方案） | M0 | P0 | Lead | `docs/tech/PLAYER_KERNEL.md`、`docs/tech/CI_BUILD.md` |
| T-101 | 工程配置：`project.yml`（XcodeGen，iOS 26 + 8 包） | M1 | P0 | Lead | `project.yml` |
| T-102 | SPM 模块骨架（8 个本地 package，可编译） | M1 | P0 | Lead | `Packages/**` |
| T-103 | App 入口 + 三页占位 UI 导航 | M1 | P0 | Lead | `Sources/LemonPlayer/**` |
| T-104 | GitHub Actions `build.yml`：模拟器构建 + 包内单测 | M1 | P0 | Lead | run 41650264063 全绿 |
| T-105 | 未签名 IPA 打包步骤（Payload + zip -X + artifact） | M1 | P0 | Lead | artifact 22KB |
| T-106 | 单测（LemonCore/LemonSubtitle）+ 覆盖率待补 | M1 | P0 | Lead | `Packages/**/Tests/**` |

---

## 🚧 Doing

| 编号 | 任务 | 里程碑 | 优先级 | 负责 | 依赖 | 写入范围 |
|---|---|---|---|---|---|---|
| — | _（M1 收口，M2 任务待认领）_ | — | — | — | — | — |

---

## 🟡 Ready（已就绪，可认领）

| 编号 | 任务 | 里程碑 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|---|
| T-201 | 网络层：URLSession 封装、超时、重试退避、错误映射、日志脱敏 | M2 | P0 | Lead | `Packages/LemonNetwork/**` |
| T-202 | 光鸭 Auth 客户端：设备码申请 / 轮询 / token 刷新 | M2 | P0 | Lead | `Packages/LemonGuangya/Sources/Auth/**` |
| T-203 | 登录页：二维码渲染、倒计时、状态机（等待/成功/过期/失败） | M2 | P0 | Lead | `Sources/LemonPlayer/Features/Login/**` |
| T-204 | Keychain 凭据存储 + TokenStore actor | M2 | P0 | Lead | `Packages/LemonPersistence/**` |
| T-205 | 文件列表 API 客户端（分页/排序/搜索）与模型 | M2 | P0 | T-201 | `Packages/LemonGuangya/Sources/Files/**` |

---

## ⬜ Backlog

### M2 登录 + 网盘浏览
| 编号 | 任务 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|
| T-201 | 网络层：URLSession 封装、超时、重试退避、错误映射、日志脱敏 | P0 | T-102 | `Packages/LemonNetwork/**` |
| T-202 | 光鸭 Auth 客户端：设备码申请 / 轮询 / token 刷新 | P0 | T-201、T-005 | `Packages/LemonGuangya/Sources/Auth/**` |
| T-203 | 登录页：二维码渲染、倒计时、状态机（等待/成功/过期/失败） | P0 | T-202 | `Sources/LemonPlayer/Features/Login/**` |
| T-204 | Keychain 凭据存储 + TokenStore actor（并发刷新只发一次） | P0 | T-202 | `Packages/LemonPersistence/**` |
| T-205 | 文件列表 API 客户端（分页/排序/搜索）与模型 | P0 | T-201 | `Packages/LemonGuangya/Sources/Files/**` |
| T-206 | 浏览页：列表、面包屑、排序、下拉刷新、无限滚动 | P0 | T-205 | `Sources/LemonPlayer/Features/Browse/**` |
| T-207 | 搜索（服务端优先，失败降级本地过滤） | P1 | T-205 | 同上 |
| T-208 | 通用状态组件：加载/空/错误/限流，统一重试 | P0 | T-103 | `Sources/LemonPlayer/Common/**` |
| T-209 | iPad 分栏布局（NavigationSplitView） | P1 | T-206 | `Sources/LemonPlayer/Features/**` |
| T-210 | 单测：登录状态机、分页合并、错误映射 | P0 | T-202~T-206 | `Packages/**/Tests/**` |

### M3 播放内核 + 直链播放
| 编号 | 任务 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|
| T-301 | 内核集成（MobileVLCKit 3.7.5，CocoaPods 静态链接）与资源打包 | P0 | T-102、T-008 | `Packages/LemonPlayback/**`、`project.yml`、`Podfile` |
| T-302 | `PlaybackEngine` 协议 + 内核适配层（轨道枚举/控制/状态回调） | P0 | T-301 | `Packages/LemonPlayback/**` |
| T-303 | 直链获取与续签（预过期刷新、Range seek、403 自动重取） | P0 | T-205 | `Packages/LemonGuangya/Sources/Playback/**` |
| T-304 | 播放器 UI：手势（双击/左右/上下/长按）、控制栏、锁定 | P0 | T-302 | `Sources/LemonPlayer/Features/Player/**` |
| T-305 | 进度条与 seek 体验（缓冲、拖动预览、续播提示） | P0 | T-304 | 同上 |
| T-306 | 倍速 / 音轨 / 内嵌字幕轨切换 | P0 | T-302 | 同上 |
| T-307 | 后台音频（AVAudioSession）+ 锁屏/控制中心（MPRemoteCommandCenter） | P0 | T-302 | `Packages/LemonPlayback/**`、App |
| T-308 | 播放错误恢复：断网重连、签名过期重取、软解回退 | P0 | T-303 | 同上 |
| T-309 | 单测：续签策略、进度模型、内核桥接状态机 | P0 | T-302 | `Packages/LemonPlayback/Tests/**` |

### M4 外挂字幕
| 编号 | 任务 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|
| T-401 | SRT 解析器（容错）+ 单测 | P0 | T-102 | `Packages/LemonSubtitle/Sources/SRT/**` |
| T-402 | WebVTT 解析器 + 单测 | P0 | T-401 | `Packages/LemonSubtitle/Sources/VTT/**` |
| T-403 | ASS/SSA 解析 + 交给内核 libass 的桥接（字体/轨道注入）+ 单测 | P0 | T-301 | `Packages/LemonSubtitle/Sources/ASS/**` |
| T-404 | 同名自动匹配（规范化、语言后缀、多候选、优先级排序）+ 单测 | P0 | T-205 | `Packages/LemonSubtitle/Sources/Matching/**` |
| T-405 | 编码检测（UTF-8/BOM/GBK/GB18030/BIG5/UTF-16）+ 手动覆盖 + 单测 | P0 | T-401 | `Packages/LemonSubtitle/Sources/Encoding/**` |
| T-406 | 时间轴校准模型（±延迟、步进、持久化）+ 单测 | P0 | T-401 | `Packages/LemonSubtitle/Sources/Timeline/**` |
| T-407 | 字幕面板 UI（轨道选择/导入/样式/延迟/预览） | P0 | T-302、T-404 | `Sources/LemonPlayer/Features/Player/Subtitle/**` |
| T-408 | SRT/VTT 自绘 overlay（样式：字号/颜色/描边/背景/边距） | P0 | T-407 | 同上 |
| T-409 | 双语字幕（主/副轨叠加布局） | P1 | T-408 | 同上 |
| T-410 | 按文件记忆（字幕选择/延迟/样式覆盖）持久化 | P0 | T-204 | `Packages/LemonPersistence/**` |
| T-411 | 字幕预览页（静态帧 + 实时样式预览） | P1 | T-407 | 同上 |

### M5 媒体库 + 剧集
| 编号 | 任务 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|
| T-501 | 文件名解析器（标题/年份/季集/多命名规范）+ 单测 | P0 | T-102 | `Packages/LemonMedia/Sources/Parsing/**` |
| T-502 | **Bangumi 客户端**（搜索/详情/剧集/图片；UA + 限流） | P0 | T-201 | `Packages/LemonMedia/Sources/Bangumi/**` |
| T-503 | 刮削编排：解析 → 搜索 → 匹配 → 落库 → 缓存 | P0 | T-501、T-502 | `Packages/LemonMedia/Sources/Scrape/**` |
| T-504 | 首页海报墙（继续观看/最近添加/分类） | P0 | T-503 | `Sources/LemonPlayer/Features/Library/**` |
| T-505 | 详情页 + 季集列表 + 手动纠错 | P1 | T-503 | 同上 |
| T-506 | 剧集自动连播 + 下一集预加载 | P1 | T-504、T-302 | `Features/Player/**` |
| T-507 | 播放历史 | P1 | T-410 | `Packages/LemonPersistence/**` |
| T-508 | 离线可用：海报与元数据磁盘缓存 | P0 | T-503 | `Packages/LemonMedia/**` |
| T-509 | Bangumi OAuth 登录 + 收藏/单集进度同步 | P1 | T-502、T-204 | `Packages/LemonMedia/Sources/Auth/**` |
| T-510 | 每日放送 / 季度番组日历 | P2 | T-502 | `Packages/LemonMedia/Sources/Calendar/**` |

### M6 离线缓存
| 编号 | 任务 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|
| T-601 | 下载任务模型 + 后台 URLSession + 断点续传 | P0 | T-205 | `Packages/LemonDownloads/**` |
| T-602 | 下载状态机（暂停/恢复/取消/失败重试）+ 单测 | P0 | T-601 | 同上 |
| T-603 | 下载管理 UI（列表/进度/速度/批量） | P0 | T-601 | `Features/Downloads/**` |
| T-604 | 缓存管理（容量统计/删除/低空间策略） | P1 | T-601 | `Packages/LemonDownloads/**` |
| T-605 | 离线播放集成（本地文件 + 字幕 + 续播） | P0 | T-603、T-407 | `Features/Player/**` |
| T-606 | 单测：任务状态机、文件校验（大小/分片） | P0 | T-602 | `Packages/LemonDownloads/Tests/**` |

### M7 打磨与发布
| 编号 | 任务 | 优先级 | 依赖 | 写入范围 |
|---|---|---|---|---|
| T-701 | 画中画（PiP）——VLCKit 不支持，v1 置灰/降级，记录 ADR | P2 | T-302、ADR | `Packages/LemonPlayback/**` |
| T-702 | AirPlay——VLCKit 无 AVPlayer 管线，v1 仅音频路由，记录 ADR | P2 | T-301 | 同上 |
| T-703 | 设置页（播放/缓存/网络/外观/关于） | P0 | T-204 | `Features/Settings/**` |
| T-704 | 诊断日志（滚动 + 脱敏 + 导出） | P1 | T-201 | `Packages/LemonCore/**` |
| T-705 | 隐私清单、开源许可页、免责声明 | P0 | — | `Resources/**`、`Features/Settings/**` |
| T-706 | 性能优化（启动/起播/滚动/内存） | P0 | 全部 | 全局 |
| T-707 | 无障碍与动态字体 | P1 | T-703 | `Features/**` |
| T-708 | Release 工作流 + tag 触发 + Release 附 IPA + 安装文档 | P0 | T-104、T-105 | `.github/workflows/**`、`docs/INSTALL.md` |
| T-709 | 回归清单 J-01~J-04 执行记录 | P0 | 全部 | `docs/qa/REGRESSION.md` |

---

## 依赖关系简图

```
M0 文档 ──► M1 骨架+CI ──┬──► M2 登录+浏览 ──► M5 媒体库 ──┐
                          │                                  ├──► M7 发布 v1.0
                          └──► M3 播放内核 ──► M4 字幕 ─────┤
                                              └──► M6 离线缓存 ┘
```

## 更新记录
| 日期 | 变更 |
|---|---|
| 2026-11-03 | 初始化看板，拆出 M0~M7 共 60+ 任务卡 |
