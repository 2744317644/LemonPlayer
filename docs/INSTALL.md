# 安装说明（未签名 IPA 自签）

> 适用版本：M1 之后的每次 CI 构建产物。适用于没有开发者账号（或只有免费 Apple ID）的情况。

## 1. 拿到 IPA

方式 A：GitHub Actions
1. 打开仓库 → Actions → 最近一次 `build` 运行；
2. 页面底部 `Artifacts` → 下载 `LemonPlayer-unsigned-ipa`（zip）；
3. 解压得到 `LemonPlayer-unsigned.ipa`。

方式 B：Release（M7 之后）
- 打 `v*` tag 后，Release 页会附带 IPA 与 `SHA256SUMS`。

> 未签名 IPA **不能直接安装**，必须用工具重签。

## 2. 自签安装（免费 Apple ID）

### Windows / macOS：Sideloadly

1. 下载并安装 [Sideloadly](https://sideloadly.io/)；
2. 数据线连接 iPhone，信任电脑；
3. Sideloadly 选择 `LemonPlayer-unsigned.ipa`，Apple ID 填自己的（会做双重验证）；
4. 点击 Start，输入 Apple ID 密码/验证码；
5. 安装完成后，手机「设置 → 通用 → VPN与设备管理」→ 信任该开发者证书；
6. 打开 App。

### AltStore（自签 + 自动续签）

1. 电脑安装 AltServer，手机装 AltStore（AltServer 会帮你签名）；
2. AltStore → My Apps → `+` → 选择 IPA；
3. 保持电脑与手机同一 Wi-Fi，AltStore 可每 7 天自动续签。

## 3. 7 天限制

- 免费 Apple ID 签名的 App **有效期 7 天**，到期后图标仍在但打开闪退；
- 解决办法：重新用 Sideloadly/AltStore 覆盖安装（数据会保留，Keychain 凭据不丢）；
- 有 $99 开发者账号可以用 1 年签名，或走 TestFlight（90 天）。

## 4. 首次启动检查清单

- [ ] 出现登录页 → 用光鸭云盘 App 扫码；
- [ ] 登录成功后进入「网盘」页，能看到根目录文件；
- [ ] 抽屉/设置里显示当前账号；
- [ ] 断网后重新打开：可进入 App 并提示网络错误（不闪退）。

## 5. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 安装时报 "未受信任的开发者" | 证书未信任 | 设置 → 通用 → VPN与设备管理 → 信任 |
| 打开后闪退（7 天后） | 签名过期 | 重新自签覆盖安装 |
| 扫码后 App 没反应 | 轮询被系统挂起 | 保持 App 在前台 2 分钟内完成扫码（设备码有效期 120 秒） |
| 登录后又回到登录页 | refresh_token 失效 | 重新扫码；如频繁发生请导出诊断日志反馈 |
| 目录列表 401 | token 过期/设备标识不一致 | 退出重登；检查是否恢复了备份导致 Keychain 与 UserDefaults 不同步 |

## 6. 安全提示

- 你的 Apple ID 密码只应输入到 Sideloadly/AltStore 本地工具，不要发给任何人；
- 光鸭凭据存放在 iOS Keychain（`AfterFirstUnlockThisDeviceOnly`），不会随 iCloud 备份迁移到其他设备；
- 本项目不会上传任何账号信息。
