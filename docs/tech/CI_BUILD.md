# 构建与分发（GitHub Actions · Xcode 26）

> 版本：v0.1 · 更新：2026-11-03 · 对应任务 T-006 / ADR-006
> 前提：开发机为 Windows（无 Xcode/Swift），**CI 是唯一编译真相源**；分发只做未签名 IPA + 自签。

---

## 0. 结论

| 项 | 决策 |
|---|---|
| Runner | `macos-26`（arm64），镜像 `20261026.0455.2`，系统 macOS 26.6.2 |
| Xcode | **26.6（17F113，默认）**；同镜像还预装 26.5 / 26.4.1 / 26.3 / 26.2 / 26.1.1 / 26.0.1 |
| SDK | iOS 26.5（Xcode 26.6 对应 `iphoneos26.5`） |
| 工程生成 | XcodeGen（`project.yml` 为唯一真相源）→ 生成 `.xcodeproj` |
| 依赖 | 主选 MobileVLCKit 3.7.5（CocoaPods）→ 需要 `pod install` 生成 `.xcworkspace` |
| 测试 | 模拟器 `xcodebuild test`（iPhone 17 / iOS 26.5，运行时用 `simctl list` 动态兜底） |
| 产物 | 未签名 `LemonPlayer-unsigned.ipa` + `.xcarchive`（可选）+ 测试日志 |
| 签名 | 不做（`CODE_SIGNING_ALLOWED=NO`）；安装由用户用 Sideloadly/AltStore 自签 |
| 发布 | 打 `v*` tag → 附加 IPA 到 GitHub Release + SHA256 |

> 说明：`macos-26` 目前是 arm64 镜像；`macos-26` 的 Intel 版本曾在 2026 年以 public beta 形式存在，已不需要。若镜像标签未来改名，用 `macos-latest` 会漂移，**必须显式写 `macos-26`**。

---

## 1. 关键命令（可直接复制验证）

### 1.1 环境准备

```bash
# 默认已经是 Xcode 26.6，一般无需切换；显式固定版本更稳
sudo xcode-select -s /Applications/Xcode_26.6.app
xcodebuild -version          # Xcode 26.6, Build 17F113
xcodebuild -showsdks | grep iphoneos

# XcodeGen（镜像未预装，需安装）
brew install xcodegen
xcodegen --version

# CocoaPods 镜像已预装 1.17.0；确认
pod --version
```

### 1.2 生成工程 + 安装依赖

```bash
xcodegen generate --spec project.yml
pod install --repo-update
```

> XcodeGen 生成 `.xcodeproj`，CocoaPods 在其上注入 `Pods.xcodeproj` 并生成 `.xcworkspace`。
> **构建/测试必须用 `LemonPlayer.xcworkspace`**，不是 `.xcodeproj`。
> `project.yml` 里不要手写 Pods 相关 target；`Podfile` 与 `project.yml` 各自管理。

### 1.3 模拟器构建 + 单测

```bash
# 动态取一个可用的 iPhone 模拟器（避免镜像升级后设备名变化导致失败）
DEST=$(xcrun simctl list devices available -j \
  | jq -r '[.devices[][] | select(.name|startswith("iPhone"))][0] | "platform=iOS Simulator,name=\(.name),OS=\(.os // "" | gsub("iOS-";""))"')
# 简化版（固定写法，镜像当前可用）：
# DEST='platform=iOS Simulator,name=iPhone 17,OS=26.5'

xcodebuild test \
  -workspace LemonPlayer.xcworkspace \
  -scheme LemonPlayer \
  -destination "$DEST" \
  -derivedDataPath .build/DerivedData \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
```

### 1.4 未签名 IPA（Release，真机架构）

```bash
xcodebuild archive \
  -workspace LemonPlayer.xcworkspace \
  -scheme LemonPlayer \
  -configuration Release \
  -sdk iphoneos \
  -archivePath .build/LemonPlayer.xcarchive \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | xcbeautify

# 组 Payload 并压缩成 IPA（未签名）
mkdir -p .build/Payload
cp -R .build/LemonPlayer.xcarchive/Products/Applications/LemonPlayer.app .build/Payload/
cd .build && zip -qr LemonPlayer-unsigned.ipa Payload
shasum -a 256 LemonPlayer-unsigned.ipa
```

