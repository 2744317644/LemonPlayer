# CI 构建与出包（GitHub Actions · Xcode 26）

> 版本：v0.2 · 更新：2026-11-03 · 对应 ADR-004（XcodeGen）、ADR-006（CI）、ADR-012（分发形态）
> 前提：开发机是 Windows（无 Xcode），**CI 是唯一的编译真相源**（ADR-011）；v1 只产出**未签名 IPA**，由用户侧自签安装。
> 关联文档：[`PLAYER_KERNEL.md`](PLAYER_KERNEL.md)（内核选型 → 决定依赖形态）

---

## 0. 结论（TL;DR）

| 项 | 决策 |
|---|---|
| Runner | **`macos-26`**（arm64 / Apple Silicon；`macos-latest` 也指向它），镜像 `20261026.0455.2`，系统 **macOS 26.6.2（25G83）** |
| Xcode | 预装 26.0.1 / 26.1.1 / 26.2 / 26.3 / 26.4.1 / 26.5 / **26.6（默认，17F113）**；workflow 里**显式 pin** `Xcode_26.6.app` |
| SDK | `iphoneos26.5`（Xcode 26.5/26.6 共用）；`IPHONEOS_DEPLOYMENT_TARGET = 26.0` |
| 工程 | XcodeGen 生成（`project.yml` 是唯一真相源）→ **先 `xcodegen generate`，再 `pod install`** → 用 `.xcworkspace` 构建 |
| 依赖 | MobileVLCKit 3.7.5（CocoaPods）→ CI 必须 `pod install` + 缓存 |
| 单测 | 模拟器 `xcodebuild test`，设备 **运行时用 `xcrun simctl` 动态解析**（镜像里 iOS 26.5 有 iPhone 17 / 17 Pro / iPhone Air） |
| 产物 | `LemonPlayer-unsigned.ipa`（`Payload/` + `zip -X`）+ `.xcresult`；tag 构建再附到 GitHub Release |
| 签名 | 不做（`CODE_SIGNING_ALLOWED=NO`） |
| 计费 | 私有仓库：macOS 标准 runner **$0.062/分钟**（≈Linux 的 10 倍）→ 一次完整 CI ≈ 25–35 分钟 ≈ **$1.5–2.2** |

---

## 1. macOS runner 现状（2026-11-03 抓取）

### 1.1 标签与架构

| 标签 | 架构 | 说明 |
|---|---|---|
| **`macos-26`** | **arm64** | 标准 3-core Apple Silicon；`macos-latest` 指向它；`macos-26-xlarge` 是同镜像大规格 |
| `macos-26-intel` / `macos-26-large` | x64 | Intel 版（`macos-latest-large` 指向它） |
| `xcode-27` | arm64 | Xcode 27 公共预览镜像（现阶段不要用） |
| `macos-14` | x64 | **2026-11-02 已全部退役**，引用它必失败 |
| `macos-15` / `macos-15-intel` | arm64 / x64 | 上一代，可用但没必要 |

> 结论：`runs-on: macos-26` 就是 **Apple Silicon**。担心"是不是 Intel"的疑虑可以放下——但在 workflow 里**不要写 `macos-latest`**（会随 GA 版本漂移）。

### 1.2 镜像内容（`macos-26` / arm64，镜像 `20261026.0455.2`）

| 组件 | 版本 |
|---|---|
| OS | macOS 26.6.2（25G83），Darwin 25.6.0 |
| **CocoaPods** | **1.17.0**（预装，不需要 `gem install`） |
| **xcbeautify** | **3.2.1**（预装，可直接用） |
| **Xcodes CLI** | 2.1.0（预装，需要"镜像里没有的 Xcode 版本"时用） |
| Fastlane | 2.238.0 |
| SwiftLint | 0.65.1 |
| Ruby / Bundler | 3.4.10 / 4.0.19 |
| jq | 1.8.2（解析 `simctl -j` 用） |
| Homebrew | 6.x（`brew install xcodegen` 用） |
| Xcode Command Line Tools | 26.6.0 |

### 1.3 预装 Xcode

| Xcode | Build | 路径 |
|---|---|---|
| **26.6（默认）** | 17F113 | `/Applications/Xcode_26.6.app`（`/Applications/Xcode.app` 软链到这里） |
| 26.5 | 17F42 | `/Applications/Xcode_26.5.app` |
| 26.4.1 | 17E202 | `/Applications/Xcode_26.4.1.app` |
| 26.3 | 17C529 | `/Applications/Xcode_26.3.app` |
| 26.2 | 17C52 | `/Applications/Xcode_26.2.app` |
| 26.1.1 | 17B100 | `/Applications/Xcode_26.1.1.app` |
| 26.0.1 | 17A400 | `/Applications/Xcode_26.0.1.app` |

SDK：`iphoneos26.0 / 26.1 / 26.2 / 26.4 / **26.5**`（26.5 供 Xcode 26.5 与 26.6 使用）。

### 1.4 预装模拟器（iOS 部分）

