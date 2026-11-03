# Bangumi 番组计划 API 接入文档（LemonPlayer）

> 面向 **LemonPlayer（Swift / SwiftUI 原生 iOS 播放器，挂载光鸭云盘、以动漫为主）** 的可落地实现说明。
>
> 本文所有接口结论都标注来源：**【实测】** = 2026-11-03 用真实 HTTP 请求打到 `api.bgm.tv` 验证过（含状态码与响应片段）；**【文档】** = 来自 Bangumi 官方 OpenAPI/文档仓库；**【待验证】** = 无法在不登录、不注册 OAuth 应用的前提下证实，禁止直接依赖。
>
> 文档数据核对时间：**2026-11-03**。核对方式：Windows + PowerShell/.NET `HttpClient` 直连 `api.bgm.tv`（UA 与 iOS 客户端一致），文档来自 `bangumi/api` 与 `bangumi/server` 仓库 master 分支。
>
> 一句话结论：**「海报墙 + 番剧详情 + 剧集列表 + 进度记录」这四件事，Bangumi 一家能全部覆盖**（前三项纯公开接口即可，第四项需要 OAuth 登录）。但 Bangumi **没有** TMDB 那样的「按文件名/集合/季」编排能力，剧集匹配必须自己做（见 §6），这是本项目最大的工作量与最大风险来源。

---

## 0. 文档说明

### 0.1 来源清单