> 关键点：
> - `CODE_SIGNING_ALLOWED=NO` 必须同时作用于 `archive`，否则会对未配置签名的 target 报错；
> - 未签名 IPA 里没有 `_CodeSignature`，直接安装会失败，必须由 Sideloadly/AltStore 重签；
> - `Payload/` 目录名对大小写敏感，必须是 `Payload`。

---

## 2. Workflow 骨架

> 放在 `.github/workflows/build.yml`，M1 落地时创建。下面每一段都标了"为什么"。

```yaml
name: build

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true          # 同分支新提交取消旧任务，省 macOS 分钟

jobs:
  build:
    runs-on: macos-26               # arm64；显式固定，不用 macos-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.6.app

      - name: Cache CocoaPods
        uses: actions/cache@v4
        with:
          path: |
            ~/.cocoapods
            Pods
          key: pods-${{ hashFiles('Podfile.lock') }}

      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: |
            .build/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ hashFiles('**/Package.resolved') }}

      - name: Install tools
        run: |
          brew install xcodegen
          pod install --deployment       # --deployment 确保严格按 Podfile.lock

      - name: Generate project
        run: xcodegen generate --spec project.yml

      - name: Build & test (simulator)
        run: |
          xcodebuild test \
            -workspace LemonPlayer.xcworkspace \
            -scheme LemonPlayer \
            -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
            -derivedDataPath .build/DerivedData \
            -enableCodeCoverage YES \
            CODE_SIGNING_ALLOWED=NO | xcbeautify

      - name: Archive (unsigned)
        if: github.ref == 'refs/heads/main'
        run: |
          xcodebuild archive \
            -workspace LemonPlayer.xcworkspace \
            -scheme LemonPlayer \
            -configuration Release -sdk iphoneos \
            -archivePath .build/LemonPlayer.xcarchive \
            -derivedDataPath .build/DerivedData \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | xcbeautify
          mkdir -p .build/Payload
          cp -R .build/LemonPlayer.xcarchive/Products/Applications/LemonPlayer.app .build/Payload/
          (cd .build && zip -qr LemonPlayer-unsigned.ipa Payload && shasum -a 256 LemonPlayer-unsigned.ipa)

      - name: Upload IPA
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: LemonPlayer-unsigned-ipa
          path: .build/LemonPlayer-unsigned.ipa
          retention-days: 14
```

> 注意：`pod install` 要在 `xcodegen generate` **之后**执行（Pods 需要基于生成的工程注入）；若顺序反了，`.xcworkspace` 会指向不存在的工程。
> 实际上 CocoaPods 是在 `pod install` 时读取 `.xcodeproj`：因此顺序 = 先 generate，再 pod install。

### 2.1 版本/发布工作流（M7 落地）

```yaml
on:
  push:
    tags: ['v*']
# 步骤与 build 类似，最后：
#   - 生成 SHA256SUMS
#   - softprops/action-gh-release 上传 IPA + SHA256
```

需要用户填的 secrets（M7）：

| Secret | 用途 | 何时需要 |
|---|---|---|
| `TMDB_API_KEY` | 注入 xcconfig/Info.plist | M5 起 |
| `APPLE_TEAM_ID` / `APPLE_CERT_P12` / `APPLE_PROVISION_PROFILE` | 自动签名出可安装 IPA | 仅当改走 TestFlight |
| `APPSTORE_API_KEY_ID` / `APPSTORE_API_ISSUER` / `APPSTORE_API_KEY` | `xcodebuild -exportArchive` 上传 TestFlight | 同上 |

> 当前（仅自签）不需要任何 secret；CI 不涉及证书。

---

## 3. 安装路径（写给用户）

### 3.1 未签名 IPA → 自签安装（免费 Apple ID）