| 运行时 | 关键设备 |
|---|---|
| iOS 26.2 | iPhone 16e、iPhone 17、17 Pro、17 Pro Max、iPhone Air、iPad (A16)、iPad Pro 11/13-inch (M5)… |
| iOS 26.4 | iPhone 17、17 Pro、17 Pro Max、**17e**、iPhone Air、iPad (A16)、iPad Air (M4)、iPad Pro (M5)… |
| **iOS 26.5** | iPhone 17、17 Pro、17 Pro Max、17e、iPhone Air、iPad (A16)、iPad Air (M4)、iPad Pro 11/13-inch (M5)… |

→ `name=iPhone 17` 在 2026 年的镜像是**可用**的，但设备名会随运行时版本变（26.2 没有 17e、26.4 才有）。**推荐运行时解析**（§5）。

### 1.5 上架口径（即使 v1 不上架也要知道）

**2026-04-28 起**，上传 App Store Connect 的 iOS 应用必须用 **iOS 26 SDK（Xcode 26）** 构建。我们本来就在 Xcode 26 上，天然满足；但这也意味着**不要**回退到 Xcode 15/16 的构建。

---

## 2. 选择 Xcode（三种写法 + 断言）

```yaml
# ✅ 写法 A：镜像自带多版本目录（推荐）
- name: Select Xcode
  run: |
    sudo xcode-select -s /Applications/Xcode_26.6.app
    xcodebuild -version            # 断言：Xcode 26.6 / Build 17F113
    xcrun --sdk iphoneos --show-sdk-version   # 期望 26.5

# 写法 B：环境变量（对 xcodebuild / swift 都生效，无需 sudo）
- run: echo "DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer" >> "$GITHUB_ENV"

# 写法 C：要装镜像里没有的版本（如将来的 26.7）
- run: |
    xcodes install 26.7 --directory /Applications --experimental-unxip
    sudo xcode-select -s /Applications/Xcode_26.7.app
```

**必须做版本断言**：镜像每周更新，默认 Xcode 会漂移（2026-07-21 就切过一次默认版本）。建议把断言做成一步，失败立刻红：

```bash
test "$(xcodebuild -version | head -1)" = "Xcode 26.6" || {
  echo "::error::Xcode 版本漂移，请更新 XCODE_APP"; exit 1; }
```

---

## 3. 工程生成 + 依赖安装（XcodeGen → CocoaPods）

> **仓库现状（M1 已实测通过）**：当前 `project.yml` 只依赖 `Packages/` 下的 8 个本地 SPM 包，没有 `Podfile`，所以 `.github/workflows/build.yml` 用 `-project LemonPlayer.xcodeproj` 构建 —— 首次 Actions run `41650264063`（2026-11-03）**1m16s 全绿**，产出 `LemonPlayer-unsigned.ipa`（骨架版 22KB）并上传 artifact。
> **CocoaPods 在 M3 引入**（MobileVLCKit 随 T-301 接入）之后才会多出 `Podfile` → `.xcworkspace`，从那时起本文所有 `xcodebuild` 都必须改成 `-workspace LemonPlayer.xcworkspace`（差异清单见 §8.3）。

顺序**不能颠倒**（CocoaPods 要读取已存在的 `.xcodeproj`）：

```bash
brew install xcodegen                      # 镜像未预装；首次约 30–60s（可缓存）
xcodegen generate --spec project.yml       # ① 生成 LemonPlayer.xcodeproj
pod install --deployment                   # ② 在 .xcodeproj 上注入 Pods
# ③ 之后所有 xcodebuild 都用 -workspace LemonPlayer.xcworkspace
```

要点：

- `--deployment` 要求 `Podfile.lock` 与 `Pods/` 一致，**防止 CI 悄悄升级依赖**；
- `Podfile.lock` + `project.yml` 必须提交进仓库（`Pods/` 不提交，由缓存/安装恢复）；
- `pod install` 会改写 `.xcworkspace`，**不要**提交 `.xcworkspace`（XcodeGen/CocoaPods 生成物）；
- 私有仓库里 MobileVLCKit 的下载包 **222 MB**，一定要缓存（§4）。

---

## 4. 缓存

| 缓存对象 | 路径 | 说明 |
|---|---|---|
| CocoaPods 下载缓存 | `~/Library/Caches/CocoaPods` | mobilevlckit 的 tar.xz 落在这里，命中后 `pod install` 从 ~2 分钟降到 ~10 秒 |
| Pods 产物 | `Pods/` | 命中即可跳过 `pod install`（配合 `--deployment` 校验） |
| CocoaPods specs 仓库 | `~/.cocoapods` | 体积大且 CDN 模式下不必要，**可选** |
| SwiftPM 缓存 | `~/Library/Caches/org.swift.swiftpm` | v1 只有本地包时影响小；将来接 MPVKit（30+ 二进制 target）时**必须** |
| SwiftPM 检出目录 | 用 `-clonedSourcePackagesDirPath .build/spm` 固定 | 与 `Package.resolved` 绑定 |
| Homebrew（xcodegen） | `~/Library/Caches/Homebrew` + `brew --prefix` | 可选，省 30–60s |

