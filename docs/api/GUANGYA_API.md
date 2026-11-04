# 光鸭云盘（GuangYaPan）非官方 REST API 参考

> 面向 **LemonPlayer（Swift / SwiftUI 原生 iOS 播放器）** 的可落地实现说明。
>
> ⚠️ **本文件不是官方文档。** 光鸭云盘（产品站 `guangya.net` / `guangyupan.com`）未公开开发者文档，以下内容全部来自对社区已跑通实现的**源码逐行核对**，并逐条标注来源链接。
> 标 **【待验证】** 的条目表示：在可获取到的参考实现中**没有可证实的依据**，禁止直接照抄，必须接真机/真账号抓包确认。
>
> 文档数据核对时间：2026-11-03。参考实现版本：ShukeBta/Guangyadisk 插件 v2.2.3、AList `drivers/guangyapan`（main）、PyPI `guangyaclient` 0.0.2、npm `guangya` 0.1.2。

---

## 0. 来源清单（S1–S12）

| 编号 | 来源 | 用途 |
|---|---|---|
| S1 | [guangya_client.py](https://github.com/ShukeBta/Guangyadisk/blob/main/plugins.v2/shukguangyadisk/guangya_client.py)（[raw](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)） | 公共请求头、设备码 OAuth2、token 刷新 |
| S2 | [guangya_api.py](https://github.com/ShukeBta/Guangyadisk/blob/main/plugins.v2/shukguangyadisk/guangya_api.py)（[raw](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)） | 文件 CRUD、列表字段映射、上传/秒传、下载 |
| S3 | [\_\_init\_\_.py](https://github.com/ShukeBta/Guangyadisk/blob/main/plugins.v2/shukguangyadisk/__init__.py)（[raw](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)） | `/stream` `/browse` `/webdav` 路由、扫码轮询逻辑、用户信息字段兜底 |
| S4 | [webdav_provider.py](https://github.com/ShukeBta/Guangyadisk/blob/main/plugins.v2/shukguangyadisk/webdav_provider.py)（[raw](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/webdav_provider.py)） | Range 转发、流式代理响应头 |
| S5 | [alist drivers/guangyapan/driver.go](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) | 列表/下载/上传/任务轮询、限流间隔、401/403 刷新 |
| S6 | [alist drivers/guangyapan/types.go](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) | **响应结构体字段名（权威）** |
| S7 | [alist drivers/guangyapan/meta.go](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/meta.go) | 配置项、`orderBy` 取值范围 |
| S8 | [alist drivers/guangyapan/offline.go](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/offline.go) | 离线下载/分享等边缘接口 |
| S9 | [AList 文档：GuangYaPan](https://alistgo.com/zh/guide/drivers/guangyapan.html) | 登录方式说明、令牌自动保存 |
| S10 | [DDSRem-Dev/guangyaclient](https://github.com/DDSRem-Dev/guangyaclient)（[client.py](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) / [tools.py](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/tools.py) / [const.py](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/const.py)） | 文件详情、回收站、分享、gcid 算法、traceparent |
| S11 | [intellecat/guangya-node](https://github.com/intellecat/guangya-node)（[client.ts](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) / [types.ts](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts) / [oss.ts](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/oss.ts)）+ [npm guangya](https://www.npmjs.com/package/guangya) | **FileInfo / FileDetail 字段表（权威）**、OSS 签名算法、错误码 112 |
| S12 | [Guangyadisk README](https://github.com/ShukeBta/Guangyadisk/blob/main/README.md) | 架构说明（注意：其中 `client_id=guangya_web` 与源码不符，见 §1.3） |

---

## 1. 概览

### 1.1 域名与 base URL

所有实现中出现过的域名（均可在源码中直接读到）：

| 用途 | Base URL | 来源 |
|---|---|---|
| 账户 / OAuth2 / 用户 | `https://account.guangyapan.com` | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) · [S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) · [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) |
| 业务 API（文件/资产） | `https://api.guangyapan.com` | 同上 |
| Web 站点（`Referer` / `Origin` 用） | `https://www.guangyapan.com` | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) · [S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |
| 上传对象存储（动态下发） | `data.fullEndPoint`（每次 `get_res_center_token` 返回） | [S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) · [S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts) |
| 下载 CDN（动态下发） | `data.signedURL` / `data.downloadUrl` | [S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) · [S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) |

> **域名澄清**：任务简报里写的是 `guangya.net`。`guangya.net` 确实是产品对外站点（Guangyadisk README 的致谢链接指向它），但**四个参考实现的所有 HTTP 请求目标都是 `guangyupan.com`**，没有任何一份实现请求过 `guangya.net`。
> 结论：**API 走 `guangyupan.com`**；`guangya.net` 上是否存在 API 端点 — **【待验证】**。
> 来源：[S12](https://github.com/ShukeBta/Guangyadisk/blob/main/README.md)、[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)

### 1.2 两套响应信封（**非常重要**）

1. **账户域（`account.guangyapan.com`）= 扁平 OAuth2 风格**，无 `data` 包裹：
   `access_token` / `refresh_token` / `token_type` / `expires_in` / `sub` / `error` / `error_code` / `error_description`。
   依据：[S6 `tokenResp`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) 的 struct tag 全部是顶层字段；[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) 直接 `result.get("device_code")` / `result.get("access_token")`（无 `.data`）。
2. **业务域（`api.guangyapan.com`）= `{code, msg, data}` 信封**：
   ```json
   { "code": 0, "msg": "success", "data": { } }
   ```
   成功判据（各实现不统一，建议两者都接受）：
   - `code == 0`
   - 或 `msg == "success"`（不区分大小写；[S8 `isSuccessMsg`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/offline.go) 甚至允许 `msg == ""`）
   失败：`code != 0` 且 `msg` 为中文错误文案（如 `参数错误`）。
   依据：[S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go)、[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S11 types.ts `ApiResponse`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts)

### 1.3 公共参数（真实字段名）

| 字段 | 值 / 形态 | 说明 | 来源 |
|---|---|---|---|
| `client_id` | `aMe-8VSlkrbQXpUR` | 三份实现完全一致，**这是唯一可信值** | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) `DEFAULT_CLIENT_ID`、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) `defaultClient`、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) `CLIENT_ID` |
| `device_id` / `did` / `X-Device-Id` | 32 位小写 hex（`md5(16 random bytes)` 或 `uuid4().hex`，去连字符） | 同一值出现在 header `did` 与 `x-device-id` 中，且**与 token 绑定** | [S5 `normalizeDeviceID`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S10 `generate_did`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/tools.py)、[S1 `_generate_device_id`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) |
| `dt` / `Dt` | `"4"` | 业务 API header | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| `x-client-version` | `"0.0.1"` | 账户域 header | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) |
| `x-sdk-version` | `"9.0.2"` | 账户域 header | 同上 |
| `x-protocol-version` | `"301"` | 账户域 header | 同上 |
| `x-device-model` | `chrome%2F147.0.0.0`（URL 编码的 `chrome/147.0.0.0`） | 账户域 header | 同上 + [S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |
| `x-device-name` | `"PC-Chrome"` | 账户域 header | 同上 |
| `x-device-sign` | `wdi10.<device_id><32位随机hex>` | 形如 `wdi10.` + did + 32 hex；**非签名校验，随机值即可**（三份实现均用随机数/占位 `xxx…`） | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)（`xxxxxxxx…` 占位）、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)（`token_hex(16)`）、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |
| `x-os-version` | `Win32` / `MacIntel` | 平台标识（不同实现取值不同，均可用） | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) vs [S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| `x-platform-version` / `x-provider-name` / `x-net-work-type` | `"1"` / `"NONE"` / `"NONE"` | 常量 | 同上 |
| `traceparent` | `00-<32hex>-<16hex>-01`（W3C Trace Context） | 两份 JS/Py SDK 每个数据面请求都带；插件与 AList 未带 | [S10 `generate_traceparent`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/tools.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |
| `x-captcha-token` | `captcha_token` | 仅短信登录链路需要 | [S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) |
| `x-action` | `"401"` | **刷新 token 时**带上（两份实现一致） | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |

> ⚠️ **S12 README 的配置表把 Client ID 写成 `guangya_web`**，与 `guangya_client.py` 的 `DEFAULT_CLIENT_ID = "aMe-8VSlkrbQXpUR"` 冲突。以**源码三处一致的 `aMe-8VSlkrbQXpUR`** 为准，README 该行为过期信息。
> 来源：[S12](https://github.com/ShukeBta/Guangyadisk/blob/main/README.md) vs [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)

### 1.4 时间戳 / 签名机制

**结论：普通 REST 请求没有 `sign` 参数，也没有 `timestamp`/`nonce` 参数。**

- 逐条核对四份实现的所有请求体（`get_file_list` / `rename` / `delete_file` / `get_res_center_token` / `get_res_download_url` 等），字段全部为业务字段，**不存在** `sign`、`ts`、`timestamp`、`nonce`、`appkey` 之类的签名参数。
  来源：[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts)
- 认证仅靠 `Authorization: Bearer <access_token>` + `did`/`dt` header。
- **唯一存在的签名有两处**：
  1. **下载**：`signedURL` 由服务端生成，客户端**只透传不签名**（§5）。
  2. **上传**：阿里云 OSS V1 签名（§4.6）。这也是**唯一对客户端时钟敏感的环节**（`x-oss-date` = HTTP Date 格式的当前时间，需与真实时间偏差在 OSS 允许窗口内）。算法见 §4.6。

---

## 2. 认证

### 2.1 设备码 OAuth2（扫码登录）— 播放器首选

只有 [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) + [S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py) 实现了这条链路，标准 RFC 8628 device flow 变体。

#### ① 申请设备码 / 二维码

```http
POST https://account.guangyapan.com/v1/auth/device/code
Content-Type: application/json
（无 Authorization）

{ "scope": "user", "client_id": "aMe-8VSlkrbQXpUR" }
```

**真实响应（2026-11-03 实测）**：

```json
{
  "device_code": "AWrp64wt9HmyQUIZBmaFo3C4oJpX2EH4MoOPYuj3UgJ-6arEgA",
  "user_code": "AWrp64zaRXBZp3c0Kg",
  "expires_in": 120,
  "interval": 2,
  "verification_url": "https://account.guangyapan.com/__/auth/device/?client_id=...&scope=user%20profile%20sso%20offline",
  "verification_uri_complete": "https://account.guangyapan.com/__/auth/device/?client_id=...&scope=...&user_code=AWrp64zaRXBZp3c0Kg"
}
```

| 字段 | 含义 | 备注 |
|---|---|---|
| `device_code` | 轮询用的设备码（长字符串，**不要展示给用户**） | ✅ 实测 |
| `user_code` | 向用户展示的短码 | ✅ 实测 |
| `verification_url` | 授权页地址 | ✅ 实测，**注意是 `url` 不是 `uri`**（社区文档写作 `verification_uri`，与真实响应不符） |
| `verification_uri_complete` | 带 `user_code` 的授权页地址 | ✅ 实测，二维码直接用这个 |
| `expires_in` | 有效期秒数，**实测 120**（社区实现按 300 兜底） | ✅ 实测 |
| `interval` | 轮询间隔秒数，**实测 2**（社区实现按 5 兜底） | ✅ 实测 |

**二维码怎么来**：插件没有调用任何"返回 PNG/SVG"的接口，而是把 `verification_uri_complete` 交给前端渲染二维码。
→ 因此 **LemonPlayer 侧需要自己用 `CoreImage.CIFilter.qrCodeGenerator` 把 `verification_uri_complete`（或 `verification_uri + "?user_code=" + user_code`）画成二维码**。
依据：[S3 `get_qrcode`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py) 返回值中没有图片字段，只有 `user_code` / `verification_uri` / `verification_uri_complete`。

> **2026-11-05 复核（WSL 直连实测）**
> - `POST /v1/auth/device/code`（JSON body）**仍返回 200**，字段与上表一致：`expires_in=120`、`interval=2`。
> - `POST /v1/auth/token`（未扫码）返回 **HTTP 400** + `error=authorization_pending`、`error_code=4050`、`error_description=Precondition Required`；`details[].message = "Authorizing"`。客户端只认 `authorization_pending` 即可。
> - ⚠️ **API 域名不承载授权网页**：`account.guangyapan.com/__/auth/device/`（含 `verification_uri_complete`）返回 404（nginx，且 `Accept: text/html` 也一样）。授权页应由 web 域名（`www.guangyupan.com`）提供；客户端需保留「改用网页域名打开」兜底。
> - `api.guangyapan.com` 对任意路径返回 **410 Gone**（疑似需要 web 端专用头/或已迁移），不要用该域名做登录。

#### ② 轮询状态 / 换 token（同一个接口）

```http
POST https://account.guangyapan.com/v1/auth/token
Content-Type: application/json

{
  "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
  "device_code": "<device_code>",
  "client_id": "aMe-8VSlkrbQXpUR"
}
```

| 情况 | 响应 | 处理 | 来源 |
|---|---|---|---|
| 用户还没扫码/没确认 | `{"error": "authorization_pending", ...}`（HTTP 4xx，插件用 `treat_http_error_as_response` 把错误体当正常响应解析） | 继续按 `interval` 轮询 | [S1 `poll_device_code`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) |
| 授权成功 | 扁平 token 响应，含 `access_token`、`refresh_token`、`expires_in`、`token_type`、`sub` | 落库/存 Keychain | [S6 `tokenResp`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) |
| 设备码过期 | `{"error": "expired_token", ...}` — **【待验证】**（标准 RFC 用这个值，但代码里只显式匹配了 `authorization_pending`） | 重新申请设备码 | 代码中未见 —【待验证】 |

> **实现要点**：`authorization_pending` 是**以 HTTP 错误状态 + JSON error 体**返回的（插件必须显式把 4xx 响应体当数据解析才能读到）。Swift 侧不要用 `URLSession` 默认的"非 2xx 直接抛错"逻辑，必须把 4xx body 反序列化后判断 `error` 字段。
> 依据：[S1 `_request(treat_http_error_as_response=True)`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)

#### ③ 刷新 access_token

```http
POST https://account.guangyapan.com/v1/auth/token
Content-Type: application/json
x-action: 401
x-client-id: aMe-8VSlkrbQXpUR
x-device-id: <device_id>
（其余 x-* 账户头同 §1.3）

{
  "grant_type": "refresh_token",
  "refresh_token": "<refresh_token>",
  "client_id": "aMe-8VSlkrbQXpUR"
}
```

成功：新 `access_token` + 新 `refresh_token`（`refresh_token` **可能轮换**，必须回存最新值）。
依据：[S1 `refresh_access_token`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S5 `refreshToken`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)（带 `x-action: 401`）

失败判定（插件用的关键字，可复用为"需要重新扫码"的判据）：
`unauthenticated` / `无效token` / `authorize failed` / `认证失败` / `invalid_grant` / `invalid token` / `invalid_token` / `token expiry`。
依据：[S1 `_is_auth_invalid_result`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)

#### ④ 账号密码登录（2026-11-05 发现）

```http
POST https://account.guangyapan.com/v1/auth/signin
Content-Type: application/json

{ "client_id": "aMe-8VSlkrbQXpUR", "username": "<手机号/邮箱/用户名>", "password": "<密码>" }
```

- 字段名必须是 **`username`**（用 `account` / `email` / `phone` 会返回 `username can not be empty`）。
- 用假密码实测：HTTP 400 `{"error":"invalid_account_or_password","error_code":4022,"error_description":"verification failed"}` → 接口真实存在。
- 成功响应应为 token（`access_token` / `refresh_token` / `expires_in`）；客户端用**宽容解析**兼容顶层与 `data` 嵌套两种形态。
- ⚠️ 未用真实凭据验证成功路径；**LemonPlayer rc21 起提供「账号密码登录」通道**，失败会映射为「账号或密码错误」。

### 2.2 短信验证码登录（备选，4 步）

AList 与两份 Python/TS SDK 都实现，链路一致：

| 步 | 请求 | 关键字段 | 来源 |
|---|---|---|---|
| 1 | `POST https://account.guangyapan.com/v1/shield/captcha/init` | body: `{client_id, action:"POST:/v1/auth/verification", device_id, meta:{phone_number}}` → `captcha_token` | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S5 `ensureCaptchaToken`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| 2 | `POST https://account.guangyapan.com/v1/auth/verification` | header `x-captcha-token`；body `{phone_number, target:"ANY", client_id}` → `verification_id` | 同上 |
| 3 | `POST https://account.guangyapan.com/v1/auth/verification/verify` | body `{verification_id, verification_code, client_id}` → `verification_token` | 同上 |
| 4 | `POST https://account.guangyapan.com/v1/auth/signin` | header `x-captcha-token`；body `{verification_code, verification_token, username, client_id}` → token 响应 | 同上 |

- 手机号格式：`"+86 13800138000"`（**带空格**，AList 的 `normalizePhoneE164` 刻意拼成 `+86 ` + 号码，注释说是"匹配浏览器 payload"）。
  来源：[S5 `normalizePhoneE164`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)
- 可能返回 `captcha_invalid` / `captcha_token expired`，此时需重新第 1 步。
  来源：[S5 `requestVerificationID`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)

### 2.3 用户信息

```http
GET https://account.guangyapan.com/v1/user/me
Authorization: Bearer <access_token>
```

- 可用作 **token 有效性探针**：AList 以"`sub` 非空"判定有效。
  来源：[S5 `validateToken`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S6 `userMeResp{Sub}`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go)
- 方法：**GET 与 POST 都有人用**（[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) 用 GET；[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) 用 POST）。建议用 GET。
- 除 `sub` 外的字段（昵称、手机号、VIP）**没有任何实现能确证**：插件用 `_pick_first` 在 `name/user_name/username/nickname/nickName/phone/mobile/...` 等 10 个候选键里猜。
  → **【待验证】**，禁止在 Swift 模型里硬编码这些键。
  依据：[S3 `_get_config` 中的 `_pick_first` 列表](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)

### 2.4 空间容量

```http
POST https://api.guangyapan.com/nd.bizassets.s/v1/get_assets
Authorization: Bearer <access_token>
did: <device_id>
dt: 4
Content-Type: application/json

{}
```

响应（`{code,msg,data}` 信封）：

| 字段 | 含义 | 置信度 | 来源 |
|---|---|---|---|
| `data.totalSpaceSize` | 总容量（**字节**，实现按整数直接当字节用） | ✅ 已核实 | [S2 `usage()`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) 直接 `data.get("totalSpaceSize")` |
| `data.usedSpaceSize` | 已用容量 | ✅ 已核实 | 同上（`available = total - used`） |
| `data.freeSpaceSize` | 剩余容量 | ⚠️ 插件兼容候选 | [S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py) |
| `data.fileCount` / `data.totalFileCount` | 文件数 | ⚠️ 插件兼容候选 | 同上 |
| `data.vipExpireTime` | 会员到期时间 | ⚠️ 插件兼容候选 | 同上 |

> 会员等级/VIP 字段：`vip_level`、`vipLevel`、`memberType`、`expireTime` 等均为插件**猜测键**，**【待验证】**。单位是"字节"还是"KB"没有文档，但插件直接用 `total - used` 当字节并喂给 MoviePilot，按字节处理最可能正确 —【待验证】。

---

## 3. 文件接口（只读侧重点）

### 3.1 路径前缀的两种写法（先看这个）

同一批业务接口在真实实现中出现了两种前缀：

- 带网关前缀：`https://api.guangyapan.com/nd.bizuserres.s/v1/...`（[S1/S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) 的写操作/详情/下载）
- 无前缀：`https://api.guangyapan.com/userres/v1/file/get_file_list`（[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) 与 [S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) 的**列表接口**）

两份实现都能跑通（都带真实联调记录），推测网关对 `v1` 路径做了兜底路由。**建议统一用 `/nd.bizuserres.s/v1/...`（三方一致）**，列表接口若 404 再回退到 `/userres/v1/...`。
两种写法是否完全等价 — **【待验证】**。

### 3.2 目录列表（核心）

```http
POST https://api.guangyapan.com/nd.bizuserres.s/v1/file/get_file_list
Authorization: Bearer <access_token>
did: <device_id>
dt: 4
Content-Type: application/json
```

请求体：

| 字段 | 类型 | 说明 | 来源 |
|---|---|---|---|
| `parentId` | string | `""` = 根目录；`"*"` = **全盘**（跨目录聚合，用于"视频/图片/文档"聚合视图）；其它 = 目录 fileId | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)（`parent_id or ""`）、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)（`parent_id="*"`） |
| `page` | int | **从 0 开始** | [S2 `_iter_parent_items`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) `page = 0` 递增；[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) 默认 0 |
| `pageSize` | int | 实现用 100 / 50 | [S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) `PageSize` 默认 100 |
| `orderBy` | int | 排序字段。`3` = 按时间（README 与默认值）；`10` = 回收站默认；`0..4` 为合法区间 | [S7](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/meta.go) `options:"0,1,2,3,4"`；[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) 回收站用 `order_by=10` |
| `sortType` | int | **`0` = 升序，`1` = 降序** | [S10 docstring](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) "0 升序，1 降序"；[S7](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/meta.go) `options:"0,1"` 默认 1 |
| `fileTypes` | int[] | 类型过滤：`1` 图片、`2` 视频、`3` 音频、`4` 文档、`5` 压缩包、`9` BT 种子；`[]` = 全部 | [S10 const.py](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/const.py) `FILE_TYPE` |
| `resType` | int | 资源类型过滤；聚合视图传 `1`（文件） | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) `res_type=1`；语义 —【待验证】 |
| `dirType` | int | `4` = **回收站** | [S2 `_iter_recycle_items`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) |
| `needPlayRecord` | bool | 请求播放进度记录（视频聚合视图用） | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts) |

> ⚠️ **`sortType` 有冲突说法**：S12 README 写 "升序(1)/降序(2)"，而两份 SDK 的代码注释/取值域都是 `0/1`。以 `0/1` 为准（`meta.go` 的 `options:"0,1"` 是硬校验）。
> 来源：[S7](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/meta.go) vs [S12](https://github.com/ShukeBta/Guangyadisk/blob/main/README.md)

响应：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "total": 1234,
    "list": [ /* FileItem[] */ ]
  }
}
```

**分页终止条件**（三份实现一致的写法，直接照抄）：
`len(list) < pageSize` **或** `已累计条数 >= total` → 停止；否则 `page += 1`。
来源：[S2 `_iter_parent_items`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S5 `List`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)

### 3.3 `FileItem` 字段表（列表项 / 搜索结果项）

字段名以 [S11 types.ts `FileInfo`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts) + [S6 `fileItem`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) 交叉核对：

| 字段 | 类型 | 含义 | 置信度 |
|---|---|---|---|
| `fileId` | string | 文件/目录唯一 ID（字符串，**不要当 Int64 解析**，实现里既有 string 也有 int 传参） | ✅ |
| `parentId` | string | 父目录 ID（根目录下为空串） | ✅ |
| `fileName` | string | 名称（含扩展名） | ✅ |
| `fileSize` | int64 | 字节数；**目录通常为 0 或缺省** | ✅ |
| `resType` | int | **`2` = 目录，非 2 = 文件**（这是唯一的类型判据） | ✅ [S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) `item.ResType == 2`、[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) `item.get("resType") == 2` |
| `fileType` | int | 业务类型（1 图片 / 2 视频 / 3 音频 / 4 文档 / 5 压缩包 / 9 BT） | ✅ 枚举值见 [const.py](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/const.py)，与 `fileTypes` 过滤参数同源 |
| `dirType` | int | 目录类型（`4` 出现在回收站语境） | ⚠️ 语义【待验证】 |
| `ext` | string | 扩展名 | ⚠️ 仅 S11 类型定义 |
| `mineType` | string | MIME 类型 — **注意这是原字段名的拼写（`mine`，不是 `mime`）** | ⚠️ 仅 S11 类型定义；**不要自行改成 `mimeType`** |
| `gcid` | string | 内容哈希（秒传用，§4.6） | ✅ [S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts) |
| `md5` | string | 文件 MD5 | ⚠️ 仅 S11 类型定义 |
| `ctime` / `utime` | int64 | 创建 / 更新时间（**Unix 秒**，非毫秒） | ✅ [S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) `time.Unix(v,0)`；[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) `int(item.get("utime") or item.get("updateTime") or 0)` |
| `thumbnail` | string | **缩略图地址** | ⚠️ 仅 S11 类型定义；URL 形态、是否需鉴权、有无尺寸参数 — **【待验证】** |
| `fullParentIds` | string | 完整祖先 ID 链 | ⚠️ 仅 S11 类型定义，分隔符【待验证】 |
| `auditStatus` | int | 审核状态 | ⚠️【待验证】 |
| `depth` | int | 层级深度 | ⚠️【待验证】 |

> **缩略图结论**：列表项**确实有 `thumbnail` 字段名**（S11 类型定义），但四份实现里**没有任何一份真正读取/展示它**，所以它的取值形态（完整 URL / 相对路径 / 是否需要带 token 签名）无法核实 — **【待验证】**。LemonPlayer 的海报墙/缩略图**建议先不依赖该字段**，改用视频首帧或本地生成。
> 来源：[S11 types.ts](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts)、[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)（`_build_file_item_from_api` 未使用 thumbnail）

### 3.4 文件详情（推荐：拿时长/分辨率/编码）

```http
POST https://api.guangyapan.com/nd.bizuserres.s/v1/file/get_file_detail
Authorization: Bearer <access_token>