1. 从 Actions 产物或 Release 下载 `LemonPlayer-unsigned.ipa`；
2. Windows/Mac 上用 **Sideloadly** 或 **AltStore**，登录自己的 Apple ID，选择 IPA；
3. 工具会用免费开发者证书重签并安装到设备；需在「设置 → 通用 → VPN与设备管理」信任证书；
4. **免费账号签名 7 天过期**，过期后 App 打不开，需重新用工具续签；
5. 首次启动若提示"不受信任的开发者"，同上处理。

### 3.2 TestFlight（需 $99/年开发者账号）

- 需要 Team ID + App Store Connect API Key 配到 GitHub Secrets；
- 工作流改为 `xcodebuild -exportArchive -exportOptionsPlist`（`method: app-store-connect`）+ `xcrun altool/notarytool` 上传；
- 优点：90 天有效、可无线安装；缺点：需要付费账号 + 审核（内部测试可免审）。

### 3.3 不要做的事

- ❌ 不要把 `*.p12` / `*.mobileprovision` 提交进仓库（`.gitignore` 已覆盖）；
- ❌ 不要用 `macos-latest`（镜像漂移会随机失败）；
- ❌ 不要在未配置签名时跑 `archive` 却忘了 `CODE_SIGNING_ALLOWED=NO`（会报 "requires a provisioning profile"）。

---

## 4. Windows 本地开发说明

- 本机无法编译 Swift；只能改代码、跑文档、读 CI 日志。
- **网络代理**：本机 `127.0.0.1:7890` 有可用代理；shell 直连 GitHub 会超时，需要时这样用：

```powershell
$env:HTTPS_PROXY='http://127.0.0.1:7890'; $env:HTTP_PROXY='http://127.0.0.1:7890'
git -c http.proxy=http://127.0.0.1:7890 clone <repo>     # 单次
# 或全局（会污染其他仓库，谨慎）：
# git config --global http.proxy http://127.0.0.1:7890
```

- 纯逻辑包（`LemonSubtitle`、`LemonMedia` 解析器）设计为不依赖 UIKit，未来可选用 **Swift for Windows** 在本地跑 `swift test`（M1 之后评估，不作为必须项）。

---

## 5. 常见坑（按优先级）

| 坑 | 现象 | 处理 |
|---|---|---|
| 镜像 Xcode 版本升级 | 新 iOS SDK 触发新警告/弃用 | 固定 `Xcode_26.6.app`；升级单独 PR 验证 |
| CocoaPods 与 XcodeGen 顺序 | `.xcworkspace` 打不开 / Pods target 丢失 | 先 `xcodegen generate` 再 `pod install` |
| VLCKit 静态链接 | 缺少资源 bundle / 符号重复 | `use_frameworks! :linkage => :static` + 检查 `resources` |
| 模拟器设备名变化 | `destination` 找不到设备 | 用 `simctl list -j` 动态解析（见 1.3） |
| 覆盖率文件 | `.xcresult` 解析失败 | 用 `xcrun xccov view --report` 或 `-enableCodeCoverage` + 第三方 action |
| macOS 分钟计费 | 每月额度耗尽 | `concurrency` 取消旧任务；仅 main/tag 跑 archive |
| 大体积二进制缓存 | cache key 命中率低、上传慢 | cache 只放 `Pods/`、`SourcePackages`，不放 `DerivedData` |
| 未签名 IPA 安装失败 | "无法安装此 App" | 用 Sideloadly/AltStore 重签，不要直接 `ideviceinstaller` |

---

## 6. 待验证（M1 执行时回填）

- [ ] `macos-26` runner 上 `brew install xcodegen` 的实际耗时与版本
- [ ] MobileVLCKit 3.7.5 在 Xcode 26.6 下的编译是否通过（有无 Swift 6 并发/弃用告警）
- [ ] XcodeGen 生成的工程 + CocoaPods static linkage 是否兼容
- [ ] `xcodebuild test` 的模拟器 destination 在当前镜像的实际可用设备名
- [ ] 未签名 IPA 的实际体积（含 VLCKit）是否 < 300MB 目标