```yaml
- name: Cache CocoaPods
  uses: actions/cache@v4
  with:
    path: |
      ~/Library/Caches/CocoaPods
      Pods
    key: pods-${{ runner.os }}-${{ hashFiles('Podfile.lock') }}
    restore-keys: pods-${{ runner.os }}-

- name: Cache SwiftPM
  uses: actions/cache@v4
  with:
    path: |
      ~/Library/Caches/org.swift.swiftpm
      .build/spm
    key: spm-${{ runner.os }}-xcode26.6-${{ hashFiles('**/Package.resolved') }}
    restore-keys: spm-${{ runner.os }}-xcode26.6-
```

**不要**缓存 `DerivedData`（体积巨大、跨 Xcode 版本易污染），只缓存"下载物"。

---

## 5. 模拟器编译 + 单元测试

### 5.1 动态解析设备（不写死）

```bash
pick_ios_sim() {
  local rt id
  rt=$(xcrun simctl list runtimes -j \
        | jq -r '[.runtimes[]|select(.platform=="iOS" and .isAvailable)]|sort_by(.version)|last|.identifier')
  [ -n "$rt" ] && [ "$rt" != "null" ] || { echo "::error::无可用 iOS 运行时"; return 1; }

  for n in "iPhone 17 Pro" "iPhone 17" "iPhone 17e" "iPhone Air" "iPhone 16e"; do
    id=$(xcrun simctl list devices -j \
          | jq -r --arg rt "$rt" --arg n "$n" \
            '[.devices[$rt][]|select(.isAvailable and .name==$n)][0].udid // empty')
    [ -n "$id" ] && { echo "$id"; return 0; }
  done

  xcrun simctl list devices -j \
    | jq -r --arg rt "$rt" '[.devices[$rt][]|select(.isAvailable and (.name|startswith("iPhone")))][0].udid'
}

SIM_UDID="$(pick_ios_sim)" && echo "SIM_UDID=$SIM_UDID" >> "$GITHUB_ENV"
```

诊断时先看清单：

```bash
xcrun simctl list devices available
xcrun simctl list runtimes
```

### 5.2 测试命令

```bash
set -o pipefail
xcodebuild test \
  -workspace LemonPlayer.xcworkspace \
  -scheme LemonPlayer \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/spm \
  -skipMacroValidation \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO \
  -resultBundlePath .build/test.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify --renderer github
```

- 固定写法（2026 镜像可用，长期不推荐）：`-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`。
- 只编译测试不跑：`build-for-testing`；只跑某包：`-only-testing:LemonSubtitleTests`。
- 覆盖率导出：`xcrun xccov view --report --json .build/test.xcresult`。
- 失败也留证据：`if: always()` 上传 `.build/test.xcresult`。

---

## 6. 未签名 IPA

### 6.1 命令（archive → Payload → zip）

```bash
set -euo pipefail

xcodebuild archive \
  -workspace LemonPlayer.xcworkspace \
  -scheme LemonPlayer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath .build/LemonPlayer.xcarchive \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/spm \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  EXPANDED_CODE_SIGN_IDENTITY="" \
  MARKETING_VERSION="${MARKETING_VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  | xcbeautify --renderer github

APP=".build/LemonPlayer.xcarchive/Products/Applications/LemonPlayer.app"
test -d "$APP" || { echo "::error::.app 未生成"; exit 1; }

rm -rf .build/ipa && mkdir -p .build/ipa/Payload
cp -R "$APP" .build/ipa/Payload/
# -X 去掉扩展属性/资源叉，-y 保留符号链接：否则部分重签工具判定包结构非法
( cd .build/ipa && zip -qry -X ../LemonPlayer-unsigned.ipa Payload )
mv .build/ipa/../LemonPlayer-unsigned.ipa .build/LemonPlayer-unsigned.ipa

shasum -a 256 .build/LemonPlayer-unsigned.ipa | tee .build/SHA256SUMS
```

要点：

- `Payload/` 目录名**大小写敏感**，必须叫 `Payload`，且 `LemonPlayer.app` 直接位于其下；
- 未签名包内**没有** `_CodeSignature/`，直接装会失败，必须由 Sideloadly/AltStore 重签；
- `CODE_SIGNING_ALLOWED=NO` 是**全局** build setting，会同时作用于 Pods 里的 target（否则 Pods target 仍会找 profile 报错）；
- 用 `-destination 'generic/platform=iOS'` 而不是 `-sdk iphoneos`（两者混用会报 conflicting destination，且 `-sdk` 跳过部署目标校验）。