{ "fileId": "<file_id>" }
```

响应 `data` 结构（依据 [S11 `FileDetail`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/types.ts)）：

```jsonc
{
  "fileInfo": { /* 同 §3.3 FileInfo */ },
  "location": "…",                      // ⚠️ 含义【待验证】
  "picInfo": { "width": 0, "height": 0, "previewUrl": "…" },  // 图片类；可为 null
  "videoResource": [
    {
      "gcid": "…",
      "info": {
        "resolution": { "width": 1920, "height": 1080 },
        "duration": 0,        // ⚠️ 单位（秒/毫秒）【待验证】
        "bitRate": 0,
        "frameRate": 0,
        "videoCodec": "…",    // ⚠️ 取值枚举【待验证】（h264/hevc/…）
        "audioCodec": "…",
        "videoType": "…",
        "resolutionName": "…",  // 如 "1080p"
        "mimeType": "…",        // 注意：这里是 mimeType（详情内层），而 FileInfo 里是 mineType
        "defaultResolution": true
      }
    }
  ]
}
```

> **重要提醒**：
> - AList 与 ShukeBta 插件**都没有**调用 `get_file_detail`（它们只靠列表项 + 文件名后缀推断），所以这个接口的**真实返回字段只有 S11 的类型定义作依据**，没有第二份实现交叉验证。**整段按【待验证】对待**，播放器应实现"详情接口失败 → 退化为用列表项 + `ext` 判类型"。
> - 也就是说：**"文件详情"这条路径的字段名，目前只有单一来源。**

### 3.5 搜索

**四个参考实现中不存在任何搜索接口调用。**

- AList 的 `drivers/guangyapan` 只实现了 `List/Link/MakeDir/Rename/Remove/Move/Copy/Put`，没有实现搜索能力。
  来源：[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)
- 两份 SDK 和插件也没有 `search` 相关方法。
  来源：[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts)

**结论**：服务端搜索接口 **【待验证】（很可能不存在或未公开）**。
**可落地的替代方案**：
1. 用 `parentId: "*"` + `fileTypes: [2]` 做"全盘视频聚合列表"（**已核实可用**），在**客户端本地**对该列表做名称/拼音过滤，充当"搜索"。
   来源：[S10 `fs_video_list`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts)
2. 首页/资料库做**逐层懒加载 + 本地索引**（详情见 §7）。注意全盘聚合是**全库扫描**（每次 `pageSize` 条），大账号下开销高。

### 3.6 写操作（简要）

| 操作 | method + path | 关键 body | 备注 | 来源 |
|---|---|---|---|---|
| 新建文件夹 | `POST /nd.bizuserres.s/v1/file/create_dir` | `{parentId, dirName, failIfNameExist?:bool}` → `data.fileId` | `failIfNameExist` 默认 false | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) |
| 重命名 | `POST /nd.bizuserres.s/v1/file/rename` | `{fileId, newName}` | 无 data | 同上 |
| 移动 | `POST /nd.bizuserres.s/v1/file/move_file` | `{fileIds:[...], parentId}` → `data.taskId` | 异步，需轮询 | [S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| 复制 | `POST /nd.bizuserres.s/v1/file/copy_file` | `{fileIds, parentId}` → `data.taskId` | 异步 | 同上 |
| 删除（→ 回收站） | `POST /nd.bizuserres.s/v1/file/delete_file` | `{fileIds:[...]}` → `data.taskId` | 传入**普通** fileId = 移入回收站 | [S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) "传入普通文件 ID 时移入回收站，传入回收站文件 ID 时从回收站永久删除" |
| 删除（彻底） | `POST /nd.bizuserres.s/v1/file/delete_file` | `{fileIds:[回收站里的 fileId]}` | **同一个接口**，靠"ID 来自回收站列表"区分 | 同上 + [S2 `_purge_from_recycle`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) |
| 回收站列表 | `POST /nd.bizuserres.s/v1/file/get_file_list` | `{..., dirType:4, orderBy:10, sortType:0}` | 走列表接口 | [S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) |
| 回收站还原 | `POST /nd.bizuserres.s/v1/file/recycle_file` | `{fileIds:[...]}` | | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |
| 清空回收站 | `POST /nd.bizuserres.s/v1/file/clear_recycle_bin` | 空体 | | 同上 |

**异步任务轮询（写操作通用）**：

```http
POST https://api.guangyapan.com/nd.bizuserres.s/v1/get_task_status
{ "taskId": "<task_id>" }
```

`data.status` 语义（据 [S2 `_wait_task_done`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) 与 [S5 `waitTaskDone`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)）：

| status | 含义 | 依据 |
|---|---|---|
| `2` | **成功** | 两份实现都以 `== 2` 判定成功 |
| `0, 1, 3` | 进行中 / 需继续等 | S2 把 `0,1,3,145,146,147,155,163` 一律当"继续等"；S5 把 `-1, 3` 当失败 |
| `145, 146, 147, 155, 163` | 任务处理中（这些数也出现在 `code` 里，见 §6） | S2 |
| 其它 | 失败 | 两份实现不一致（S5 视 `-1/3` 为失败，S2 视 `3` 为进行中）→ **建议：轮询固定次数（如 30×300ms ~ 300×1s）后放弃**，不要死等 |

补充：`get_file_info_by_task_id` 也可作为"任务是否已落地为文件"的判据（`data.fileId` 非空即成功）。
来源：[S2 `_wait_task_done`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S5 `waitUploadTaskInfo`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)

### 3.7 上传（秒传 / 分片，简要）

```
1) POST /nd.bizuserres.s/v1/get_res_center_token
   { "capacity": 2, "name": "<文件名>", "res": { "fileSize": <字节>, "md5": "<可选>" }, "parentId": "<dirId 或 ''>" }
   → data: { taskId, bucketName, objectPath, endPoint, fullEndPoint, region, provider,
             creds: { accessKeyID, secretAccessKey, sessionToken, expiration }, gcid? }