| 编号 | 来源 | 用途 |
|---|---|---|
| S1 | [bangumi/api · open-api/v0.yaml](https://github.com/bangumi/api/blob/master/open-api/v0.yaml)（[raw](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)） | **v0 接口权威 schema**（由 S2 同步而来） |
| S2 | [bangumi/server · openapi/v0.yaml](https://github.com/bangumi/server/blob/master/openapi/v0.yaml) | v0 schema 的上游仓库；[渲染页](https://bangumi.github.io/api/) |
| S3 | [bangumi/api · open-api/api.yml](https://raw.githubusercontent.com/bangumi/api/master/open-api/api.yml) | **旧版 API schema**（当前只登记了 `/calendar`），含 `Legacy_Subject*` 字段 |
| S4 | [docs-raw/user agent.md](https://github.com/bangumi/api/blob/master/docs-raw/user%20agent.md) | **User-Agent 强制规范** |
| S5 | [docs-raw/How-to-Auth.md](https://github.com/bangumi/api/blob/master/docs-raw/How-to-Auth.md) | **OAuth2 授权码流程、token 刷新、token_status** |
| S6 | [docs-raw/Search-API.md](https://github.com/bangumi/api/blob/master/docs-raw/Search-API.md) | 旧版搜索 `GET /search/subject/{keywords}` |
| S7 | [bangumi/dev-docs · 图片.md](https://github.com/bangumi/dev-docs/blob/master/%E5%9B%BE%E7%89%87.md) | 图片 URL 前缀规则、尺寸枚举 |
| S8 | [bangumi/dev-docs · 条目.md](https://github.com/bangumi/dev-docs/blob/master/%E6%9D%A1%E7%9B%AE.md) | 条目/章节表结构（字段真实含义） |
| S9 | [bangumi/dev-docs · 用户收藏.md](https://github.com/bangumi/dev-docs/blob/master/%E7%94%A8%E6%88%B7%E6%94%B6%E8%97%8F.md) | 收藏/章节进度底层结构 |
| S10 | [bangumi/Archive](https://github.com/bangumi/Archive) | **每周三全量 wiki 数据导出**（官方指定给"不需求实时"的场景） |
| S11 | [bangumi/server · pkg/vars/platform.go.json](https://github.com/bangumi/server/blob/master/pkg/vars/platform.go.json) | `platform` 取值全表（TV/OVA/剧场版/WEB/日剧…） |
| S12 | [subject_collection_type.yaml](https://github.com/bangumi/server/blob/master/openapi/components/subject_collection_type.yaml) | 收藏类型 1–5 枚举 |
| S13 | [episode_collection_type.yaml](https://github.com/bangumi/server/blob/master/openapi/components/episode_collection_type.yaml) | 单集收藏类型 0–3 枚举 |
| S14 | [bangumi/api issue #206](https://github.com/bangumi/api/issues/206) | 官方对"批量抓取/UA 被封"的回应 |
| S15 | [bangumi/api issue #231](https://github.com/bangumi/api/issues/231) | `/v0/me` 未授权实际返回 **401**（文档曾写 403） |
| S16 | [TMDB FAQ](https://developer.themoviedb.org/docs/faq) | 署名要求、商用授权 |
| S17 | [TMDB Rate Limiting](https://developer.themoviedb.org/docs/rate-limiting) | TMDB 限流现状（~40 req/s） |
| S18 | [TMDB Image Basics](https://developer.themoviedb.org/docs/image-basics) | `image.tmdb.org/t/p/{size}` 拼法 |
| S19 | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | 5.2 知识产权、内容版权责任 |

### 0.2 实测记录（R1–R22）

全部请求携带 `User-Agent: LemonPlayer/0.1.0 (iOS; https://github.com/lemonplayer/lemonplayer)`，未携带 `Authorization`。

| 编号 | 请求 | 结果 |
|---|---|---|
| R1 | `GET /v0/subjects/12` | 200，3 512 B，见 §5.1 |
| R2 | `GET /v0/episodes?subject_id=12&type=0&limit=3` | 200，`{data,total:24,limit:3,offset:0}` |
| R3 | `GET /v0/episodes?subject_id=12&limit=1`（全部 type） | 200，`total=27`；`type=1` 时 `total=3` |
| R4 | `GET /v0/episodes?subject_id=253&limit=1` / `type=0` / `type=1` / `type=2` | `total=31` / `26` / `1` / `1` |
| R5 | `GET /v0/episodes?subject_id=411427&type=0&limit=1` | `total=12`，首集 `ep=1`、`sort=26` |
| R6 | `POST /v0/search/subjects`（keyword=`间谍过家家`） | 200，`total=27`，前 5 条含 2 季/第2部分/第3季/剧场版 |
| R7 | `POST /v0/search/subjects`（`air_date:[">=2022-04-01","<2022-07-01"]`） | 200，`total=1`（精确命中第 1 季） |
| R8 | `POST /v0/search/subjects`（keyword=`[Nekomoe kissaten] Sousou no Frieren [01][1080p][CHS]`） | 200，**`total=0`**（原始文件名搜不到） |
| R9 | `POST /v0/search/subjects`（keyword=`""`） | 200，`total=1000`（空关键词 = 全库前 1000） |
| R10 | `GET /calendar` | 200，7 个 weekday，`items` 为旧版 subject（图片为 `http://`） |
| R11 | `GET /v0/calendar` | **404**（不存在该路径） |
| R12 | `GET /v0/subjects/12/episodes` | **404**（剧集不是子资源，必须用 `/v0/episodes`） |
| R13 | `GET /search/subject/chobits?type=2&responseGroup=small&max_results=2` | 200，`{results:2,list:[…]}`；`air_date` 为 `""`、图片 `http://` |
| R14 | `GET /v0/subjects/12/subjects` | 200，数组，`relation` 为中文（`片尾曲`/`书籍`） |
| R15 | `GET /v0/subjects/12/persons` | 200，**123 条**，33 588 B |
| R16 | `GET /v0/subjects/12/characters` | 200，24 974 B |
| R17 | `GET /v0/me`（无 token） | **401** `{"title":"Unauthorized",…,"description":"need Login"}` |
| R18 | `GET /v0/subjects/99999999` | **404** `{"title":"Not Found",…,"description":"resource can't be found in the database or has been removed"}` |
| R19 | 40 个并发 `GET /v0/episodes?...` | **40 × 200**，未触发 429 |
| R20 | 空 UA / `Bangumi/1.0` / `okhttp/4.9.0` 请求 `GET /v0/subjects/12` | 均 200（详见 §2.3） |
| R21 | `GET /bgm.tv/oauth/access_token` | **405** `{"error":"invalid_request","error_description":"The request method must be POST when requesting an access token",…}` |
| R22 | `GET https://bgm.tv/oauth/authorize`（不带参数/带假 client_id） | 200 HTML → 跳登录页 |

---

## 1. 结论速览（TL;DR）

### 1.1 四项能力是否只靠 Bangumi 就能做

| 能力 | 只用 Bangumi 可行？ | 依据 | 缺口 |
|---|---|---|---|
| 海报墙 | ✅ | `POST /v0/search/subjects`、`GET /calendar`、`GET /v0/subjects?type=2`、登录后 `GET /v0/users/{username}/collections` 都能拿到 `images.grid/small` 完整 URL【实测 R1/R6/R10】 | 不含"我的本地文件"，海报墙必须有本地媒体库表 |
| 番剧详情 | ✅ | `GET /v0/subjects/{id}` 一次返回中文名、简介、评分、排名、标签、放送日、平台、封面【实测 R1】 | 简体中文简介覆盖率高但非 100%，少数条目 `summary` 为空 |
| 剧集列表 | ✅ | `GET /v0/episodes?subject_id=`，带 `ep/sort/name/name_cn/airdate/duration`【实测 R2】 | 数量与 `subject.eps` 常常对不上（见 §5.2 陷阱），必须按 `type=0` 实数 |
| 进度记录 | ✅ 但需登录 | `PATCH /v0/users/-/collections/{subject_id}/episodes`（批量）+ `PUT /v0/users/-/collections/-/episodes/{episode_id}`【文档 S1】 | 必须 OAuth2；且是**同步到 Bangumi 账号**，不想登录就只能纯本地存 |

### 1.2 推荐路线（明确结论）

**v1：只做 Bangumi 公开接口 + 本地进度（不接 OAuth）。**
理由：公开接口已覆盖"海报墙 + 详情 + 剧集"，实测无需任何 token（R1–R16 全部 200）。进度先存本地 `SwiftData`，避免在 v1 就背上 OAuth、`client_secret` 内置的安全负担和 token 刷新逻辑。

**v1.5：接 OAuth，把进度双向同步到 Bangumi。** 这一步的用户价值最高（用户本来就在 bgm.tv 记进度），但必须先解决 `client_secret` 无法安全内置的问题（见 §4.1.4）。

**不要做「只做 TMDB」**：用户主力看动漫，TMDB 的日文/中文番剧名、分集标题、放送日历、单集进度全线弱于 Bangumi。

**TMDB 兜底：建议做，但排在最后（v2），且只扮演"兜底"角色**，不要做成双写双读。推荐形态是：`type=6（三次元）` 或 Bangumi 搜索 `total=0` 时才查 TMDB。

> 结论一句话：**Bangumi 优先 + TMDB 兜底**，但 v1 只落 Bangumi，TMDB 不进 v1 关键路径。

---

## 2. API 基础

### 2.1 域名与 Base URL

| 用途 | Base URL | 说明 | 来源 |
|---|---|---|---|
| 数据 API | `https://api.bgm.tv` | v0 与旧版共用同一 host，v0 带 `/v0` 前缀 | 【实测】R1–R19；[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml) |
| OAuth 授权 / token | `https://bgm.tv` | **注意与数据 API 不同域** | [S5](https://github.com/bangumi/api/blob/master/docs-raw/How-to-Auth.md)；【实测】R21/R22 |
| 图片 CDN | `https://lain.bgm.tv` | v0 直接返回完整 URL | 【实测】R1；[S7](https://github.com/bangumi/dev-docs/blob/master/%E5%9B%BE%E7%89%87.md) |
| 新版前端 / 拿测试 token | `https://next.bgm.tv/demo/access-token` | 页面需登录，可自助生成 Access Token 做联调 | [S1 顶部 description](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)；【实测】返回 200 登录页 |
| 开发者平台（注册应用） | `https://bgm.tv/dev/app` | 申请 `client_id` / `client_secret`，配置回调地址 | 【实测】`https://bgm.tv/dev` 返回 200「Bangumi 开发者平台」 |

### 2.2 v0 API 与旧版 API 的区别

Bangumi 同时存在两代 API，**同一 host、不同前缀**：

| 维度 | v0（`/v0/...`） | 旧版（无前缀） |
|---|---|---|
| 文档形态 | OpenAPI 自动生成，有 [渲染页](https://bangumi.github.io/api/) | 手写 md（`docs-raw/`）+ 仅 `/calendar` 进了 OpenAPI（[S3](https://raw.githubusercontent.com/bangumi/api/master/open-api/api.yml)） |
| 条目详情 | `GET /v0/subjects/{id}`，字段 `date` / `eps` / `total_episodes` / `infobox` | `GET /subject/{id}?responseGroup=small|medium|large`，字段 `air_date` / `eps_count` / `air_weekday` / `crt` / `staff` |
| 剧集列表 | **独立接口** `GET /v0/episodes?subject_id=`【实测 R2】 | 内嵌在 `responseGroup=large` 的 `eps[]` 里 |
| 搜索 | `POST /v0/search/subjects`（JSON body，meilisearch） | `GET /search/subject/{keywords}?type=&responseGroup=&max_results=`（[S6](https://github.com/bangumi/api/blob/master/docs-raw/Search-API.md)） |
| 图片 | 返回**完整 https URL**，多档 `r/{px}` 变体【实测 R1】 | 返回 **`http://`** URL，且需按 `/pic/cover/{l|m|s|c|g}/` 拼（[S7](https://github.com/bangumi/dev-docs/blob/master/%E5%9B%BE%E7%89%87.md)）；iOS ATS 会拦 |
| 每日放送 | **没有**（`/v0/calendar` → 404【实测 R11】） | `GET /calendar`【实测 R10】 |
| Token 传递 | 只认 `Authorization: Bearer`（**不允许 query string**） | 历史上可用 query token（[S5](https://github.com/bangumi/api/blob/master/docs-raw/How-to-Auth.md)） |
| 稳定性 | 搜索接口文档自标「实验性，schema 与行为可能随时改动」 | 冻结多年的老实现 |

**LemonPlayer 策略：一律用 v0；只有"每日放送 /calendar"不得不回退旧版**（见 §3.7）。旧版 `/search/subject/` 与 `/subject/{id}` 不建议使用——返回的 `http://` 图片和空 `air_date`（实测 R13）会额外引入 ATS 与数据清洗问题。

### 2.3 User-Agent：强制要求，但不是"空 UA 立刻 403"

**官方规定（必须遵守）**【[S4](https://github.com/bangumi/api/blob/master/docs-raw/user%20agent.md)】：

- 非浏览器调用者必须带**可识别的** UA，包含**开发者个人 ID** 与**应用名称**；分发的客户端还要带**版本号**；开源项目附项目主页。
- 明确点名禁用形如 `database`、`Bangumi/1.0`、`Bangumi/1.3.13.0` 的 UA（只写产品名 + 版本，无法定位到人）。
- 原文："各种请求库的默认 UA 可能会被禁用。"

**实测（R20）**：空 UA、`Bangumi/1.0`、`okhttp/4.9.0` 三种情况当前**都返回 200**。
说明拦截**不是**"UA 为空就 403"的简单判定，更可能是 Cloudflare 按 IP/频率/指纹做的平台级封禁。

**但社区有真实的封禁案例**：有人以 5–10 秒/次的节奏循环抓了约 6 500 条，跑了十小时，之后**同一 UA 被 ban**，表现为 `connect ETIMEDOUT`（浏览器正常、后端程序超时）【[S14 issue #206](https://github.com/bangumi/api/issues/206)】。

**结论（写给实现）**：

```swift
// 推荐格式：应用名/版本号 (平台; 项目主页)
static let userAgent = "LemonPlayer/1.0.0 (iOS; https://github.com/<owner>/LemonPlayer)"
```

- UA **必须**在每一次请求（含图片请求）上带，且**不要随版本随机变化**——一旦被封，换 UA 也不一定能解封。
- 不要用 `.default`（`CFNetwork/… Darwin/…`）——那正是文档说"可能被禁用"的默认 UA。
- 官方提供了**更优解**：`bangumi/Archive` 每周三 05:00 (GMT+8) 导出全量 wiki 数据，明确目的是"方便不需要实时数据的场景，顺便减少爬虫"【[S10](https://github.com/bangumi/Archive)】。需要本地索引/离线搜索时**先考虑下载归档**，不要全量扫 API。

### 2.4 是否需要 OAuth

| 场景 | 需要 token？ | 依据 |
|---|---|---|
| 条目详情、剧集列表、搜索、日历、关联条目、人物、角色、图片 | ❌ 不需要 | 【实测】R1–R16 全部无 token 200 |
| 查看用户公开收藏 | ❌ 不需要（`sai` 的收藏实测 200） | 【实测】R1 之外：`GET /v0/users/sai/collections?subject_type=2&type=3&limit=3` → 200 |
| 查看**私有**收藏 | ✅ 需要 | [S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)（"查看私有收藏需要 access token"） |
| 任何写入（收藏、评分、进度） | ✅ 需要 | [S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml) `security: HTTPBearer: [write:collection]` |
| **R18/NSFW 条目** | ✅ 需要（否则被当不存在） | [S3 securitySchemes](https://raw.githubusercontent.com/bangumi/api/master/open-api/api.yml)：未授权用户请求 NSFW 条目会得到 **404** |

> `POST /v0/search/subjects` 的 `filter.nsfw` 在无权限时会被**直接忽略**，不会返回 R18 条目（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)）。这对"用户主力看正常番剧"的 LemonPlayer 是好事：**默认不传 `nsfw` 也能得到干净结果**。

### 2.5 速率限制：没有公开数值，只能自律

| 结论 | 证据 |
|---|---|
| **官方没有公布数值型限流**，文档里查不到 QPS/每日配额 | `docs-raw/` 三篇文档均无限流章节；v0/api.yml schema 无限流说明 |
| 实测 **40 并发** 全部 200，**无 429、无 `X-RateLimit-*`、无 `Retry-After`** | 【实测 R19】 |
| 但存在**UA 级封禁**（表现为连接超时），且官方对"如何避免"的回答是：**用每周归档，别爬** | [S14](https://github.com/bangumi/api/issues/206) |
| 服务端有缓存策略，善用可显著降低请求数 | `GET /v0/subjects/{id}` "cache with 300s"；`GET /v0/subjects` 列表"第一页 cache 24h，之后 1h"（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)） |

**LemonPlayer 自律规则（写死进代码）**：

1. **全局 ≥1 请求/秒**（即 ≤60 req/min）。这是社区长期经验值，也是本文建议的硬上限。
2. 单域名 `httpMaximumConnectionsPerHost = 2`。
3. 429 / 5xx / 超时：指数退避（1s→2s→4s，最多 3 次），并优先读 `Retry-After`（如果将来出现）。
4. **一切 GET 结果本地落盘**（§10.3 给了 TTL 表），海报墙滚动/详情二次进入**不发请求**。
5. 批量场景（首次建库、全量扫描）→ **不要循环打 API**，改用 `bangumi/Archive` 的 release 数据【S10】。

### 2.6 错误响应统一形状

所有 v0 错误都是同一个 `ErrorDetail` 结构（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)），实测两种：

```json
// 401（R17，注意文档写的是 403，实际是 401，见 issue #231）
{"title":"Unauthorized","details":{"path":"/v0/me","method":"GET"},"request_id":"a54bf093cefdd496-LHR","description":"need Login"}

// 404（R18）
{"title":"Not Found","details":{"path":"/v0/subjects/99999999","method":"GET"},"request_id":"a54bf4fbbb72fd4e-LHR","description":"resource can't be found in the database or has been removed"}
```

| 状态码 | 含义 | 客户端处理 |
|---|---|---|
| 400 | 参数校验失败（`limit` 超上限、`type` 非法等） | 修参数，不要重试 |
| 401 | 无 token / token 失效 | 触发刷新，刷新失败则登出（**不是 403**，见 [S15](https://github.com/bangumi/api/issues/231)） |
| 403 | Cloudflare 拦截 / UA 被封 | **不要重试**；提示"服务不可用"，此时换 UA 无用 |
| 404 | 条目/用户不存在；**或 NSFW 条目对未授权用户伪装成 404** | 区分：带 token 再试一次，仍 404 才是真不存在 |
| 405 | 方法错（如 `GET /oauth/access_token`） | 【实测 R21】 |
| 429 | 被限流 | 退避后重试，并降低全局速率 |
| 5xx | 服务端故障 | 指数退避重试 |

`request_id` 一定要落日志（bangumi 官方 issue 要求带上它排查）。

---

## 3. 公开接口（无需登录）

### 3.0 总表

| # | 接口 | 方法 | 用途 | 实测 |
|---|---|---|---|---|
| A | `/v0/search/subjects` | POST | 关键词搜索条目（主力） | ✅ R6–R9 |
| B | `/v0/subjects/{id}` | GET | 条目详情 | ✅ R1 |
| C | `/v0/episodes?subject_id=` | GET | 剧集列表（**不是** `/v0/subjects/{id}/episodes`） | ✅ R2–R5 |
| D | `/v0/episodes/{episode_id}` | GET | 单集详情 | ✅ |
| E | `/v0/subjects/{id}/subjects` | GET | 关联条目（续作/前作/剧场版/原作） | ✅ R14 |
| F | `/v0/subjects/{id}/persons` | GET | 制作人员 | ✅ R15 |
| G | `/v0/subjects/{id}/characters` | GET | 角色 + 声优 | ✅ R16 |
| H | `/calendar`（旧版） | GET | 每日放送 | ✅ R10 |
| I | `/v0/subjects?type=&sort=&year=` | GET | 浏览/排行榜 | ✅ |
| J | `/v0/subjects/{id}/image?type=` | GET | 跳转/直接返回图片 | ✅ |
| K | `/v0/users/{username}/collections` | GET | 用户收藏（公开可读） | ✅ |
| L | `/search/subject/{keywords}`（旧版） | GET | 旧搜索（**不推荐**） | ✅ R13 |

**分页默认值（很容易踩坑，务必记）**【[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml) `parameters:`】：

- 通用 `limit`：默认 **30**，最大 **50**，`offset` 默认 0。
- `/v0/episodes` 的 `limit`：默认 **100**，最大 **200**。
- `/v0/users/-/collections/{id}/episodes` 的 `limit`：最大 **1000**。

### 3.1 `POST /v0/search/subjects`（主力搜索）

```http
POST https://api.bgm.tv/v0/search/subjects?limit=5&offset=0
Content-Type: application/json
User-Agent: LemonPlayer/1.0.0 (iOS; https://github.com/<owner>/LemonPlayer)

{
  "keyword": "间谍过家家",
  "sort": "match",
  "filter": {
    "type": [2],
    "nsfw": false,
    "air_date": [">=2022-04-01", "<2022-07-01"]
  }
}
```

- `sort`：`match`（相关度，默认）/ `heat`（收藏人数）/ `rank` / `score`。
- `filter.type`：数组，多值之间是**或**；`2` = 动画（见 §5.5）。
- `filter.nsfw`：`false` 只回非 R18；无权限用户此字段被忽略。
- `filter.air_date` / `rating` / `rank` / `rating_count`：字符串表达式数组，如 `">=6"`、`"<8"`、`">10"`。

**实测返回**（`limit=5`，返回体 23 206 B，`total=27`）：

| id | date | platform | name | name_cn |
|---|---|---|---|---|
| 329906 | 2022-04-09 | TV | SPY×FAMILY | 间谍过家家 |
| 373267 | 2022-10-01 | TV | SPY×FAMILY 第2クール | 间谍过家家 第2部分 |
| 411427 | 2023-10-07 | TV | SPY×FAMILY Season 2 | 间谍过家家 第二季 |
| 498378 | 2025-10-04 | TV | SPY×FAMILY Season 3 | 间谍过家家 第三季 |
| 411428 | 2023-12-22 | 剧场版 | 劇場版 SPY×FAMILY CODE: White | 剧场版 间谍过家家 代号：白 |

关键行为（都直接影响 §6 的算法）：

1. **结果里是完整 `Subject` 对象**（含 `infobox`、`tags`、`rating`），单条约 4.5 KB。`limit` 不要开大。
2. **关键词里带季号会显著改善排序**：搜 `"间谍过家家"` 第一条是第 1 季；搜 `"间谍过家家 第二季"` 第一条就是 `411427`（实测 R6 对比）。所以**先拼季号再搜**比"搜完再排序"更省事。
3. **`air_date` 过滤是消歧最强武器**：加 `[">=2022-04-01","<2022-07-01"]` 后 `total` 从 27 直接降到 **1**（R7）。
4. **空关键词返回 `total=1000`**（R9）——必须在前置校验里拦掉空 `keyword`，否则白拿 1000 条、浪费配额。
5. **原始文件名搜不到**：`"[Nekomoe kissaten] Sousou no Frieren [01][1080p][CHS]"` → `total=0`（R8）。**归一化是刚需**，不是优化项。
6. 文档自标「实验性 API，schema 与行为可能随时改动」——**必须在客户端做解码容错**（见 §7.2）。

### 3.2 旧版搜索（不推荐，仅作对照）

```http
GET https://api.bgm.tv/search/subject/chobits?type=2&responseGroup=small&max_results=2&start=0
```

实测返回 `{"results":2,"list":[…]}`，但：

- `air_date` 是 **空字符串**（`responseGroup=small` 时不给），`summary` 也是空；
- 图片是 **`http://lain.bgm.tv/pic/cover/l/…`**（无 `r/{px}` 变体）——iOS ATS 直接拦截，必须改写成 `https://`；
- `type` 为可选的**单个**整数，不能多值。

结论：**v0 搜索 + `limit=1` 已经够用，不需要旧版搜索。**

### 3.3 `GET /v0/subjects/{id}`（条目详情）

实测 R1（`/v0/subjects/12`，3 512 B）字段全集：

```
id, type, name, name_cn, summary, date, platform, images{large,common,medium,small,grid},
infobox[], tags[], rating{rank,total,count{1..10},score}, collection{wish,collect,doing,on_hold,dropped},
eps, total_episodes, volumes, series, locked, nsfw, meta_tags[]
```

- `date`：放送/发售日期，`YYYY-MM-DD`（文档写 `air date in YYYY-MM-DD format`）。**实测存在 `null`（`/v0/subjects/2`）与 `""`（搜索结果 `id=198753`）两种"没有日期"**，必须用 `String?`。
- `eps`：维基人填的"话数"；`total_episodes`：**数据库里该条目的章节总数（含 SP/OP/ED）**。二者都可能与真正的本篇集数不符 → 见 §5.2。
- `rating.score`：`number`（可能是 `7.5` 或 `null`，无评分时 `rank=0`）。
- `collection`：五项人数，可用于"热度"排序。
- `infobox`：`[{key, value}]`，`value` 可能是 `String`，也可能是 `[{k,v}]` 数组；**别名（中文名/别名/英文名/日文名）都在这里**，是匹配算法的重要素材（实测 12 号条目 `infobox` 有 29 项，第一项 `key=中文名`）。
- `locked` / `nsfw`：布尔。

服务端缓存 300s（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)），可以放心短时重复读。

### 3.4 剧集列表

> ⚠️ **最容易写错的一处**：剧集**不是**条目的子资源。
> `GET /v0/subjects/{id}/episodes` → **404**（实测 R12）。
> 正确写法：`GET /v0/episodes?subject_id={id}`。

```http
GET https://api.bgm.tv/v0/episodes?subject_id=12&type=0&limit=200&offset=0
```

参数：`subject_id`（必填）、`type`（`EpType`，见 §5.5）、`limit`（默认 100，最大 200）、`offset`。

实测返回（2385 B）：

```json
{"data":[{"airdate":"2002-04-03","name":"ちぃ 目覚める","name_cn":"叽，觉醒了",
          "duration":"24m","desc":"脚本：大川七瀬…","ep":1,"sort":1,
          "id":1027,"subject_id":12,"comment":36,"type":0,"disc":0,
          "duration_seconds":1440}, …],
 "total":24,"limit":3,"offset":0}
```

- 有 `total/limit/offset`（与 `Subject` 详情不同），**分页信息可靠**。
- `duration` 是字符串（`"24m"`）；`duration_seconds` 是服务端解析后的整数（解析不了为 `0`）——播放器做"总时长估算"用后者。
- `ep`：本篇内序号，**从 1 开始，非本篇（SP/OP）为 0 或无此字段**。
- `sort`：**`number`（可为小数）**，实测 SP 有 `sort=8.5`。
- `desc`：简介，含 `\r\n` 与 `\t`，长度可观。

### 3.5 关联条目 `GET /v0/subjects/{id}/subjects`

实测 R14：直接返回**数组**（不分页），元素字段 `{images, name, name_cn, relation, type, id}`。

`relation` 是**中文字符串**（不是枚举数字）：`片尾曲`、`书籍`、`续集`、`前传`、`剧场版`、`角色出演` 等。

用途：
- 详情页"相关系列"横滑；
- **季号链**：`续集`/`前传` 可以串出整个系列，用来校正"第几季"（比只靠标题关键词可靠）。
- 结果里会混入音乐（`type=3`）、书籍（`type=1`），UI 上要过滤或分组。

### 3.6 人物与角色

```http
GET /v0/subjects/12/persons      # 实测 123 条 / 33 588 B
GET /v0/subjects/12/characters   # 实测 24 974 B
```

- `persons[]` 字段：`{images, name, relation, career, type, id, eps}`。`relation` 是**职位中文名**（实测：`录音`、`补间动画`）。`eps` 是"参与章节"，实测多为空字符串。
- `characters[]` 字段：`{images, name, summary, relation, type, id, actors[]}`，`actors` 内含声优 `Person`。
- 两者都**没有分页参数**，一次全量返回。`persons` 动辄上百条 → **详情页首屏不要请求**，折叠展开时再懒加载；或者干脆不做（播放器场景价值低，角色+声优价值更高）。

### 3.7 每日放送 `GET /calendar`（唯一的旧版依赖）

```http
GET https://api.bgm.tv/calendar
```

- **`/v0/calendar` 不存在**（实测 R11 → 404）。
- 返回**数组 7 个元素**（周一…周日），元素为：

```json
{"weekday":{"en":"Mon","cn":"星期一","ja":"月耀日","id":1},
 "items":[{"id":390200,"url":"http://bgm.tv/subject/390200","type":2,
           "name":"…","name_cn":"…","summary":"","air_date":"2026-10-05","air_weekday":1,
           "rating":{"total":8,"count":{…},"score":3.6},
           "images":{"large":"http://lain.bgm.tv/pic/cover/l/…","common":"…","medium":"…","small":"…","grid":"…"},
           "collection":{"doing":1}}]}
```

坑：

1. `items` 是 `Legacy_SubjectSmall`，**图片全为 `http://`** → 必须在解码后统一改写成 `https://`，否则 ATS 拦。
2. `summary` 实测为空字符串；`eps` / `eps_count` 字段**当前不存在于 items**（实测 keys 只有 `id,url,type,name,name_cn,summary,air_date,air_weekday,rating,images,collection`）。
3. `items` 数量不固定（实测周一 14 条），**不含分页**。
4. 缓存：`calendar` 变化频率低，客户端按 **12 小时**缓存即可。

> 替代方案（可选）：用 `POST /v0/search/subjects` + `filter.air_date`（本周区间）+ `sort=heat` 自己算"本周新番"，就能完全摆脱旧版接口。代价是 1 次 POST（或多页）。**如果厌恶旧版接口，这是干净的做法。**

### 3.8 浏览 / 排行榜 `GET /v0/subjects`

```http
GET https://api.bgm.tv/v0/subjects?type=2&sort=rank&year=2024&limit=20
```

参数：`type`（**必填**）、`cat`（书籍分类）、`series`、`platform`、`sort`（`date` | `rank`）、`year`、`month`、`limit`、`offset`。
实测 200，返回 `Paged_Subject`。

- `sort=rank` + `type=2` = **动画排行榜**；`year`/`month` = 按季度筛。
- 服务端缓存：第一页 24h、之后 1h（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)）→ 适合做"补番推荐"页。
- 注意：此接口返回的同样是完整 `Subject`（含 `infobox`），`limit=50` 一页约 200 KB+，**不要一次拉太多页**。

### 3.9 图片 URL 拼法（**结论：v0 不用拼，直接可用**）

**v0（实测 R1，权威）**：`images` 五个字段都是**完整 https URL**，尺寸靠路径里的 `/r/{px}/` 变体区分：

| 字段 | 实测 URL | 实际宽度 |
|---|---|---|
| `large` | `https://lain.bgm.tv/pic/cover/l/c2/0a/12_q23bZ.jpg` | 原图（无 `/r/` 前缀） |
| `medium` | `https://lain.bgm.tv/r/800/pic/cover/l/c2/0a/12_q23bZ.jpg` | 800 |
| `common` | `https://lain.bgm.tv/r/400/pic/cover/l/c2/0a/12_q23bZ.jpg` | 400 |
| `small` | `https://lain.bgm.tv/r/200/pic/cover/l/c2/0a/12_q23bZ.jpg` | 200 |
| `grid` | `https://lain.bgm.tv/r/100/pic/cover/l/c2/0a/12_q23bZ.jpg` | 100 |

**旧版（[S7](https://github.com/bangumi/dev-docs/blob/master/%E5%9B%BE%E7%89%87.md)）**：数据库只存相对路径（如 `a8/7f/4_cMMK5.jpg`），需要拼前缀 + 尺寸字母：

- 条目：`https://lain.bgm.tv/pic/cover/{l|m|s|c|g}/`（5 档，`c`=common）
- 人物/角色：`https://lain.bgm.tv/pic/crt/{l|m|s|g}/`（4 档，**没有 `c`**）

**实测角色图**（`/v0/subjects/12/characters`）：`small` 用 `/r/100/pic/crt/l/`，`medium` 用 `/r/400/pic/crt/l/`，`grid` 用 `pic/crt/g/`（无 `/r/`），`large` 用 `pic/crt/l/`。→ **不要自己按字符串拼角色图，直接读字段**。

**无图兜底**（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml) `/v0/subjects/{id}/image`）：无图时返回默认图 `https://lain.bgm.tv/img/no_icon_subject.png`。

**UI 选图建议**：海报墙格子用 `grid`（100px）→ 详情页大图用 `large`；iPad/横屏格子可用 `small` 或 `common` 防糊。**绝不要拿 `large` 铺列表**（原图动辄数百 KB）。

### 3.10 条目图跳转接口 `GET /v0/subjects/{id}/image?type=`

文档说是 **302 + `Location`**（`type` ∈ `small|grid|large|medium|common`）；实测用自动跟随重定向的客户端拿到的是 **200 + 图片字节**（`GET /v0/subjects/12/image?type=large`，未出现在上方 R 表中）。
→ 实现上可以直接把它当图片 URL（`AsyncImage`/`URLSession` 都能处理重定向）；但**更推荐**直接用 §3.9 的 `images.*` 字段，少一次 302。

---

## 4. 认证与用户数据（OAuth2）

### 4.1 授权码流程

来源：[S5 How-to-Auth](https://github.com/bangumi/api/blob/master/docs-raw/How-to-Auth.md)（**唯一权威文档，内容不多，全部抄录在此**）。

#### 4.1.1 端点

| 步骤 | 端点 | 说明 |
|---|---|---|
| ① 引导授权 | `GET https://bgm.tv/oauth/authorize` | 参数 `client_id`（必）、`response_type=code`（必）、`redirect_uri`、`scope`、`state` |
| ② 回调拿 code | 你的 `redirect_uri?code=CODE` | **code 有效期 60 秒** |
| ③ 换 token | `POST https://bgm.tv/oauth/access_token` | 参数 `grant_type=authorization_code`、`client_id`、`client_secret`、`code`、`redirect_uri`（必）、`state`（可选） |
| ④ 调 API | `Authorization: Bearer <access_token>` | **v0 不允许 query string 传 token** |
| ⑤ 刷新 | `POST https://bgm.tv/oauth/access_token` | `grant_type=refresh_token`、`client_id`、`client_secret`、`refresh_token`、`redirect_uri` |
| ⑥ 查询令牌信息 | `POST https://bgm.tv/oauth/token_status` | 参数 `access_token`，返回 `expires`（unix 时间戳） |

`POST /oauth/access_token` 成功后返回：

```json
{"access_token":"…","expires_in":604800,"token_type":"Bearer","scope":null,
 "refresh_token":"…","user_id":123456}
```

- `expires_in = 604800` = **7 天**。
- `scope` 固定为 `null` —— 官方文档明确：授权页参数 `scope` 标注为「**尚未实现**」（S5 原文）。
- 实测补充：`GET /oauth/access_token` → **405**，`error_description` 明确 "The request method must be **POST** when requesting an access token"（R21）；`GET /oauth/authorize`（不带参数或假 `client_id`）返回 200 HTML 登录页（R22）——即**用户必须先登录 bgm.tv**。

#### 4.1.2 scope：形式存在，实际未生效

- 授权页 `scope` 参数"尚未实现"（S5）。
- 但 v0 schema 的 `security` 里已经出现权限字符串：`HTTPBearer: [write:collection]`（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)），说明**服务端按 token 权限点校验**，只是申请阶段无法用 `scope` 限缩。
- 实现含义：**拿到的 token 就是全权限（含写收藏）**，客户端务必自己守住"只写自己的进度"，并把它当高敏感凭据存 Keychain。

#### 4.1.3 PKCE：未发现支持

- 官方流程文档（S5）**没有** `code_challenge` / `code_verifier` / `code_challenge_method` 任何参数。
- 在 `bangumi/api` 仓库搜索 issue，**没有任何** PKCE / `code_challenge` 相关条目（GitHub issue 搜索 `repo:bangumi/api PKCE OR code_challenge` → `total_count: 0`）。
- 结论：**【待验证】不支持 PKCE**（保守按"不支持"设计）。

参考实现可直接对照开源 iOS/Android 客户端的做法（如 `czy0729/Bangumi`，其 UA 示例就出自官方文档）。

#### 4.1.4 移动端的现实难题：`client_secret` 无处安放

**这是 Bangumi 接 OAuth 的最大架构风险，必须写进决策记录**：

- 无 PKCE + 换 token 必须带 `client_secret` → 原生 App 只能把 secret **内置进包体**（可被 dump）或**自建中转服务**代换 token。
- 选项 A（内置 secret）：实现最快；secret 泄露风险；官方未提供"public client"模式。
- 选项 B（自建中转，如 Cloudflare Worker）：把 `code` 转发换 token，secret 只存在服务端；多一个后端要维护，且**回调 `redirect_uri` 必须与注册值完全一致**。
- 选项 C（不接 OAuth，v1 推荐）：进度只存本地，用 `import/export` 让用户手动搬。

**建议：v1.5 选 B**（如果 App 要上架分发）；**个人自用/内测阶段选 A 也能接受**，但要在 README 标注风险。

### 4.2 拿 `username`：`GET /v0/me`

```http
GET https://api.bgm.tv/v0/me
Authorization: Bearer <access_token>
```

- 返回 `User` + `email` + `reg_time` + `time_offset`（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)）。
- `User` 字段：`{id, username, nickname, user_group, avatar{large,medium,small}, sign}`。
- **`username` 才是后面所有 `/v0/users/{username}/…` 的 key**（不是 `id`，`id` 是数字 UID）。`username` 描述为"唯一用户名，初始与 UID 相同，可修改一次"。
- 无 token 实测：**401** `description: "need Login"`（R17）。
- token 里其实也带 `user_id`（§4.1.1），但 `/v0/me` 是拿 `username` 的唯一正路 → **登录成功后第一件事就是调它并落盘**。

### 4.3 用户收藏 `GET /v0/users/{username}/collections`

```http
GET /v0/users/sai/collections?subject_type=2&type=3&limit=30&offset=0
```

- 参数：`subject_type`（1/2/3/4/6）、`type`（1–5，见 §5.5）、`limit`（默认 30，最大 50）、`offset`。
- **公开可读**（实测 200，`total=30`），私有收藏需 token。
- 返回 `{data,total,limit,offset}`，`data[]` 元素实测字段：

```json
{"updated_at":"2026-04-14T01:26:27+08:00","comment":null,"tags":["日本","TV","2004"],
 "subject":{ …SlimSubject：id,type,name,name_cn,date,images,score,rank,eps,volumes,
             collection_total,tags… },
 "subject_id":514358,"vol_status":0,"ep_status":8,"subject_type":2,
 "type":3,"rate":0,"private":false}
```

- `ep_status` = **已看集数**（实测 8，对应 13 集的番）。**这是"追番海报墙"最省事的读法**：一次拿到封面 + 中文名 + 看到第几集。
- `type`：1 想看 / 2 看过 / 3 在看 / 4 搁置 / 5 抛弃（[S12](https://github.com/bangumi/server/blob/master/openapi/components/subject_collection_type.yaml)）。
- 单个条目：`GET /v0/users/{username}/collections/{subject_id}`（未收藏 → 404）。

### 4.4 写收藏 `POST|PATCH /v0/users/-/collections/{subject_id}`

- **`-` 代表"当前 token 用户"**，不用拼 username。
- `POST` = 不存在则创建、存在则修改；`PATCH` = 只改，未收藏返回 404（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)）。
- 返回 **204**（无 body）。
- 请求体（**所有字段可选**，[S1 UserSubjectCollectionModifyPayload](https://github.com/bangumi/server/blob/master/openapi/components/user_subject_collection_modify_payload.yaml)）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | 1–5 | 收藏类型 |
| `rate` | 0–10 | 评分，`0` 表示删除评分 |
| `ep_status` | int | **只能用于书籍条目**的进度（动画会报错/无效） |
| `vol_status` | int | 同上，卷数 |
| `comment` | string | 评价 |
| `private` | bool | 仅自己可见 |
| `tags` | [string] | 标签；不传/`null` 忽略；传 `[]` 清空；不能含空格 |

> ⚠️ 文档原话："由于直接修改剧集条目的完成度可能会引起意料之外效果，**只能用于修改书籍类条目的完成度**"。
> → **动画进度绝不能靠 `ep_status` 写**，必须走 §4.5。

### 4.5 单集进度（动画进度的唯一正路）

| 操作 | 接口 | Body | 返回 |
|---|---|---|---|
| 读某条目全部集进度 | `GET /v0/users/-/collections/{subject_id}/episodes?episode_type=0&limit=1000` | — | `{data:[{episode:{…}, type, updated_at}], total,…}` |
| 读单集 | `GET /v0/users/-/collections/-/episodes/{episode_id}` | — | `UserEpisodeCollection` |
| **批量写（推荐）** | `PATCH /v0/users/-/collections/{subject_id}/episodes` | `{"episode_id":[1027,1028],"type":2}` | 204 |
| 单集写 | `PUT /v0/users/-/collections/-/episodes/{episode_id}` | `{"type":2}` | 204 |

- `EpisodeCollectionType`（[S13](https://github.com/bangumi/server/blob/master/openapi/components/episode_collection_type.yaml)）：`0` 未收藏 / `1` 想看 / `2` 看过 / `3` 抛弃。
- `PATCH` 语义是"**把列出的 episode 全部置为该状态**"，且"**同时会重新计算条目的完成度**"（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)）。
- 所以"看到第 8 集"最省请求的写法是：**一次 PATCH 把 1–8 全部置为 `2`**（幂等，可重放）；不要逐集 PUT。
- 实测未做（需 token）→ 这一节全部为【文档】。**第一次接真账号时必须抓包核对 204 与完成度回算**。

### 4.6 token 存储与刷新策略

| 项 | 建议 |
|---|---|
| 存储 | Keychain（`kSecClassGenericPassword`），`access_token`/`refresh_token`/`expires_at` 三项；**不要进 UserDefaults** |
| 提前刷新 | 本地记 `expires_at = now + expires_in`，**剩余 < 1 天**时后台刷新 |
| 401 处理 | 收到 401 → 刷新一次 → 重放原请求一次；仍 401 → 清 token、切游客态、提示重新登录 |
| 刷新失败 | 保留 refresh_token（刷新失败未必是 token 失效，可能是网络/5xx），只降级为游客态 |
| 并发刷新 | 用 actor 串行化，避免 3 个并发 401 触发 3 次刷新（refresh_token 可能一次性）【待验证：Bangumi 是否轮换 refresh_token 并失效旧的——文档只说"返回新的 access_token 与 refresh_token"】 |
| 登出 | 只清本地 token；如需解绑，引导用户去 bgm.tv 设置页撤销授权（未发现 revoke 接口，**待验证**） |

---

## 5. 数据结构

### 5.1 Subject（条目）

`GET /v0/subjects/{id}` 与 `POST /v0/search/subjects` 的 `data[]` 都是这个结构（实测 R1 keys 全量）。

| 字段 | 类型 | 说明 | 备注 / 陷阱 |
|---|---|---|---|
| `id` | int | 条目 ID | |
| `type` | int | 1 书籍 / 2 动画 / 3 音乐 / 4 游戏 / 6 三次元 | **没有 5** |
| `name` | string | 原名（多为日文） | |
| `name_cn` | string | 简体中文名 | **可空字符串**，UI 要回退到 `name` |
| `summary` | string | 简介 | 含 `\r\n`；可空 |
| `date` | string | 放送/发售日 `YYYY-MM-DD` | **可为 `null` 或 `""`**（实测两种都出现） |
| `platform` | string | `TV` / `WEB` / `OVA` / `剧场版` / `小说` / `游戏` / `画集`… | 字符串，非枚举数字；全表见 [S11](https://github.com/bangumi/server/blob/master/pkg/vars/platform.go.json) |
| `images` | object | 5 档完整 URL | 见 §3.9 |
| `infobox` | array | `[{key, value}]`，`value` 为 string 或 `[{k,v}]` | **别名都在这里** |
| `eps` | int | wiki 填的"话数" | 与实际章节数**不一定相等** |
| `total_episodes` | int | DB 中章节总数 | **含 SP/OP/ED**（实测 R4） |
| `volumes` | int | 书籍册数 | 动画为 0 |
| `series` | bool | 是否书籍系列主条目 | |
| `rating` | object | `{rank, total, count{1..10}, score}` | `count` 的 key 是**字符串** |
| `collection` | object | `{wish, collect, doing, on_hold, dropped}` | 各项人数 |
| `tags` | array | `[{name, count, total_count}]` | 最多 30 条（实测） |
| `meta_tags` | array | 维基人维护的公共标签 | 实测 `["科幻","TV","恋爱","日本","漫画改","日常"]` |
| `locked` / `nsfw` | bool | | |
| `image` | string | **仅搜索结果里有**（旧字段） | 与 `images.large` 并存，忽略即可 |

### 5.2 Episode（章节）

`GET /v0/episodes?subject_id=` 的 `data[]`：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | int | 章节 ID（**写进度用它**） |
| `type` | int | 0 本篇 / 1 SP / 2 OP / 3 ED / 4 预告广告 / 5 MAD / 6 其他 |
| `ep` | number | 本篇内序号，从 1 开始；非本篇为 0 或无 |
| `sort` | number | 同类内排序/集数，**可为小数**（实测 `8.5`） |
| `name` / `name_cn` | string | 标题 / 简体中文标题（可空） |
| `airdate` | string | `YYYY-MM-DD`（可空字符串） |
| `duration` | string | 原始时长（`"24m"`） |
| `duration_seconds` | int | 服务端解析的秒数，解析失败 `0` |
| `desc` | string | 简介 |
| `comment` | int | 吐槽数 |
| `disc` | int | 碟片号（音乐用） |
| `subject_id` | int | 所属条目 |

#### 陷阱 1：`eps` / `total_episodes` 不可信

| 条目 | `subject.eps` | `total_episodes` | 实测 `type=0` 实数 | 实测 `type=1`(SP) |
|---|---|---|---|---|
| 12（人形电脑天使心） | 27 | 27 | **24** | 3 |
| 253（EVA） | 26 | 31 | **26** | 1（+OP 1） |
| 411427（间谍过家家 S2） | 12 | 12 | **12** | — |

→ **判断"有几集"必须请求 `/v0/episodes?subject_id=&type=0` 取 `total`**，然后用 `limit=200` 分页拉全（24 集一次就够；长篇需要 offset 翻页）。

#### 陷阱 2：`sort` 会"跨季续编号"，`ep` 会"重启"

实测 R5：`411427`（SPY S2）第一集 `ep=1` 但 **`sort=26`**（延续第 1 季的 12 集 + 第 2 部分 13 集）。而 `12` 的 SP 是 `ep=0, sort=8.5`。

→ **本地文件 `01.mkv` 要匹配 `ep`，不是 `sort`。**
→ 反过来，如果本地是"整季合集/跨季连播"（`01`–`37`），就该用 `sort`。
→ 因此匹配器必须**同时保留两个编号**，按本地编号区间自动选择（§6.6）。

### 5.3 Images

见 §3.9。要点重申：

- v0 全部是**完整 https URL**，直接用。
- 旧版与 `/calendar` 是 **`http://`**，解码后必须 `replacingOccurrences(of: "http://lain.bgm.tv", with: "https://lain.bgm.tv")`。
- 尺寸档不统一（条目 5 档含 `common`，人物/角色 4 档无 `common`），**按字段名取，不要自己拼**。

### 5.4 枚举速查

| 枚举 | 取值 |
|---|---|
| `SubjectType` | `1` 书籍、`2` 动画、`3` 音乐、`4` 游戏、`6` 三次元（无 5） |
| `EpType` | `0` 本篇、`1` SP、`2` OP、`3` ED、`4` 预告/宣传、`5` MAD、`6` 其他 |
| `SubjectCollectionType` | `1` 想看、`2` 看过、`3` 在看、`4` 搁置、`5` 抛弃 |
| `EpisodeCollectionType` | `0` 未收藏、`1` 想看、`2` 看过、`3` 抛弃 |
| `PersonType` | `1` 个人、`2` 公司、`3` 组合 |
| `PersonCareer` | `producer` / `mangaka` / `artist` / `seiyu` / `writer` / `illustrator` / `actor` |
| `platform`（动画，实测常见） | `TV`、`WEB`、`OVA`、`剧场版`、`动态漫画` |

### 5.5 Codable 建模（Swift）

关键点：**`sort`/`ep` 是 Double**、**`date` 可能是 null**、**`rating.count` 的 key 是字符串**、**`infobox.value` 是联合类型**、**`nsfw`/`images` 可能缺**。

```swift
import Foundation

// 用 .convertFromSnakeCase 会与 date / infobox 等自定义解码打架，建议显式 CodingKeys。
struct BGMSearchResponse: Decodable {
    let total: Int
    let limit: Int
    let offset: Int
    let data: [BGMSubject]
}

struct BGMSubject: Decodable, Identifiable {
    let id: Int
    let type: Int              // 1/2/3/4/6
    let name: String
    let nameCn: String?        // 可能 "" 或 null
    let summary: String?
    let date: String?          // 可能 null / ""
    let platform: String?
    let images: BGMImages?
    let eps: Int?
    let totalEpisodes: Int?
    let rating: BGMRating?
    let collection: BGMCollection?
    let tags: [BGMSubjectTag]?
    let metaTags: [String]?
    let nsfw: Bool?
    let infobox: [BGMInfoBoxItem]?

    enum CodingKeys: String, CodingKey {
        case id, type, name, summary, date, platform, images, eps, rating, collection, tags, nsfw, infobox
        case nameCn = "name_cn"
        case totalEpisodes = "total_episodes"
        case metaTags = "meta_tags"
    }

    /// 展示用名：优先中文名，空串/null 回退原名
    var displayName: String {
        if let cn = nameCn, !cn.isEmpty { return cn }
        return name
    }
}

struct BGMImages: Decodable {
    let large: String?
    let common: String?
    let medium: String?
    let small: String?
    let grid: String?

    var largeURL: URL? { Self.safe(large) }
    var gridURL: URL?  { Self.safe(grid ?? small) }

    /// 旧版接口/日历会给 http://，ATS 会拦 → 统一升 https
    private static func safe(_ s: String?) -> URL? {
        guard var s, !s.isEmpty else { return nil }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        return URL(string: s)
    }
}

struct BGMRating: Decodable {
    let rank: Int?
    let total: Int?
    let score: Double?         // 无评分时可能 0 或 null
    let count: [String: Int]?  // key = "1"…"10"
}

struct BGMCollection: Decodable {
    let wish: Int?
    let collect: Int?
    let doing: Int?
    let onHold: Int?
    let dropped: Int?
    enum CodingKeys: String, CodingKey {
        case wish, collect, doing, dropped
        case onHold = "on_hold"
    }
}

struct BGMSubjectTag: Decodable, Identifiable {
    let name: String
    let count: Int
    let totalCount: Int?
    var id: String { name }
    enum CodingKeys: String, CodingKey { case name, count; case totalCount = "total_count" }
}

/// infobox.value 是 String 或 [{k,v}] 联合类型
struct BGMInfoBoxItem: Decodable {
    let key: String
    let value: BGMInfoValue
}

enum BGMInfoValue: Decodable {
    case text(String)
    case pairs([KeyValue])

    struct KeyValue: Decodable { let k: String?; let v: String? }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let s = try? single.decode(String.self) { self = .text(s); return }
        if let arr = try? single.decode([KeyValue].self) { self = .pairs(arr); return }
        self = .text("")
    }

    /// 展开成纯文本别名数组：匹配算法要用
    var aliases: [String] {
        switch self {
        case .text(let s): return [s]
        case .pairs(let ps): return ps.compactMap { $0.v }
        }
    }
}

// MARK: - 章节

struct BGMEpisodePage: Decodable {
    let total: Int
    let limit: Int
    let offset: Int
    let data: [BGMEpisode]
}

struct BGMEpisode: Decodable, Identifiable {
    let id: Int
    let type: Int              // 0 本篇
    let name: String
    let nameCn: String?
    let ep: Double?            // 本篇序号，可能缺省
    let sort: Double           // 必填、可为小数
    let airdate: String?       // 可能 ""
    let duration: String?
    let durationSeconds: Int?
    let desc: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, sort, airdate, duration, desc
        case nameCn = "name_cn"
        case ep
        case durationSeconds = "duration_seconds"
    }

    var displayName: String {
        if let cn = nameCn, !cn.isEmpty { return cn }
        if !name.isEmpty { return name }
        return "第 \(Int(sort)) 集"
    }
}

// MARK: - 统一错误

struct BGMError: Decodable, Error {
    let title: String
    let description: String?
    let requestId: String?
    struct Details: Decodable { let path: String?; let method: String? }
    let details: Details?

    enum CodingKeys: String, CodingKey {
        case title, description, details
        case requestId = "request_id"
    }
}
```

> **为什么手写 CodingKeys**：接口混用 `snake_case`（`name_cn`）与短名（`ep`/`sort`/`date`），且 `ep` 可能不存在。`keyDecodingStrategy = .convertFromSnakeCase` 会把 `name_cn` 变 `nameCn`（没问题），但**同时**会把你要显式映射的 `request_id` 也变掉，调试期容易出玄学 bug。显式声明更稳。

---

## 6. 匹配策略：文件名 → subject + episode

这是本项目**唯一真正的算法工作**，也是最大的失败来源。先看三条实测事实：

1. **原始文件名直接搜 → 0 结果**（R8）。`[Nekomoe kissaten] Sousou no Frieren [01][1080p][CHS]` → `total=0`。必须先把"组名/分辨率/编码/字幕语言/集号"剥掉。
2. **季号写进关键词会显著改善排序**（R6）：`"间谍过家家 第二季"` 的第 1 条就是目标条目；只搜 `"间谍过家家"` 第 1 条是第 1 季。
3. **`air_date` 区间过滤是终极消歧器**（R7）：加上 `[">=2022-04-01","<2022-07-01"]` 后候选从 27 → 1。

### 6.1 总体流程

```
文件名 ──①清洗/解析──▶ (baseTitle, seasonHint, episodeNo, kindHint, yearHint)
                              │
                              ▼
                    ②候选召回（两路搜索，各 ≤10 条）
                              │
                              ▼
                    ③归一化 + 别名扩展（name / name_cn / infobox 别名）
                              │
                              ▼
                    ④打分排序（标题 60 + 季号 20 + 年份/日期 10 + 类型 10）
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
         ≥85 自动绑定    60–85 让用户确认    <60 手动搜索
                              │
                              ▼
                    ⑤集号映射（ep 优先，必要时 sort）
```

### 6.2 ① 文件名解析

目标：从 `[Nekomoe kissaten&LoliHouse] Sousou no Frieren - 03 [WebRip 1080p HEVC-10bit AAC][CHS&JPN].mkv` 提取
`baseTitle="Sousou no Frieren"`、`episodeNo=3`、`seasonHint=nil`、`kindHint=TV`。

规则（按顺序应用，每步都记录命中项，便于调试）：

1. 去扩展名（`.mkv/.mp4/.avi/.ts/.m2ts/.flv/.wmv`）。
2. 去掉**方括号/圆括号/花括号**包裹的**技术标签**（`[...]`、`(...)`、`【...】`）——但要**保留**可能是标题的括号内容（含 CJK 且长度 > 4 的保留，其余丢弃）。
3. 去掉发布组前缀（第一个 `[...]` 前无内容时，整段丢弃）。
4. 去掉关键词（大小写不敏感）：`1080p|720p|2160p|4k|8k|hevc|avc|x264|x265|h\.?264|h\.?265|10bit|8bit|aac|flac|opus|webrip|web-dl|bluray|bdrip|bd|dvdrip|hdtv|remux|chs|cht|jpn|jpn&chs|gb|big5|简|繁|简体|繁体|内嵌|外挂|字幕|招新|招募|v2|repack|uncensored`。
5. 提取并移除**集号**：`- 03`、`[03]`、`EP03`、`E03`、`第3话/第3集`、`03话`。**只在标题之后出现时**才算集号（防止 `86 - Eighty Six` 被误伤）。
6. 提取并移除**季号**：`S02`、`Season 2`、`2nd Season`、`第2季`、`第二季`、`II`、`2期`、`Part 2`、`Cour 2`。
7. 提取**年份**：`(2023)`、`[2023]`、`2023年`。
8. 提取**类型提示**：含 `剧场版|Movie|Gekijouban` → `.movie`；含 `OVA|OAD|特别篇|SP` → `.ova`；否则 `.tv`。
9. 剩余部分做分隔符归一（`.`、`_`、`-`、`×` 两侧空格 → 空格），压缩空白 → `baseTitle`。

> 建议把 1–9 写成**纯函数 + 单元测试表**（30 条真实文件名做 golden test），这是最值得投入测试的地方。

### 6.3 ② 候选召回

对同一部片子做**最多两路**搜索（控制请求数，全局 1 rps）：

| 路 | keyword | filter | 说明 |
|---|---|---|---|
| L1 | `baseTitle + seasonToken`（有季号时拼上"第N季"） | `type:[2]`、`nsfw:false`、`limit:8` | 主力；季号入词提升排序（R6） |
| L2 | `baseTitle`（不带季号） | 同上 + （若有年份）`air_date:[">={year-1}-01-01","<={year+1}-12-31"]` | 兜底；`air_date` 是最强消歧（R7） |

- `baseTitle` 为空或纯符号 → 直接放弃（避免 R9 的 `total=1000` 空搜索）。
- 若 `total=0` → 再尝试 **季号去掉、只留首个 2–3 个词**的降级查询，最多 1 次。
- 若两次都 `total=0` → 进"未匹配"，让用户手动搜。

> 罗马音 → 日文的转换不要指 API 的"模糊"能力：实测 `Sousou no Frieren` 能搜到（`total=3`），但**结果排第一的是第 2 季**（因为 match 排序按热度）。所以**排序永远要自己重算**，不能信 `sort=match`。

### 6.4 ③ 归一化

对 `baseTitle` 与候选的 `name`、`name_cn`、`infobox` 里所有别名（`中文名/别名/英文名/日文名/第二中文名/罗马字` 等 key）**逐一比较**：

```
normalize(s):
  1. Unicode NFKC（全角→半角，× → x 的兼容分解需例外处理）
  2. 小写
  3. 去掉所有空白与标点：空格 ・ ・ ･ ： : ！ ! ？ ? 、 ， , . ~ ～ - – — / ＆ &
  4. 片假名 → 平假名
  5. 繁 → 简（内置映射表或 OpenCC 数据，务必本地做，别联网）
  6. 去掉尾部季号标记与"第N季/第N期/Season N"
  7. 罗马音长音/促音归一（ou→o、uu→u、ā→a 等）——只在"罗马音 ↔ 罗马音"比较时启用
```

**不要**做的：拼音转换（`banggumi`→`bangumi` 之类）。收益低、错误率高。

### 6.5 ④ 打分

设候选 `c`，解析结果 `p`：

```
titleScore  ∈ [0,1]   // 见下
seasonScore ∈ [0,1]   // 季号是否与候选一致
dateScore   ∈ [0,1]   // 年份/放送日与 p.yearHint 的接近度
kindScore   ∈ [0,1]   // platform 与 p.kindHint 一致性

total = 60*titleScore + 20*seasonScore + 10*dateScore + 10*kindScore
```

`titleScore` 取候选所有别名中的最高分：

| 情形 | 分值 |
|---|---|
| 归一化后完全相等 | 1.00 |
| 一方是另一方的前缀/后缀，且短者长度 ≥ 4 | 0.90 |
| 词集合 Jaccard ≥ 0.8 | 0.75 |
| Jaccard ≥ 0.5 | 0.55 |
| Jaccard ≥ 0.3 | 0.35 |
| 否则 | 0 |

`seasonScore`：

- 候选标题/别名里解析出的季号 == `p.seasonHint` → 1.0
- 两边都没季号（都视作第 1 季）→ 1.0
- 候选中出现 `第2期/Season 2/II` 而 `p` 无季号 → 0.3（可能误判成续作）
- 明显冲突（第 1 季 vs 第 3 季）→ 0

`dateScore`：有 `yearHint` 时 `1 - min(|year差|,3)/3`；无年份 → 0.5（中性）。

`kindScore`：`platform` 与 `kindHint` 一致 1.0；不冲突（如 `.tv` vs `WEB`）0.7；冲突（`.tv` vs `剧场版`）0。

**分档动作**：

| 总分 | 动作 |
|---|---|
| ≥ 85 | 自动绑定，详情页显示"数据来源 Bangumi" + 可手动改 |
| 60–85 | 显示前 3 个候选，让用户点一下（**默认不写库**） |
| < 60 | 视为未匹配，走手动搜索（把 `baseTitle` 预填进搜索框） |

> 用户**手动绑定过的结果永远优先**，写进 `manualBinding` 表，自动匹配不得覆盖。

### 6.6 ⑤ 季号处理（**Bangumi 的核心差异点**）

Bangumi 用**独立 subject 表示每一季**（不像 TMDB 的 `season` 子对象）。所以"第 2 季"不是参数，是**另一个条目**。

要点：

1. **必须先解析季号再搜索**，且季号要进关键词（R6 实测：`"... 第二季"` 直接把目标顶到第 1 位）。
2. 季号 token 归一化映射：`S2 / Season 2 / 2nd Season / 第2季 / 第二季 / 2期 / Part 2 / Cour 2 / II` → `season = 2`。
3. **无季号的默认是第 1 季**；但如果候选里存在"更早的同名条目"，且本地文件年份更新，说明可能是续作 → 降权第 1 季候选。
4. **利用 `续集/前传` 关系链校正**（§3.5）：如果 `p` 匹配到了第 1 季，而季号是 3，可以沿 `relation == "续集"` 走两跳到真正目标。这比改关键词更精确，代价是多 2 次请求（可只在"季号 ≥ 2 且标题打分相同"时启用）。
5. `platform` 区分 `TV` / `WEB` / `OVA` / `剧场版`（[S11](https://github.com/bangumi/server/blob/master/pkg/vars/platform.go.json)）：
   - 文件名含 `剧场版/Movie/劇場版` → 优先 `platform == 剧场版`；
   - 含 `OVA/OAD` → 优先 `platform == OVA`；
   - 注意实测反例：`id=253`（EVA TV 版）的 `platform` 是 `TV`，而 `eps=26`——**不要用 `eps==1` 判断剧场版**。
6. 剧场版通常是**单集**：整部影片直接映射到 `ep=1`（或 `sort=1`），不需要集号；文件名里的数字（如 `2023`）**不能**当集号解析。

### 6.7 ⑥ 集号映射（第二难的坑）

拿到 subject 后：

```
episodes = GET /v0/episodes?subject_id={id}&type=0&limit=200（翻页取全）
```

再按"本地编号体系"二选一：

| 本地文件形态 | 用哪个编号 | 判据 |
|---|---|---|
| 每季从 01 重新编号 | **`ep`** | `1...N` 且 `N ≤ 该季本篇总数` |
| 跨季连播（01–37） | **`sort`** | `N > 该季本篇总数`，且 `max(sort) ≥ N` |
| 单集文件带绝对集号（`S02E05` = 全系列第 17 集） | `sort` | 同上 |
| 剧场版/OVA 单文件 | `ep=1`（无则 `sort=1`） | `kindHint != .tv` |
| 本地是 `SP01/OVA02` | `type=1` 里按 `sort` 升序取第 n 个 | 文件名含 `SP/OVA/OAD/特别篇` |

**实测依据**：R5 里 `411427`（SPY S2）第 1 集 `ep=1`、`sort=26`；若错用 `sort`，`S02E01` 会被映射成"全系列第 26 集"，进度就会写错。

补充规则：

- 只把 `type == 0` 的章节放进"剧集列表"UI；`type ∈ {1..6}` 收进"其他"折叠区（数量少，但 Bangumi 里 SP 常常有真实标题，别丢）。
- 若 `episodes.count` 与本地集数差 1–2 且 `sort` 连续（例如 Bangumi 少录了一集总集篇）→ 用 `sort` 序列对齐，并把差异显示为"本地多出 N 集"，**不要静默错位**。
- 多文件合并（`01-12` 一个文件）→ 该文件绑定 `ep` 区间，播放进度百分比折算到区间内。

### 6.8 匹配结果持久化（建议表结构）

```swift
@Model final class MediaBinding {      // SwiftData
    @Attribute(.unique) var fileKey: String   // 光鸭 path 的稳定 hash
    var subjectId: Int?
    var episodeId: Int?
    var seasonNo: Int?
    var episodeNo: Double?
    var confidence: Double          // 0…1
    var source: String              // "auto" / "manual"
    var updatedAt: Date
}
```

- `confidence < 0.85` 的**不要**写 `subjectId`，只写"未匹配 + 建议 id"，避免污染海报墙。
- 重新扫描时：`source == "manual"` 的行**跳过**自动匹配。

---

## 7. Swift 实现注意

### 7.1 URLSession 配置

```swift
let cfg = URLSessionConfiguration.default
cfg.httpMaximumConnectionsPerHost = 2      // 与全局 1rps 配合
cfg.timeoutIntervalForRequest = 15
cfg.timeoutIntervalForResource = 30
cfg.requestCachePolicy = .useProtocolCachePolicy
cfg.urlCache = URLCache(memoryCapacity: 50 << 20, diskCapacity: 500 << 20)

// 关键：UA 必须可识别（S4）
cfg.httpAdditionalHeaders = [
    "User-Agent": "LemonPlayer/1.0.0 (iOS; https://github.com/<owner>/LemonPlayer)",
    "Accept": "application/json"
]
```

- **不要**用 `URLSession.shared` 的默认 UA（`CFNetwork/…`），文档明说默认 UA 可能被封。
- 图片请求也走同一个带 UA 的 session（`lain.bgm.tv` 对 Referer 无要求，但带 UA 更安全）。

### 7.2 解码容错（实验性接口 + 老旧字段）

- 所有**非关键字段**用 `Optional`（`rating`、`collection`、`tags`、`infobox`、`durationSeconds`…）。
- `date` / `airdate` 用 `String?`，**不要**直接 `Date` 解码（会因 `null`/`""` 崩）。
- `sort` / `ep` 用 `Double`（实测 `8.5`）。
- `rating.count` 用 `[String: Int]`（key 是 `"1"…"10"`）。
- 搜索接口文档标注"实验性"→ **`decodeIfPresent` 全开**，任何新增字段都不该让 App 崩。

### 7.3 日期处理（`air_date` 是 `YYYY-MM-DD`，无时区）

```swift
enum BGMDate {
    // 只用于"显示"与"比较"，绝不带时区语义
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")!  // 放送日按日本时间理解
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return formatter.date(from: s)
    }
}
```

- 陷阱：用设备本地时区解析 `2024-04-07`，在 UTC-8 的设备上会显示成 `2024-04-06`。**统一 `Asia/Tokyo`** 或干脆当字符串比较。
- `updated_at`（收藏）/`reg_time`（用户）是 RFC3339 带偏移（`2026-04-14T01:26:27+08:00`）→ 用 `ISO8601DateFormatter`（`.withInternetDateTime`）或 `Date.ISO8601FormatStyle`。
- `token_status` 的 `expires` 是 **unix 秒级时间戳**（Int），不是字符串。

### 7.4 图片加载与缓存

- 用 `AsyncImage` 起步，但**上线前换成 Nuke / Kingfisher**（`AsyncImage` 无磁盘缓存、无重试、无降级）。
- Key 用 `subject.id + 尺寸档`（URL 里 `?r=` 版本参数会变，直接当 URL key 也可）。
- 尺寸选择：格子 `grid`，列表 `small`，详情头部 `large`，背景模糊用 `medium`。
- 磁盘缓存上限 500 MB，LRU；「清除缓存」入口放设置页。
- 无图/加载失败：用 `https://lain.bgm.tv/img/no_icon_subject.png` 兜底（[S1](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml) 明确这是默认图）。

### 7.5 并发限流（≥1 请求/秒）

```swift
actor RateLimiter {
    private let minInterval: TimeInterval = 1.0 / 1.0   // 1 req/s
    private var last: Date = .distantPast
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(last)
        if elapsed >= minInterval {
            last = now
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
            Task { try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000)) }
        }
        last = Date()
    }
}
```

更稳妥的版本：用一个 `AsyncStream` 串行令牌队列，避免上面的写法在并发下抖动。要点：

- **所有** 出站请求（含图片）共享同一个 limiter（或图片单独给更高配额，但图片走 CDN，可放宽）。
- 批量任务用 `TaskGroup` 且 `maxConcurrent = 1`（限流器已串行，`TaskGroup` 只用于结构化取消）。
- 用户滚动触发的请求要能**取消**（`Task.checkCancellation()`），否则会排队把限流器堵死。

### 7.6 请求构造注意事项

- **中文关键词必须走 JSON body**（`POST /v0/search/subjects`）——天然避免 URL 编码问题。若用 GET（日历/详情）则无需中文。
- `Content-Type: application/json`；body 里 `keyword` 用 UTF-8 编码，不要 `\u` 转义（两者 API 都接受，但原生 UTF-8 更易读）。
- `Authorization: Bearer <token>`（**只放 header**，v0 不接受 query token）。
- **谨慎设 `If-None-Match`**：服务端缓存 300s，客户端 ETag 反而可能拿到 304 却无 body（需要自己处理），v1 直接关掉条件请求更简单。

### 7.7 与光鸭云盘的衔接

- 光鸭侧只负责"文件 + 路径 + 时长"（见 [GUANGYA_API.md](GUANGYA_API.md)），**Bangumi 侧只负责元数据**，两边用 `MediaBinding` 连接。
- 文件列表 → 解析文件名 → Bangumi 匹配（离线批量，串行 1 rps）→ 写入 `MediaBinding`。
- **首次建库要算好时间**：1 rps × 500 个文件 ≈ 8–10 分钟。→ 放到后台任务（`BGProcessingTask`），显示进度条；或直接用 `bangumi/Archive` 预置一个"条目 id ↔ 名称/别名"的本地索引，**先本地匹配，匹配不上的再打 API**（可把 95% 的请求省掉）。

---

## 8. 与 TMDB 的取舍

### 8.1 硬指标对比

| 维度 | Bangumi | TMDB |
|---|---|---|
| 中文番名 | ✅ 原生 `name_cn`（实测覆盖良好） | ⚠️ 依赖 `language=zh-CN` 的 translation，日番常有缺失/机翻 |
| 分集标题 | ✅ `name` + `name_cn` 双标题（实测 R2） | ⚠️ 日番 episode 标题常缺失，编号导向 |
| 中文简介 | ✅ `summary` | ⚠️ 常缺，或英文机翻 |
| 放送日历 | ✅ `GET /calendar` 每日放送（R10） | ❌ 无"每日放送"概念 |
| 评分/排名/标签 | ✅ 动漫向评分更贴近目标用户 | ✅ 但受众不同（西方影视向） |
| **单集观看进度** | ✅ 官方 API 原生支持（§4.5） | ❌ 只能靠本地（或第三方 Trakt） |
| 每季是否独立条目 | ✅ 独立 subject（季号必须自己处理） | ❌/✅ 有 season 对象，但日番划分常错（把 1 季拆成 2 部等） |
| 剧场版/OVA 区分 | ✅ `platform` 字段（TV/OVA/剧场版/WEB） | ⚠️ 靠 `runtime`/`episode_count` 猜 |
| 三次元（日剧/电影）覆盖 | ⚠️ 有 `type=6`（日剧/欧美剧/华语剧/电影/综艺，[S11](https://github.com/bangumi/server/blob/master/pkg/vars/platform.go.json)），但库小 | ✅ 强 |
| 非日本动画（欧美动画/国漫） | ⚠️ 有但弱 | ✅ 更强 |
| 图片分辨率 | ⚠️ 海报原图多为 300–800px 宽（`large` 常 ~400–500px），`/r/800` 只有放大变体 | ✅ `original` 可达 2000px |
| 图片 URL | ✅ v0 直接完整 URL | ⚠️ 需 `/configuration` 取 `base_url` 再拼 `w500`（[S18](https://developer.themoviedb.org/docs/image-basics)） |
| 鉴权门槛 | ⚠️ 写操作需 OAuth（无 PKCE，见 §4.1.3） | ⚠️ 需 API Key；用户级操作另需 session |
| 限流 | ⚠️ 无数值，靠自律（§2.5） | ✅ 文档化：~40 req/s（[S17](https://developer.themoviedb.org/docs/rate-limiting)） |
| 商用授权 | ❓ **未找到任何授权条款**（§9） | ⚠️ 开发者 API 仅限非商用；商用需联系销售（[S16](https://developer.themoviedb.org/docs/faq)） |
| 署名要求 | ❓ 无正式要求（§9） | ✅ 强制：logo + "This product uses the TMDB API but is not endorsed or certified by TMDB."（[S16](https://developer.themoviedb.org/docs/faq)） |

### 8.2 推荐结论

**「Bangumi 优先 + TMDB 兜底」，但兜底放在 v2，且只兜"Bangumi 明确没有/搜不到"的情况。**

```
匹配流程（最终形态）
  1. 本地索引（Archive 预置）→ 命中 → 结束（不发网络请求）
  2. POST /v0/search/subjects → 得分 ≥85 → 绑定 Bangumi
  3. 得分 60–85 → 用户确认（不自动）
  4. 全程 total == 0 且 kindHint ∈ {tv-movie, 三次元} → 查 TMDB 兜底
  5. 仍失败 → 手动搜索
```

**为什么不做"只做 Bangumi"**：三次元/欧美剧是明显短板，而用户随时可能放一部日剧进去；兜底成本低（一个 `search/movie` + `search/tv`）。

**为什么不"双写双读"**：两边的季/集编号模型根本不同（Bangumi 一季一条目，TMDB 一剧多季），双写会让进度记录变成噩梦。**一个文件只允许绑定一个源**。

**给 v1 的明确建议**：**只接 Bangumi 公开接口**。理由：
1. 用户主力是动漫，TMDB 的增量价值在 v1 几乎为零；
2. 少一个 API Key、少一套署名义务、少一套限流策略；
3. TMDB 的商用限制（[S16](https://developer.themoviedb.org/docs/faq)）反而比 Bangumi（无明显限制但也没授权，见 §9）更需要提前想清楚商业模式。

---

## 9. 合规：图片版权、商用、App Store

### 9.1 Bangumi 是否给出使用条款？

**结论：没有找到。**

| 查证项 | 结果 |
|---|---|
| `https://bgm.tv/about/terms`、`/terms`、`/about/contact`、`/about/site` | 全部 **404**（实测） |
| `https://bgm.tv/about` | 只有项目编年史（"关于 Bangumi 番组计划"），**无使用条款/授权声明** |
| `bangumi/api` 仓库 | 文件树中**没有 LICENSE 文件**（只有 README + docs-raw + open-api） |
| `bangumi/server` 仓库 | 有 `LICENSE.txt`（**AGPLv3**）——但那是**服务端源码**的许可，**不等于** API 数据/图片的授权 |
| API 文档中关于授权/商用的说明 | **无**（`docs-raw/` 三篇 + 两份 OpenAPI 均无） |

→ 因此：**不能声称"Bangumi 允许商用"或"禁止商用"**，这两句都没有依据。可依据的只有"未发现公开条款"这一事实。

### 9.2 图片版权

- Bangumi 的封面/角色图是**用户上传**的官方宣传物料，**版权归原权利人**（动画制作委员会/出版社等），Bangumi 不拥有这些图片【推断，但 [S10](https://github.com/bangumi/Archive) 的导出内容也印证"数据来自 wiki 用户填写"】。
- 实操建议（风险最低）：
  1. **在线按需加载**（`lain.bgm.tv` 直链），**不要把图片打包进 App、不要做离线全量缓存后再分发**。
  2. 详情页底部标注 **"数据与图片来源：Bangumi 番组计划"**，并链到 `https://bgm.tv/subject/{id}`。
  3. 缓存仅用于性能（LRU、上限、可清理），不做二次分发。
  4. 用户本地海报可自定义覆盖（让用户自己对版权负责）。
- 反例（不要做）：把 `images.large` 全量下载后打进 IPA；把海报用于 App Store 截图/宣传物料（这属于商业使用，风险最高）。

### 9.3 商用

- Bangumi 侧：**无公开条款** → 若 LemonPlayer 计划收费/内购，**法务上属于"未获明确授权"状态**。可做的降低风险动作：
  1. 在 README / 关于页写明数据来源与"非官方"；
  2. 不把 Bangumi 数据作为付费卖点（付费卖的是播放器能力，不是数据）；
  3. 若规模做大，去 `bangumi/api` 仓库开 issue 直接问授权（这是唯一官方沟通渠道，[README](https://github.com/bangumi/api/blob/master/README.md) 明确"优先用 GitHub issue"）。
- TMDB 侧（如果 v2 接）：开发者 API **仅限非商用**，商用必须联系销售拿 license，且**强制署名**【[S16](https://developer.themoviedb.org/docs/faq)】。

### 9.4 App Store 展示要求

- **5.2 知识产权**：开发者对 App 内使用的第三方内容（图片、名称、简介）负责，需有使用权或合法依据【[S19](https://developer.apple.com/app-store/review/guidelines/)】。→ 呼应 §9.2，别把海报放进商店素材。
- **1.1 内容**：NSFW 内容要过滤。好消息是 Bangumi 未授权时**不返回 R18**（§2.4），所以 v1（无 token）天然干净；**接入 OAuth 后必须显式传 `filter.nsfw: false`**，否则登录用户的搜索结果会包含 R18，触发审核风险。
- **隐私**：`GET /v0/me` 会返回 `email`，**不要上传/打点**；token 存 Keychain 并在隐私清单里声明"不用于追踪"。
- **账号删除**：若提供 Bangumi 登录，Apple 要求 App 内能"删除账号"——但 Bangumi 账号不是你的，正确做法是提供**"解除绑定/退出登录"**并在文案里说明"账号数据在 bgm.tv，需前往该站处理"。
- 建议加一个"数据来源"页：

```
本 App 的番剧资料与图片来自 Bangumi 番组计划（bgm.tv），版权归原权利人所有。
Bangumi 与本 App 无隶属关系。
```

---

## 10. LemonPlayer 接入清单

### 10.1 需要的接口（按 v1 / v1.5 分层）

| 优先级 | 接口 | 方法 | 鉴权 | 用途 |
|---|---|---|---|---|
| **v1 必须** | `/v0/search/subjects` | POST | ❌ | 文件名匹配、手动搜索 |
| **v1 必须** | `/v0/subjects/{id}` | GET | ❌ | 详情页 |
| **v1 必须** | `/v0/episodes?subject_id=&type=0` | GET | ❌ | 剧集列表 |
| **v1 必须** | `/calendar` | GET | ❌ | 首页"本周放送" |
| v1 推荐 | `/v0/subjects/{id}/subjects` | GET | ❌ | 相关系列/续作 |
| v1 可选 | `/v0/subjects?type=2&sort=rank&year=` | GET | ❌ | 补番/排行榜页 |
| v1 可选 | `/v0/subjects/{id}/characters` | GET | ❌ | 详情页角色（懒加载） |
| v1 不做 | `/v0/subjects/{id}/persons` | GET | ❌ | 数据量大（实测 123 条/33 KB），价值低 |
| **v1.5** | `GET bgm.tv/oauth/authorize` | GET | — | 登录 |
| **v1.5** | `POST bgm.tv/oauth/access_token` | POST | — | 换/刷 token |
| **v1.5** | `/v0/me` | GET | ✅ | 拿 `username` |
| **v1.5** | `/v0/users/{username}/collections` | GET | 可选 | "我的追番"海报墙 |
| **v1.5** | `/v0/users/-/collections/{subject_id}` | PATCH | ✅ | 收藏状态/评分 |
| **v1.5** | `/v0/users/-/collections/{subject_id}/episodes` | PATCH | ✅ | **单集进度（批量）** |
| v2 | TMDB `search/tv`、`search/movie` | GET | API Key | 兜底 |
| v2 | `bangumi/Archive` release 数据 | 下载 | ❌ | 本地索引，砍掉 95% 请求 |

### 10.2 页面 → 接口映射

| 页面 | 接口调用 | 说明 |
|---|---|---|
| **首页 / 发现** | `GET /calendar`（→ 按 `weekday.id` 分组） | 7 组，每组 `items[]`；图片 `http→https` |
| **我的海报墙** | 未登录：本地 `MediaBinding` + 已缓存 subject<br>登录：`GET /v0/users/{username}/collections?subject_type=2&type=3&limit=50`（翻页） | 登录态直接拿"在看"，`ep_status` 就是"看到第几集" |
| **搜索页** | `POST /v0/search/subjects`（`filter.type=[2]`，`nsfw:false`，`limit=20`） | 结果按 `match` 排序即可，不做二次排序 |
| **番剧详情** | `GET /v0/subjects/{id}`<br>`GET /v0/episodes?subject_id={id}&type=0&limit=200`（翻页）<br>懒加载：`GET /v0/subjects/{id}/subjects`、`/characters` | 详情页首屏**只发 2 个请求** |
| **剧集列表（详情页内）** | 同上 episodes（`type=0` 主列表 + `type=1` "其他"折叠） | 用 `ep` 显示序号，`sort` 只在跨季合并时用 |
| **播放页** | 无网络请求；读本地 `MediaBinding` + 进度 | 进度写本地，登录后异步 PATCH |
| **进度同步** | `PATCH /v0/users/-/collections/{subject_id}/episodes` `{"episode_id":[…],"type":2}` | **一次 PATCH 补 1..N**，幂等；失败静默重试 |
| **排行榜页** | `GET /v0/subjects?type=2&sort=rank&year=YYYY&limit=20` | 可加 `month` 做季度 |
| **设置 / 账号** | `GET /v0/me`、登出、清除缓存、数据来源声明 | |
| **匹配异常处理页** | `POST /v0/search/subjects`（用户手动输入） | 预填解析出的 `baseTitle` |

### 10.3 缓存策略（务必落地，否则会被封）

| 数据 | 存储 | TTL | 理由 |
|---|---|---|---|
| `Subject` 详情 | 磁盘 JSON（按 id） | **7 天** | 服务端缓存 300s，但条目内容几乎不变 |
| `Episode` 列表 | 磁盘 JSON（按 subject_id） | **3 天** | 新番连载中会追加，别设太长 |
| `/calendar` | 磁盘 JSON | **12 小时** | 每日放送按天变化 |
| 搜索结果 | **只放内存**（`NSCache`，上限 50 条） | 会话级 | 搜索结果不适合长期缓存 |
| 用户收藏列表 | 磁盘 JSON（按 username+type） | **10 分钟** | 进度会变；下拉刷新即失效 |
| 图片 | `URLCache` + Nuke 磁盘（≤500 MB，LRU） | 30 天 | 图片 URL 带 `?r=` 版本号，变了自然换 key |
| 配对结果 `MediaBinding` | SwiftData | 永久（用户可重置） | 核心数据，`manual` 永不自动覆盖 |

### 10.4 鉴权必要性结论

- **v1（公开接口）不需要任何 token**，实测 20 个公开端点全部 200（R1–R19）。→ **可以零登录上线**，进度纯本地。
- **只有"跨设备/跨端同步进度 + 在 bgm.tv 上留下记录"才需要 OAuth**。
- 因此建议的里程碑：
  - **M1**：本地媒体库 + 公开接口 + 本地进度 → 可发布；
  - **M2**：OAuth + 进度同步 + "我的追番"海报墙；
  - **M3**：`bangumi/Archive` 本地索引（把首扫时间从小时级降到分钟级）+ TMDB 兜底。

### 10.5 风险清单（按严重度）

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| 1 | **剧集匹配错误**（季/集错位） | 进度记错、播错集，用户直接卸载 | §6 的全流程 + 85/60 分档 + 手动覆盖优先 + 30 条 golden test |
| 2 | **UA 被封 / 无限流数值** | 全线 403/超时，功能不可用 | 固定可识别 UA、全局 1 rps、全量落盘、批量走 Archive、403 时**停止重试**并提示 |
| 3 | **`eps`/`total_episodes` 与实际集数不符** | 列表缺集/多集、进度条错 | 一律以 `/v0/episodes?type=0` 的 `total` 为准（§5.2 有实测表） |
| 4 | `client_secret` 无处安放（无 PKCE） | 内置即泄露；或被迫加后端 | M2 用 Worker 中转；个人版可内置但写明风险 |
| 5 | 搜索接口"实验性" | 字段/行为随时变 | 全可选解码 + 远程开关降级到"手动搜索" |
| 6 | 图片 `http://`（旧版/日历） | ATS 拦截，图片全白 | 统一 `http→https` 改写（`BGMImages.safe`） |
| 7 | `date` 为 `null`/`""` | Decodable 崩溃 | `String?` + 容错（§7.2） |
| 8 | 商用授权不明（无条款） | 上架收费后的法务不确定性 | 关于页声明"数据来源/非官方"；规模化前发 issue 询问 |

---

## 附录 A：实测原始响应（节选，2026-11-03）

### A.1 `GET /v0/subjects/12`（3 512 B，节选）

```json
{"date":"2002-04-02","platform":"TV",
 "images":{"small":"https://lain.bgm.tv/r/200/pic/cover/l/c2/0a/12_q23bZ.jpg",
           "grid":"https://lain.bgm.tv/r/100/pic/cover/l/c2/0a/12_q23bZ.jpg",
           "large":"https://lain.bgm.tv/pic/cover/l/c2/0a/12_q23bZ.jpg",
           "medium":"https://lain.bgm.tv/r/800/pic/cover/l/c2/0a/12_q23bZ.jpg",
           "common":"https://lain.bgm.tv/r/400/pic/cover/l/c2/0a/12_q23bZ.jpg"},
 "summary":"…","name":"ちょびっツ","name_cn":"人形电脑天使心","tags":[…30 项…],
 "infobox":[…29 项…],"rating":{"rank":947,"total":…,"count":{"1":…,"10":…},"score":7.5},
 "total_episodes":27,"collection":{"doing":951,"collect":9023,…},"id":12,"eps":27,
 "meta_tags":["科幻","TV","恋爱","日本","漫画改","日常"],
 "volumes":0,"series":false,"locked":false,"nsfw":false,"type":2}
```

### A.2 `GET /v0/episodes?subject_id=12&type=0&limit=3`（节选）

```json
{"data":[{"airdate":"2002-04-03","name":"ちぃ 目覚める","name_cn":"叽，觉醒了",
          "duration":"24m","desc":"脚本：大川七瀬\t絵コンテ：浅香守生\r\n…",
          "ep":1,"sort":1,"id":1027,"subject_id":12,"comment":36,
          "type":0,"disc":0,"duration_seconds":1440}, …],
 "total":24,"limit":3,"offset":0}
```

### A.3 `GET /v0/subjects/411427`（SPY S2）第 1 集 —— **`sort` 续编号的实证**

```
episodes type=0: total=12
first: ep=1, sort=26     ← 本地 "S02E01" 必须匹配 ep，不是 sort
```

### A.4 `POST /v0/search/subjects`（`keyword="间谍过家家"`，`limit=5`）

```
total=27
329906 2022-04-09 TV      SPY×FAMILY                 间谍过家家
373267 2022-10-01 TV      SPY×FAMILY 第2クール        间谍过家家 第2部分
411427 2023-10-07 TV      SPY×FAMILY Season 2        间谍过家家 第二季
498378 2025-10-04 TV      SPY×FAMILY Season 3        间谍过家家 第三季
411428 2023-12-22 剧场版   劇場版 SPY×FAMILY CODE: White  剧场版 间谍过家家 代号：白
```

### A.5 `GET /calendar`（节选）

```json
[{"weekday":{"en":"Mon","cn":"星期一","ja":"月耀日","id":1},
  "items":[{"id":390200,"url":"http://bgm.tv/subject/390200","type":2,
            "name":"…","name_cn":"…","summary":"","air_date":"2026-10-05","air_weekday":1,
            "rating":{"total":8,"count":{…},"score":3.6},
            "images":{"large":"http://lain.bgm.tv/pic/cover/l/1c/b4/390200_Z9jPp.jpg", …},
            "collection":{"doing":1}}, …]}]
```

→ 7 个 weekday；`items` 元素 keys 实测只有 `id,url,type,name,name_cn,summary,air_date,air_weekday,rating,images,collection`。

### A.6 `GET /v0/me`（无 token）

```json
{"title":"Unauthorized","details":{"path":"/v0/me","method":"GET"},
 "request_id":"a54bf093cefdd496-LHR","description":"need Login"}
```

---

## 附录 B：待验证清单（接真账号/真设备时必须逐条确认）

| # | 项 | 为什么重要 | 建议验证方式 |
|---|---|---|---|
| B1 | `PATCH /v0/users/-/collections/{subject_id}/episodes` 的真实 body/204 行为 | 进度同步的核心 | 用 `next.bgm.tv/demo/access-token` 生成的 token 抓包 |
| B2 | PATCH 后 `ep_status` 是否立即回算、`type` 是否被自动改成"在看" | 影响 UI 乐观更新 | 同上，PATCH 后立即 GET 收藏 |
| B3 | refresh_token 是否**轮换并失效旧的** | 决定并发刷新策略 | 连续刷新两次，看旧 refresh 是否 400 |
| B4 | 401 之外，token 过期是否可能返回 403 | 影响登出判定 | 用过期 token 请求 `/v0/me` |
| B5 | 429 的真实触发阈值与响应体 | 限流退避策略 | 谨慎压测（本文只压到 40 并发未触发，**不建议加压**） |
| B6 | `GET /v0/users/{username}/collections` 的 `subject` 是否始终带 `images` | 海报墙渲染 | 翻 5 页观察 |
| B7 | 搜索接口 `filter.type` 多值是否真为"或" | 跨类型搜索 | `[2,6]` 查询观察结果 |
| B8 | 是否存在 OAuth 撤销/revoke 端点 | 账号解绑 | 查 `bgm.tv` 开发者平台文档区 |
| B9 | 是否有官方商用授权渠道 | 商业化 | `bangumi/api` 开 issue 询问 |
| B10 | iOS `URLSession` 对 `lain.bgm.tv` 的 ATS/HTTP2 表现 | 图片加载 | 真机跑一次海报墙 |

---

**文档维护建议**：接真账号验证 B1–B5 后，把 §4.5、§4.6 的【文档】标记改为【实测】，并更新本文顶部的核对时间。