### 6.2 产物自检

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"   # com.lemonplayer.ios
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist"
ls -lh .build/LemonPlayer-unsigned.ipa
ls "$APP/Frameworks" 2>/dev/null || echo "（无动态框架 → VLCKit 静态链接成功）"
```

> 目标：**IPA < 300 MB**（N-06）。MobileVLCKit 下载包 222 MB，单架构 thinned 后安装增量估算 50–90 MB，M1 时回填实测值。

---

## 7. 安装 / 分发路径

### 7.1 无开发者账号：Sideloadly / AltStore（v1 主路径）

| 工具 | 平台 | 说明 |
|---|---|---|
| **Sideloadly** | Windows / macOS | 拖入 IPA + Apple ID → 自动重签安装；最省事 |
| **AltStore** | 需 AltServer 常驻（Mac/PC） | 7 天到期前自动续签，适合长期自用 |

免费 Apple ID 的硬限制：

- 证书 **7 天**过期（过期后 App 打不开，需重新签名安装）；
- 同时最多 **3 个**自签 App；
- 每 7 天最多 **10 个** App ID；
- 不能用需要付费团队的能力（Push / App Groups / Network Extension / iCloud 等）——若 `LemonDownloads` 以后要用 App Group 共享容器，**免费签名会失败**，需提前规划成"应用内目录"；
- 首次安装要在设备上打开「开发者模式」并重启；装完在「设置 → 通用 → VPN与设备管理」里信任证书。

### 7.2 有开发者账号：TestFlight（可选，v1.1 以后）

Xcode 26 支持纯用 **App Store Connect API Key** 做云端自动签名，CI 里不需要导入 `.p12`/`.mobileprovision`：

```bash
xcodebuild archive \
  -workspace LemonPlayer.xcworkspace -scheme LemonPlayer \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .build/LemonPlayer.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath  "$HOME/keys/AuthKey_${ASC_KEY_ID}.p8" \
  -authenticationKeyID    "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID"

xcodebuild -exportArchive \
  -archivePath .build/LemonPlayer.xcarchive \
  -exportPath .build/export \
  -exportOptionsPlist ci/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath  "$HOME/keys/AuthKey_${ASC_KEY_ID}.p8" \
  -authenticationKeyID    "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

`ci/ExportOptions.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key>            <string>app-store-connect</string>
  <key>destination</key>       <string>upload</string>     <!-- export 则只导出不上传 -->
  <key>signingStyle</key>      <string>automatic</string>
  <key>teamID</key>            <string>REPLACE_TEAM_ID</string>
  <key>uploadSymbols</key>     <true/>
  <key>stripSwiftSymbols</key> <true/>
  <key>manageAppVersionAndBuildNumber</key> <false/>
</dict></plist>
```

注意：

- API Key 角色至少 **App Manager**（上传构建需要）；
- 归档前先跑一次 `xcodegen generate` + `pod install`（同 §3）；
- `Info.plist` 里补 `ITSAppUsesNonExemptEncryption = false`，否则 TestFlight 卡"缺少出口合规信息"；
- 上传后进入「处理中」通常 5–20 分钟。

### 7.3 不要做的事

- ❌ 提交 `*.p12` / `*.mobileprovision` / `.p8`；
- ❌ 用 `macos-latest`（版本漂移）；
- ❌ 用 `xcrun altool`（已弃用；用 `-exportArchive` 的 `destination=upload`）；
- ❌ 把 `DerivedData/`、`Pods/`、`build/` 提交进仓库。

---

## 8. `.github/workflows/build.yml` 骨架