```

- **< 1 MB**：`res.md5` 传 **base64(MD5(内容))**（不是 hex！），然后单次 `PUT {fullEndPoint}/{objectPath}`。
  来源：[S10 `file_upload`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) `b64encode(md5(...))`、[S11 `fileUpload`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts)
- **≥ 1 MB**：先 `POST /nd.bizuserres.s/v1/check_can_flash_upload {taskId, gcid}` 判秒传：
  `data.canFlashUpload == true` → 直接轮询 `get_info_by_task_id` 收工。
  否则 OSS 分片：`POST {fullEndPoint}/{objectPath}?uploads` → 逐片 `PUT …?partNumber=N&uploadId=…`（5 MB/片）→ `POST …?uploadId=…` 合并。
  来源：[S11 oss.ts `cdnUpload`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/oss.ts)、[S10 `cdn_upload`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S5 `multipartUploadToOSS`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)
- 完成判定：轮询 `POST /nd.bizuserres.s/v1/file/get_info_by_task_id {taskId}`，`data.fileId` 非空即成功；`msg == "文件上传中"` 表示还在处理（两份实现都显式 sleep 2s 重试）。
  来源：[S10 `file_upload`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11 `#pollUploadInfo`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts)
- `code == 156` = 该任务已走秒传/已存在（插件据此直接等任务）。
  来源：[S2 `_upload_single_file`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)

