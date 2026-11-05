# 代码 Review（v1.0.3 前，2026-11-06）

> 范围：网络层、光鸭 API 客户端、播放器、字幕、下载、媒体库、登录 UI。
> 方法：静态审查 + 真实接口实测（用户提供 token）+ CI/模拟器验证。
> 结论：**发现并修复 6 个会导致功能失败的问题**；其余为已记录的 P2/风险。

## 一、本次修复（真正影响可用性的）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| 1 | `GuangyaFileService` | 文件接口用旧路径 `nd.bizuserres.s/v1/...`，服务端返回非 JSON → 「接口错误(-1) 响应解析失败」 | 改为官方网页在用的 `/userres/v1/file/get_file_list` 与 `/userres/v1/get_res_download_url` |
| 2 | `GuangyaFileService` / `PlaybackLink` | 成功响应**没有 `code` 字段**，解析器把 `code` 当必填 | `code: Int?`，缺省视为 0；新增真实响应单测 |
| 3 | `GuangyaFileService.webReferer` / `PlaybackLink.playbackHeaders` | Referer 写成 `www.guangyupan.com`（错误域名） | 改为 `https://www.guangyapan.com/`；CDN Range 实测 206 |
| 4 | `listAllVideos` | `parentId:"*" + fileTypes:[2]` 返回的是目录，媒体库会拿目录当视频 | 增加 `resType:1` 聚合；为空时递归遍历兜底（限 600 目录 / 5000 视频） |
| 5 | `WebLoginView` | 登录页 URL 用 `/login`（实际是营销首页），且 Timer 在 Swift 6 deinit 报错 | 改为真实路由 `/oauth/login`；`nonisolated(unsafe)` 标注 |
| 6 | 登录页 | 授权页域名/路径错误 + 入口过多 | 精简为 扫码 / 网页登录 / 账号密码；二维码点击刷新；授权页兜底域名修正 |

## 二、真实接口实测（用户 token，2026-11-05）

| 接口 | 结果 |
|---|---|
| 根目录列表 | 200，`data.total=4`（番剧/Live/云添加/TOKEN订阅） |
| 子目录列表 | 200，`total=43` |
| `get_res_download_url` | 200，`data.signedURL`（guangyacdn） |
| CDN Range GET | **206**，内容可读 |

## 三、审查通过的部分

- `HTTPClient`：4xx 不短路（轮询依赖 body）；`waitsForConnectivity`；诊断日志不含 header/body
- `SessionStore`：single-flight refresh、Keychain 失败内存兜底、登录态恢复
- `SubtitleTextDecoder`：BOM → UTF-8 → GB18030 → BIG5 → Latin-1 → 宽松 UTF-8
- `PlayerViewModel`：本地优先、直链失效自动重取并 seek 回原位、字幕 overlay/kernel 双通道
- `DownloadManager`：background session + resumeData 持久化 + 容量上限
- `AVPlayerEngine`：PiP/AirPlay 仅在 AVPlayer 内核启用，`supportsNativeASS=false` 时 ASS 走 overlay

## 四、剩余风险 / P2（已记录，不阻塞 v1.0.3）

1. **账号密码 API 登录**受 `x-captcha-token` 风控限制，推荐网页登录（已验证可用）
2. **MKV 的 PiP/AirPlay** 仍不支持（VLCKit 无 AVPlayer 管线，ADR-020）
3. 媒体库递归兜底最多 600 目录/5000 视频，超大账号可能截断（后续换聚合接口/后台索引）
4. 后台下载被系统强制终止后，resumeData 可用性依赖 iOS 版本（已做持久化 + 失败提示）
5. Bangumi 限流 1 req/s，首次扫描慢（已有 30 天匹配缓存）

## 五、验证

- `swift test`：7 包 **89 个用例**（LemonGuangya 24，含真实响应形状）
- CI（public 仓库免费 runner）：build/archive/Release 流水线
- 模拟器 UI：登录页/账号页/网页登录页截图在 `docs/screenshots/ui/`