```yaml
name: build

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
  workflow_dispatch:

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true          # 同分支新提交取消旧构建：直接省 macOS 分钟

permissions:
  contents: write                   # tag 构建要发 Release

env:
  APP_NAME: LemonPlayer
  SCHEME: LemonPlayer
  WORKSPACE: LemonPlayer.xcworkspace
  XCODE_APP: /Applications/Xcode_26.6.app     # ← 镜像漂移时只改这里
  BUNDLE_ID: com.lemonplayer.ios

jobs:
  # ============================================================ 1) 测试
  test:
    runs-on: macos-26
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: |
          sudo xcode-select -s "${XCODE_APP}"
          xcodebuild -version
          test "$(xcodebuild -version | head -1)" = "Xcode 26.6" || {
            echo "::error::Xcode 版本漂移"; exit 1; }

      - name: Cache CocoaPods
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/CocoaPods
            Pods
          key: pods-${{ runner.os }}-${{ hashFiles('Podfile.lock') }}
          restore-keys: pods-${{ runner.os }}-

      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/org.swift.swiftpm
            .build/spm
          key: spm-${{ runner.os }}-xcode26.6-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-xcode26.6-

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project & install pods
        run: |
          xcodegen generate --spec project.yml
          pod install --deployment

      - name: Pick simulator
        run: |
          rt=$(xcrun simctl list runtimes -j | jq -r '[.runtimes[]|select(.platform=="iOS" and .isAvailable)]|sort_by(.version)|last|.identifier')
          for n in "iPhone 17 Pro" "iPhone 17" "iPhone 17e" "iPhone Air" "iPhone 16e"; do
            id=$(xcrun simctl list devices -j | jq -r --arg rt "$rt" --arg n "$n" '[.devices[$rt][]|select(.isAvailable and .name==$n)][0].udid // empty')
            [ -n "$id" ] && { echo "SIM_UDID=$id" >> "$GITHUB_ENV"; break; }
          done
          [ -n "${SIM_UDID:-}" ] || { echo "::error::无可用模拟器"; exit 1; }

      - name: Test
        run: |
          set -o pipefail
          xcodebuild test \
            -workspace "${WORKSPACE}" -scheme "${SCHEME}" \
            -configuration Debug \
            -destination "platform=iOS Simulator,id=${SIM_UDID}" \
            -derivedDataPath .build/DerivedData \
            -clonedSourcePackagesDirPath .build/spm \
            -skipMacroValidation -enableCodeCoverage YES \
            -resultBundlePath .build/test.xcresult \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify --renderer github

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: xcresult
          path: .build/test.xcresult
          retention-days: 7

  # ==================================================== 2) 未签名 IPA
  unsigned-ipa:
    runs-on: macos-26
    timeout-minutes: 50
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s "${XCODE_APP}"

      - name: Cache CocoaPods
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/CocoaPods
            Pods
          key: pods-${{ runner.os }}-${{ hashFiles('Podfile.lock') }}
          restore-keys: pods-${{ runner.os }}-

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project & install pods
        run: |
          xcodegen generate --spec project.yml
          pod install --deployment

      - name: Compute version
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/v* ]]; then
            echo "MARKETING_VERSION=${GITHUB_REF_NAME#v}" >> "$GITHUB_ENV"
          else
            echo "MARKETING_VERSION=0.0.0" >> "$GITHUB_ENV"
          fi
          echo "BUILD_NUMBER=${GITHUB_RUN_NUMBER}" >> "$GITHUB_ENV"

      - name: Archive (unsigned)
        run: |
          set -o pipefail
          xcodebuild archive \
            -workspace "${WORKSPACE}" -scheme "${SCHEME}" \
            -configuration Release -destination 'generic/platform=iOS' \
            -archivePath .build/LemonPlayer.xcarchive \
            -derivedDataPath .build/DerivedData \
            -clonedSourcePackagesDirPath .build/spm \
            -skipMacroValidation \
            -resultBundlePath .build/archive.xcresult \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" EXPANDED_CODE_SIGN_IDENTITY="" \
            MARKETING_VERSION="${MARKETING_VERSION}" \
            CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
            | xcbeautify --renderer github

      - name: Package IPA
        run: |
          set -euo pipefail
          APP=".build/LemonPlayer.xcarchive/Products/Applications/${APP_NAME}.app"
          test -d "$APP" || { echo "::error::.app missing"; exit 1; }
          rm -rf .build/ipa && mkdir -p .build/ipa/Payload
          cp -R "$APP" .build/ipa/Payload/
          ( cd .build/ipa && zip -qry -X "../${APP_NAME}-unsigned.ipa" Payload )
          mv ".build/ipa/../${APP_NAME}-unsigned.ipa" ".build/${APP_NAME}-unsigned.ipa"
          /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"
          shasum -a 256 ".build/${APP_NAME}-unsigned.ipa" | tee .build/SHA256SUMS
          ls -lh ".build/${APP_NAME}-unsigned.ipa"

      - uses: actions/upload-artifact@v4
        with:
          name: LemonPlayer-unsigned-ipa
          path: |
            .build/LemonPlayer-unsigned.ipa
            .build/SHA256SUMS
          if-no-files-found: error
          retention-days: 14

  # ==================================== 3) tag：附到 GitHub Release
  release:
    needs: [unsigned-ipa]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: macos-26
    timeout-minutes: 15
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: LemonPlayer-unsigned-ipa
          path: dist

      - uses: softprops/action-gh-release@v2
        with:
          files: |
            dist/LemonPlayer-unsigned.ipa
            dist/SHA256SUMS
          body: |
            未签名 IPA（自签用）。安装方式见 docs/tech/CI_BUILD.md §7.1。
            免费 Apple ID 签名 7 天过期。

  # ============================== 4) 可选：签 & 上 TestFlight
  # 仓库 Variable ENABLE_SIGNING=true 才跑（secrets 不能用在 job 级 if）
  testflight:
    needs: [test, unsigned-ipa]
    if: github.event_name == 'push' && vars.ENABLE_SIGNING == 'true'
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s "${XCODE_APP}"

      - name: Install ASC key
        run: |
          mkdir -p "$HOME/keys"
          echo "${{ secrets.ASC_KEY_P8_BASE64 }}" | base64 --decode \
            > "$HOME/keys/AuthKey_${{ secrets.ASC_KEY_ID }}.p8"
          chmod 600 "$HOME/keys/AuthKey_${{ secrets.ASC_KEY_ID }}.p8"

      - name: Generate project & install pods
        run: |
          brew install xcodegen
          xcodegen generate --spec project.yml
          pod install --deployment

      - name: Archive & upload
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          set -o pipefail
          plist="$HOME/keys/AuthKey_${ASC_KEY_ID}.p8"
          xcodebuild archive \
            -workspace "${WORKSPACE}" -scheme "${SCHEME}" \
            -configuration Release -destination 'generic/platform=iOS' \
            -archivePath .build/LemonPlayer.xcarchive \
            -derivedDataPath .build/DerivedData -skipMacroValidation \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$plist" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER}" \
            | xcbeautify --renderer github

          sed "s/REPLACE_TEAM_ID/${TEAM_ID}/" ci/ExportOptions.plist > .build/ExportOptions.plist
          xcodebuild -exportArchive \
            -archivePath .build/LemonPlayer.xcarchive \
            -exportPath .build/export \
            -exportOptionsPlist .build/ExportOptions.plist \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$plist" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

### 8.1 每段为什么这么写

| 段 | 作用 / 原因 |
|---|---|
| `on` + `concurrency` | PR 只跑测试；tag 才出包+发版。`cancel-in-progress` 让新提交立刻停旧构建，省 macOS 分钟 |
| `permissions: contents: write` | `softprops/action-gh-release` 需要写权限 |
| `env.XCODE_APP` | 唯一跟随镜像更新的旋钮；配 `Select Xcode` 的断言做 fail-fast |
| `Cache CocoaPods` | MobileVLCKit 下载包 222 MB；命中后 `pod install` 秒级完成 |
| `Cache SwiftPM` | v1 只有本地包时作用小；接 MPVKit（30+ 二进制 target）后是刚需，key 里带 Xcode 版本避免跨版本污染 |
| `Install XcodeGen` | 镜像未预装；`brew install` 约 30–60s |
| `Generate project & install pods` | **顺序不能反**：`xcodegen` 先产出 `.xcodeproj`，`pod install` 才能注入 |
| `Pick simulator` | 运行时解析，避免镜像升级后 `destination` 找不到设备 |
| `Test` | `xcbeautify` 输出 GitHub 注解；`.xcresult` 留证据；`CODE_SIGNING_ALLOWED=NO` 避免模拟器测试被签名卡住 |
| `Archive (unsigned)` | 核心出包：`generic/platform=iOS` + 四重签名关闭 + 版本号注入 |
| `Package IPA` | `Payload/` + `zip -X`；`PlistBuddy` 打印 bundle id 做自检 |
| `release` | tag 触发，把 IPA + SHA256 附到 Release（ADR-006） |
| `testflight` | 全部由 secret 门控；没有账号时这一步永远不跑 |

### 8.2 需要用户填的变量 / Secret

| 名称 | 类型 | 用途 | 必须？ |
|---|---|---|---|
| `XCODE_APP` | workflow `env` | 锁 Xcode 版本 | 已给默认值，镜像升级时改 |
| `BUNDLE_ID` | workflow `env` | `com.lemonplayer.ios` | 已给 |
| `ENABLE_SIGNING` | **仓库 Variable** | 开关 TestFlight job（`secrets` 不能用于 job 级 `if`） | 可选 |
| `APPLE_TEAM_ID` | Secret | `DEVELOPMENT_TEAM`（10 位） | 签名时必须 |
| `ASC_KEY_ID` | Secret | App Store Connect API Key 的 Key ID | 签名时必须 |
| `ASC_ISSUER_ID` | Secret | Issuer ID（UUID） | 签名时必须 |
| `ASC_KEY_P8_BASE64` | Secret | `AuthKey_XXX.p8` 的 base64（不要提交明文 .p8） | 签名时必须 |
| `TMDB_API_KEY` | Secret | TMDB 刮削：构建时 `xcodebuild ... TMDB_API_KEY=...`，Info.plist 里写 `$(TMDB_API_KEY)` | M5 起可选 |
| `BUILD_CERT_BASE64` / `BUILD_CERT_PASSWORD` / `PROVISIONING_PROFILE_BASE64` | Secret | 仅当改走手动签名/fastlane match 时需要 | 可选 |
| 光鸭云盘凭据 | **不进 CI** | 用户在 App 内登录 / 自备 token 走 DEBUG 入口（ADR-002） | — |

> `TMDB_API_KEY` 的注入方式：Info.plist 写 `<string>$(TMDB_API_KEY)</string>`，构建时作为 build setting 传进去，Xcode 拷 Info.plist 时替换。**不要**硬编码进 Swift 源码。

### 8.3 与仓库现有 `build.yml`（M0 版本）的差异清单

现有工作流已经能跑通「XcodeGen → 模拟器构建 → main 分支出未签名 IPA」，可直接用；下表是**建议逐步补齐的部分**（按优先级）：

| 优先级 | 差异 | 现有写法 | 建议改成 | 原因 |
|---|---|---|---|---|
| **P0** | zip 未加 `-X` | `zip -qr LemonPlayer-unsigned.ipa Payload` | `zip -qry -X ...` | 避免 `__MACOSX`/扩展属性导致重签工具判包结构非法；`-y` 保留符号链接 |
| **P0** | 无 Xcode 版本断言 | 只 `xcode-select -s` | 加 `test "$(xcodebuild -version\|head -1)" = "Xcode 26.6"` | 镜像周更，默认版本会漂移 |
| **P1** | 用 `-sdk iphoneos` | `-sdk iphoneos` | `-destination 'generic/platform=iOS'` | 与 `-destination` 混用会冲突；`-sdk` 跳过部署目标校验 |
| **P1** | 无 tag 发布 | 只在 main 上传 artifact | 加 `release` job（tag `v*` → GitHub Release + SHA256） | ADR-006 要求"打 tag 附 IPA 与校验和" |
| **P1** | 无依赖缓存 | — | 加 CocoaPods/SPM 缓存（§4） | 引入 MobileVLCKit 后 `pod install` 冷启动 ~2 分钟 |
| **P1** | 单测是 `swift test --package-path` | 逐个包跑 | 保留（快速）+ 加 `xcodebuild test`（App 层与 UI 相关） | 纯逻辑包用 `swift test` 最快；App target 只能 `xcodebuild test` |
| **P2** | 无 `.xcresult` 留存 | — | `-resultBundlePath` + `if: always()` 上传 | 失败时能定位到具体断言 |
| **P2** | 出包只在 main | `if: github.ref == 'refs/heads/main'` | 加 `workflow_dispatch` 手动触发 | 需要随时手动出包验证 |

---

## 9. 常见坑

### 9.1 Xcode 26 / Swift 版本与严格并发

| Xcode | Swift |
|---|---|
| 26.0 ~ 26.3 | Swift 6.2.x（26.2 为 6.2.3） |
| **26.4 及以上（含 26.6）** | **Swift 6.3** |

（来源：Apple Xcode 26.4 Release Notes「includes Swift 6.3」、Xcode 26.2 Release Notes「includes Swift 6.2.3」）

- Swift 6.2 起，新工程模板默认 `SWIFT_APPROACHABLE_CONCURRENCY = YES` + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。好处是 UI 代码默认主线程；坏处是**后台队列代码会因为没有显式 `@MainActor`/`Sendable` 而编译失败**。
- VLCKit 是 ObjC（不受影响），但**我们自己的回调桥接层**会受影响：`VLCMediaPlayerDelegate` 回调在后台线程 → 必须 `Task { @MainActor in ... }` 或 `AsyncStream` 中转，否则 Swift 6.3 直接报错。
- 不要用 `SWIFT_STRICT_CONCURRENCY=minimal` 在 CI 里掩盖问题——它会把问题推到上架前。
- 不要开 `SWIFT_TREAT_WARNINGS_AS_ERRORS`：一次 SDK 升级就会红一片。

### 9.2 新 SDK 弃用 API

- iOS 26 SDK 会对一批旧写法给出弃用警告（`AVAsset(url:)` 一类的便利构造、`UIScreen.main` 一类的全局查询等）。编译不失败，但会淹没日志。
- 集中清理：`xcodebuild ... 2>&1 | grep -i deprecat | sort -u`，一次 PR 清完。
- Xcode 26 对过低的 `IPHONEOS_DEPLOYMENT_TARGET` 会警告；本项目统一 **26.0**（Pods 里的 target 用 `post_install` 一起抬到 26.0，否则会有一堆黄色警告）。

### 9.3 SPM 二进制 target 的缓存坑（接 MPVKit 后必读）

1. **缓存了源码但没缓存 artifact**：`SourcePackages` 命中但 `artifacts/` 缺失时，Xcode 会静默重新下载——日志停在 `Resolve Package Graph` 十几分钟，看着像卡死。对策：缓存整个 `.build/spm`，并给该步单独设 `timeout-minutes`。
2. **checksum 变更**：上游重传 release 资产会导致校验失败（极少见）。删 cache 重跑。
3. **跨 Xcode 版本复用**：xcframework 一般没问题，但**宏插件**（swift-syntax 系）编译产物跨版本会崩。对策：cache key 里带 Xcode 版本。
4. **磁盘**：标准 runner 可用空间有限，MPVKit（几百 MB）+ DerivedData 可能触发 `No space left on device`。对策：构建后删 `.build/DerivedData/Build/Intermediates.noindex`，或换 `macos-26-xlarge`（$0.102/分钟）。

### 9.4 计费与时长

- 私有仓库（本项目，ADR-012）：**标准 macOS runner $0.062/分钟**，约为 Linux（$0.006）的 10 倍。
- 免费额度是按金额折算的（Free 计划历来约等于 2,000 Linux 分钟/月）；macOS 单价是 Linux 的 ~10 倍 → **实际可用 macOS 分钟 ≈ 额度的 1/10**。具体额度以仓库 Billing 页为准。
- 一次"测试 + 出包"双 job ≈ 25–35 分钟 ≈ **$1.5–2.2**；一天 10 次提交 ≈ $20，**必须**做下面几件事：
  - `concurrency.cancel-in-progress`；
  - PR 只跑 `test`，出包 job 用 `if` 门控到 `main`/tag；
  - 缓存 CocoaPods（省 3–5 分钟）；
  - `timeout-minutes` 兜底（卡死不会烧到 6 小时）。
- 缓存本身也计费（仓库缓存配额约 10 GB，超出按 GB/月）：定期删旧 key。

### 9.5 其它

- **XcodeGen + CocoaPods 顺序**：先 `xcodegen generate`，再 `pod install`；反了会生成指向不存在工程的 `.xcworkspace`。
- **`pod install --deployment`**：`Podfile.lock` 与 `Pods/` 不一致会直接失败——这是"防漂移"而不是"添麻烦"。
- **`zip` 资源叉**：不加 `-X` 会写入 `__MACOSX/`，部分重签工具判非法。
- **`Payload` 大小写**：必须精确。
- **artifact 过期**：默认 90 天，出包产物建议显式 `retention-days: 14`。
- **模拟器 runtime 未安装**：极少数镜像裁剪会缺 iOS 26.5，`simctl list runtimes` 看不到就用 `xcodes runtimes install "iOS 26.5"`（慢，尽量别依赖）。
- **`.gitignore`**：`build/`、`.build/`、`Pods/`、`*.xcresult`、`DerivedData/`、`*.ipa`、`*.p12`、`*.mobileprovision`、`*.p8`。

---

## 10. 本地复现（等价命令，macOS）

```bash
sudo xcode-select -s /Applications/Xcode_26.6.app
brew install xcodegen
xcodegen generate --spec project.yml
pod install --deployment