**gcid 算法（秒传内容哈希，已核实）** — [S10 tools.py](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/tools.py)：

```
按文件大小选分块：
  size <= 128 MB   → 256 KB
  size <= 256 MB   → 512 KB
  size <= 512 MB   → 1 MB
  否则             → 2 MB
gcid = SHA1( concat( SHA1(chunk_i) for i ) ).hexdigest().upper()
```

> 注意是 **SHA1 的 SHA1 树**，且分块大小随文件大小变化 —— 算错就永远命中不了秒传（只会走真实上传，不会报错，难察觉）。
> `check_can_flash_upload` 有可能直接返回失败：npm README 明确记录"currently returns `112 参数错误`"，两份 TS/Py SDK 都做了 catch-and-fallthrough。
> 来源：[npm guangya README](https://www.npmjs.com/package/guangya)

---

## 4. 播放链路（file_id → 可播放直链）

### 4.1 取直链

```http
POST https://api.guangyapan.com/nd.bizuserres.s/v1/get_res_download_url
Authorization: Bearer <access_token>
did: <device_id>
dt: 4
Content-Type: application/json

{ "fileId": "<file_id>" }
```

响应：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "signedURL":   "https://……",   // 优先使用
    "downloadUrl": "https://……"    // 兜底
  }
}
```

取值顺序（**三份实现一致**）：`data.signedURL` 非空用之，否则 `data.downloadUrl`，两者都空则视为失败。
来源：[S2 `download()`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) `data.get("signedURL") or data.get("downloadUrl")`、[S5 `Link`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S6 `downloadResp`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go)

### 4.2 拿直链后怎么请求（这是本地播放的关键）

两个代理实现（[S3 `stream_file`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)、[S4 `_handle_get`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/webdav_provider.py)）对 `signedURL` 的请求方式是：

```
GET <signedURL>
User-Agent: <浏览器 UA 或客户端 UA>
Referer: https://www.guangyupan.com/      ← 两个实现都硬编码了这个 Referer
Range: bytes=…                            ← 有则转发
allow_redirects: true                     ← 显式允许重定向
```

| 问题 | 结论 | 依据 |
|---|---|---|
| 是否需要 `Referer` | **两个实现都主动带了 `Referer: https://www.guangyupan.com/`**，但**没有任何实现记录"不带会失败"**。是否强制防盗链 → **【待验证】**（建议照带，成本为零） | [S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)、[S4](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/webdav_provider.py) |
| 是否需要 `User-Agent` | 是，会转发客户端 UA（有默认值兜底）；**UA 白名单是否存在 →【待验证】** | 同上 |
| 是否需要 `Authorization` | **不需要**。直链自带签名，两个实现请求直链时**不携带** access_token | 同上（转发 header 里只有 UA / Referer / Range） |
| 是否支持 HTTP Range | **支持**（实现转发 `Range`，并把上游 `Content-Range` / `Accept-Ranges` 透传回客户端，并靠 `status == 206` 判断） | [S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)、[S4](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/webdav_provider.py) |
| 是否 302 重定向 | 两个实现都显式 `allow_redirects=True` → **存在重定向的可能（推测 signedURL → CDN 边缘节点）**，但**没有实现留下 302 的证据** → **【待验证】** | 同上 |
| 有效期多久 | **四份实现中完全没有任何过期时间字段/常量**（响应里只有 `signedURL`/`downloadUrl`）→ **【待验证】**。工程上按"短寿命、用完即弃"处理 | [S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go) |
| CDN 域名形态 | **【待验证】**（无法在不登录的情况下取到真实 URL）。上传侧的 `fullEndPoint` 经 `normalizeOSSEndpoint` 处理后是阿里云 OSS 形态 `<endpoint>`（去掉 bucket 前缀），推测下载侧同为阿里云 OSS/CDN，但**无证据** | [S5 `normalizeOSSEndpoint`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| 直链是否需 cookie | 不需要（Python 侧用裸 `requests.get`，无 session） | [S2 `download()`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) |

### 4.3 播放链路推荐形态（给 LemonPlayer）

**方案 A（推荐，先做）**：每次播放前 ⇒ `get_res_download_url` ⇒ 把直链直接交给 `AVPlayer`（配自定义 header）。
- 优点：iOS 原生、可 Range、可拖拽、无中转带宽。
- 前提：直链必须在**播放会话开始后**才失效；`AVPlayerItem` 重建时要重新取链。

**方案 B（兜底）**：自建本地代理（`AVAssetResourceLoaderDelegate` 或 `GCDWebServer` 风格本地 HTTP），把 `Range` 转发到直链，并在 403 时**自动重新取链重试**。
- 这是 [S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py) / [S4](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/webdav_provider.py) 两个实现的做法（它们是服务端代理，但逻辑等价）。
- 建议**从一开始就写这层**，因为 §4.2 里"有效期未知"意味着长时间播放必然遇到链过期。

> **反面参考**：不要在客户端缓存/持久化 `signedURL`（过期即 403/401），只缓存 `fileId`。

---

## 5. 错误码 / 常见失败

### 5.1 已核实的错误码（诚实清单：只有这么几个）

| code / 标识 | 含义 | 依据 |
|---|---|---|
| `0` / `msg == "success"` | 成功 | [S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go)、[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| `112` | 参数错误（`参数错误`）—— 实测 `check_can_flash_upload` 会返回它 | [npm guangya README](https://www.npmjs.com/package/guangya) |
| `156` | 秒传 / 任务已存在（上传 token 阶段） | [S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) `if response.get("code") == 156` |
| `145, 146, 147, 155, 163` | 任务处理中（非终态），应继续轮询 | [S2 `_wait_task_done`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)、[S5 `waitUploadTaskInfo`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) |
| `msg == "文件上传中"` | 上传任务未完成 | [S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S11](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/client.ts) |
| `error: "authorization_pending"` | 设备码未授权（HTTP 4xx + JSON） | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) |
| `error: "invalid_grant"` / `"invalid_token"` / `"unauthorized"` / 中文 `无效token` `认证失败` | token 失效，刷新或重登 | [S1 `_is_auth_invalid_result`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) |
| HTTP `401` / `403` | token 过期或无权：**两份实现都把 403 当成"需要刷新 token"处理** | [S5 `postAPI`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) `if resp.StatusCode() == 401 \|\| resp.StatusCode() == 403` |

### 5.2 未证实的失败类型（**【待验证】清单**）

以下都是任务简报里点名、但**四份实现中找不到任何实据**的失败模式，**不要写进代码的"确定分支"**，只能当"未知错误统一处理"：

| 说 法 | 状态 |
|---|---|
| 签名失效专用错误码 | **【待验证】** 无任何 code 常量 |
| 限流（429 / 频率）错误码或响应头 | **【待验证】** 只有 AList 出于礼貌加的 500ms/endpoint 限速，没有服务端限流证据 |
| 会员限制（非会员不能下载/播放原画） | **【待验证】** 无任何实现做会员判断 |
| 防盗链 403（下载侧） | **【待验证】**（虽然实现都带 Referer，但没有对照实验记录） |
| 直链过期后的具体 HTTP 状态 | **【待验证】** |
| 存储空间不足 / 文件名非法 的 code | **【待验证】** |

### 5.3 重试策略建议（基于已验证事实推导）

| 场景 | 建议 | 依据/理由 |
|---|---|---|
| 业务 API 返回 `401`/`403` | 刷新 token → 重放**一次**（不要无限重试） | [S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go) 就是这么做的（刷新后重放一次，不再递归） |
| 刷新返回 `invalid_grant` | 清 Keychain，回到扫码页 | [S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) |
| `authorization_pending` | 按 `interval`（默认 5s）轮询，直到 `expires_in`（默认 300s） | [S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py) |
| 直链 403/401 | **重新调 `get_res_download_url` 换链**，再重试；最多 2 次 | 有效期未知（§4.2）⇒ 唯一可靠恢复手段 |
| 任务轮询 | 固定上限 + 退避（如 30 次 × 500ms），超时就放弃 | S5 用 30×300ms，S2 用 300×1s |
| 通用业务调用 | **同一 endpoint 最小间隔 500ms** | AList 显式实现 `apiRateInterval = 500 * time.Millisecond`（[S5](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)） |
| 网络错误 | 指数退避 1s→2s→4s，最多 3 次 | 通用 |

> **并发刷新的坑（高风险）**：`refresh_token` 可能轮换（[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) 用返回的新值覆盖，取不到则保留旧值）。若 App 内多个请求同时 401 → 同时刷新 → 后到的旧 refresh_token 会让**前面的新 token 失效**（甚至踢下线）。**必须用 actor 串行化刷新，并做"single-flight"合并**。

---

## 6. Swift 实现注意事项

### 6.1 URLSession 封装

```swift
// 关键点 1：4xx 的 body 必须能读到（authorization_pending 就是 4xx + JSON）
// 关键点 2：区分"账户域扁平响应"与"业务域 {code,msg,data} 信封"
// 关键点 3：所有请求统一注入 did/dt/Origin/Referer/traceparent
```

- **不要**用"非 2xx 即 throw"的封装包住认证接口。`/v1/auth/token` 在 `authorization_pending` 时返回 4xx + `{"error":"authorization_pending"}`，必须解析 body。
  依据：[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py) `treat_http_error_as_response=True`
- 建议 `URLSessionConfiguration.ephemeral` + 自定义 `httpAdditionalHeaders`；`timeoutIntervalForRequest = 30`（Python 侧都是 30s）。
  依据：[S1 `_request(timeout=30)`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)
- 业务响应统一 `struct APIEnvelope<T: Decodable>: Decodable { let code: Int?; let msg: String?; let error: String?; let data: T? }`，并按"`code == 0 || msg?.lowercased() == "success"`"判成功。
  依据：[S6](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/types.go)、[S8 `isSuccessMsg`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/offline.go)
- **`fileId` 用 `String`**：同一个 API 在 Python/TS 实现里既接受 `int` 也接受 `string`，`fileId` 形态未定型，用 `String` + 宽松解码最安全。
  依据：[S2](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py) 全部 `str(item.get("fileId"))`；[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py) 签名 `Optional[Union[int, str]]`

### 6.2 token 持久化（Keychain）

- 存：`access_token`、`refresh_token`、`device_id`、`expires_at`（= 本机时间 + `expires_in`）。
- `device_id` **必须持久化**：它与 token 绑定，实现里 `did` 每次都发同一个；AList 还会校验格式（32 位小写 hex）。
  依据：[S5 `normalizeDeviceID`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)、[S1](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py)
- Keychain 项用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（避免 iCloud 同步到别的设备导致 token 互踢）。
- 刷新后**原子写回**：先写 refresh_token 再更新内存，避免中途崩溃丢新 refresh_token。

### 6.3 时间同步

- 普通 API **不需要**时间同步（无 timestamp 签名，§1.4）。
- **上传 OSS 时必须**：`x-oss-date` 用 **HTTP Date（GMT）格式**的当前时间，签名串里也用它；本机时钟偏差过大会被 OSS 拒（具体错误串 **【待验证】**）。
  依据：[S10 `oss_sign_headers`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)（`formatdate(usegmt=True)`）、[S11 oss.ts](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/oss.ts)（`new Date().toUTCString()`）
- 建议：取一次 `Date` 响应头算 offset，或直接用 `Date()` 但容忍 NTP 漂移。
- OSS 签名（V1）拼接顺序（**照抄即可**）：
  ```
  StringToSign =
    HTTP-METHOD            \n
    Content-MD5            \n
    Content-Type           \n
    Date                   \n
    x-oss-date:<date>      \n
    x-oss-security-token:<token>  \n
    /<bucket>/<objectPath>[?<sorted sub-resources>]
  Authorization = "OSS " + accessKeyID + ":" + base64(HMAC-SHA1(StringToSign, secretAccessKey))
  ```
  canonical headers 按 key 字典序，sub-resources 按 key 字典序、有值用 `k=v` 无值用 `k`。
  依据：[S11 oss.ts `ossSignHeaders`](https://raw.githubusercontent.com/intellecat/guangya-node/HEAD/src/oss.ts)、[S10 `oss_sign_headers`](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)（两份实现完全一致，可信度高）

### 6.4 并发限流

- **同 endpoint 最小 500ms 间隔**（AList 的做法，按 path 分别限流）。
  依据：[S5 `apiRateInterval` + `apiRateLimitWait`](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/driver.go)
- 建议用 `actor` + 每 path 一个 `lastFireTime`，或单一 `AsyncSemaphore(3)` 全局并发上限。
- 列表分页**串行**（不要并发拉 page 0..N，`total` 可能变化导致漏项/重复）。
- token 刷新**单飞**（§5.3）。
- 一次 App 启动只调一次 `/v1/user/me`（当探针），不要每次进页面都验 token。

### 6.5 Range 请求 / AVPlayer & VLC 需要的头

**AVPlayer**
- 直链 + 自定义 header 的标准做法：`AVURLAsset(url:options: ["AVURLAssetHTTPHeaderFieldsKey": headers])`。
- `headers = ["Referer": "https://www.guangyupan.com/", "User-Agent": "<桌面 Chrome UA>", "Range": "bytes=0-"]`（Range 一般交给系统发，不要手写死）。
- **坑**：`AVURLAssetHTTPHeaderFieldsKey` 是私有键，在某些 iOS 版本上对 `AVPlayerItem` 生效但 `AVAssetResourceLoaderDelegate` 场景要自己带；**建议直接用 ResourceLoader 代理**，可控性最强。
- 播放器要 `Accept-Ranges` / `206 Partial Content` 才能拖拽 —— 上游给了（实现透传了），但**请务必在真机上验证 `206`**。

**VLC (MobileVLCKit)**
- `VLCMedia(url:)` 后设置选项：
  `:http-referrer=https://www.guangyupan.com/`
  `:http-user-agent=<UA>`
- VLC 对 mkv/hevc/ass 字幕兼容性远好于 AVPlayer —— **光鸭库里的影视资源大概率是 mkv**，建议默认 VLC 内核，AVPlayer 作为 mp4/m4v 的快路径。

> 以上 header 组合来自两个代理实现实际转发的集合（UA + Referer + Range），不是猜测。
> 依据：[S3 `stream_file`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)、[S4 `_handle_get`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/webdav_provider.py)

### 6.6 下载离线文件的分块策略

- **不要**用 `URLSession.downloadTask` 直接下整集（无法断点续传、无法感知链过期）。用 `URLSession` 的 `Range` 分段 + `FileHandle` 追加写：
  - 块大小参考两个实现的读者：Python 侧 `iter_content(10MB)`（落盘）、代理侧 `256KB`（转发）。**落盘建议 4–8 MB/块**，兼顾内存与 Range 请求数。
  - 每块完成后记录 `bytesWritten`，链过期（403）时**重新取链**并从 `bytesWritten` 继续 `Range: bytes=N-`。
  依据：[S2 `download()`](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_api.py)（10MB chunk）、[S3](https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/__init__.py)（256KB chunk）
- 校验：列表项有 `fileSize`，下完比对大小；`md5`/`gcid` 字段存在但**是否对普通文件填充【待验证】**，不要当作必然可得。
- 后台下载：`URLSessionConfiguration.background` 与自定义 Range 循环有冲突（后台 session 不支持自定义 header 变更），建议**前台分块下载 + 断点续传元数据持久化**，或直接用系统 background downloadTask（但需接受无法换链）。
- 磁盘：`.part` 文件 + 完成后原子 rename；`URLSession` 的 `expectedContentLength` 在 206 时是**分片长度**，别当总长。

### 6.7 其他工程提醒

- **接口不稳定**：这是 C 端私有 API，没有版本承诺。建议把 path 常量集中在一个 `GuangYaEndpoint` enum，便于一次性改。
- **`mineType` 拼写**：服务端字段就是 `mineType`（S11 类型定义），别"纠正"。
- **`fileTypes` / `resType` 组合**：聚合视图用 `parentId:"*" + fileTypes:[2] + resType:1`；这是唯一可核实的"跨目录取视频"方式。
- **不要相信 `thumbnail`**（§3.3），海报请自建缓存。

---

## 7. 刻意没写进本文的东西

- 分享（share）系列 11 个接口、离线下载（cloud collection）系列 5 个接口：[S10](https://raw.githubusercontent.com/DDSRem-Dev/guangyaclient/master/guangyaclient/client.py)、[S8](https://github.com/alist-org/alist/blob/main/drivers/guangyapan/offline.go) 里有完整签名，但**与播放器主链路无关**，且 LemonPlayer 不需要，故略（如需要可照 S10 的 `share_*` / `cloud_*` 方法逐字搬迁）。
- 任何"会员等级/限速/VIP 权益"相关判断 — 无任何依据，全部【待验证】。

---

## 附录 A：一次性 curl 核对脚本（填上自己的 token 后可直接验证）

```bash
CID=aMe-8VSlkrbQXpUR
DID=$(openssl rand -hex 16)          # 32 hex
AT=<your access_token>

# 1) 设备码（不需要 token）
curl -sS -X POST https://account.guangyapan.com/v1/auth/device/code \
  -H 'content-type: application/json' \
  -H "x-client-id: $CID" -H "x-device-id: $DID" -H 'x-client-version: 0.0.1' \
  -d "{\"scope\":\"user\",\"client_id\":\"$CID\"}"

# 2) 用户信息（token 探针）
curl -sS https://account.guangyapan.com/v1/user/me -H "Authorization: Bearer $AT"

# 3) 空间
curl -sS -X POST https://api.guangyapan.com/nd.bizassets.s/v1/get_assets \
  -H "Authorization: Bearer $AT" -H "did: $DID" -H 'dt: 4' \
  -H 'content-type: application/json' -d '{}'

# 4) 根目录列表
curl -sS -X POST https://api.guangyapan.com/nd.bizuserres.s/v1/file/get_file_list \
  -H "Authorization: Bearer $AT" -H "did: $DID" -H 'dt: 4' \
  -H 'content-type: application/json' \
  -d '{"parentId":"","page":0,"pageSize":100,"orderBy":3,"sortType":1,"fileTypes":[]}'

# 5) 直链（拿 fileId 后）：重点观察 signedURL 的 host、query 参数、过期字段、是否 302
curl -sS -X POST https://api.guangyapan.com/nd.bizuserres.s/v1/get_res_download_url \
  -H "Authorization: Bearer $AT" -H "did: $DID" -H 'dt: 4' \
  -H 'content-type: application/json' -d '{"fileId":"<file_id>"}'

# 6) 验证 Range / 防盗链 / 重定向（关键三个实验）
curl -sSI -H 'Referer: https://www.guangyupan.com/' -H 'Range: bytes=0-1023' '<signedURL>'
curl -sSI -H 'Range: bytes=0-1023' '<signedURL>'                    # 去掉 Referer 对照
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' '<signedURL>'   # 看 302
```

**实验 6 的三个结果直接决定 §4.2 的【待验证】项**，建议在实现播放器前先跑一遍并回填本文档。

---

## 附录 B：待验证清单（TL;DR）

| # | 待验证项 | 影响 |
|---|---|---|
| 1 | `signedURL` 有效期、CDN host 形态、是否 302 | 播放器取链频率与代理层设计 |
| 2 | 直链是否需要 `Referer`/`UA`（防盗链是否强制） | 403 排查方向 |
| 3 | `get_file_detail` 的真实字段（仅单一来源 S11） | 时长/分辨率/海报功能 |
| 4 | `thumbnail` 字段的取值形态 | 缩略图/海报墙 |
| 5 | 服务端搜索接口是否存在 | "搜索"功能实现方式 |
| 6 | `get_assets` 中 VIP/会员字段名与单位 | 会员信息展示 |
| 7 | `429`/限流、会员限制、签名失效的具体错误码 | 错误提示与重试分支 |
| 8 | 设备码响应是否有 `data` 包裹 / `expired_token` 是否存在 | 扫码轮询健壮性 |
| 9 | 删除/移动/复制的任务终态判定（`status==3` 是成功还是失败，两份实现冲突） | 写操作结果判定 |
| 10 | `orderBy` 0/1/2/4 的具体排序字段 | 排序 UI |