xcodebuild archive -workspace LemonPlayer.xcworkspace -scheme LemonPlayer \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .build/LemonPlayer.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

rm -rf .build/ipa && mkdir -p .build/ipa/Payload
cp -R .build/LemonPlayer.xcarchive/Products/Applications/LemonPlayer.app .build/ipa/Payload/
(cd .build/ipa && zip -qry -X ../LemonPlayer-unsigned.ipa Payload)
unzip -l .build/LemonPlayer-unsigned.ipa | head
```

> Windows 开发机上只能改代码/看日志；本机若需访问 GitHub，用 `$env:HTTPS_PROXY='http://127.0.0.1:7890'` 之类的代理配置（仅影响本机 git/curl，不影响 CI）。

---

## 11. 第一次跑通要回填的项（写回 `docs/PROGRESS.md`）

- [ ] `brew install xcodegen` 在 macos-26 上的实际耗时与版本
- [ ] `pod install --deployment` 冷/热耗时（热 ≤ 10s 才算缓存成功）
- [ ] MobileVLCKit 3.7.5 在 Xcode 26.6 下是否有阻塞性警告/错误
- [ ] `xcodegen` 生成的工程与 `use_frameworks! :linkage => :static` 是否兼容（`.app/Frameworks/` 是否为空）
- [ ] `simctl` 实际解析到的设备名与 runtime
- [ ] 未签名 IPA 的实际体积（目标 < 300 MB，N-06）
- [ ] 一次完整 CI 的实际 macOS 分钟数（用于估算月度成本）

---

## 12. 事实来源（抓取时间 2026-11-03）

- `macos-26` 标签与架构、镜像明细（macOS 26.6.2 / 镜像 `20261026.0455.2` / Xcode 26.0.1–26.6、默认 26.6 17F113 / CocoaPods 1.17.0 / xcbeautify 3.2.1 / Xcodes 2.1.0 / iOS 26.2/26.4/26.5 模拟器清单）：<https://github.com/actions/runner-images>、<https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md>
- 标签/架构对照（`macos-26` = arm64，`macos-26-intel`/`-large` = x64，`macos-latest` → macos-26）：<https://raw.githubusercontent.com/actions/runner-images/main/README.md>
- 默认 Xcode 于 2026-07-21 切到 26.6：<https://github.com/actions/runner-images/issues/14344>
- macOS 14 镜像 2026-11-02 退役：<https://github.com/actions/runner-images/issues/15226>
- Xcode 27 预览镜像：<https://github.com/actions/runner-images/issues/14404>
- Actions 分钟单价（macOS 3/4 核 `$0.062`、Linux `$0.006`、macOS xlarge `$0.102`）：<https://docs.github.com/en/billing/reference/actions-minute-multipliers>、<https://docs.github.com/en/billing/concepts/product-billing/github-actions>
- 2026-04-28 起必须用 iOS 26 SDK 上传（2026-02-03 公告）：<https://developer.apple.com/news/?id=ueeok6yw>
- 各 Xcode 版本内置的 Swift 版本：[Xcode 26.4 Release Notes（Swift 6.3）](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes)、[Xcode 26.2 Release Notes（Swift 6.2.3）](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_2-release-notes)
- `xcodes` CLI：<https://github.com/XcodesOrg/xcodes>
- 内核相关版本/许可依据见 [`PLAYER_KERNEL.md` §8](PLAYER_KERNEL.md)
