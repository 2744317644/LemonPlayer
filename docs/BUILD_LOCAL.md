# 本地构建 IPA（不依赖 GitHub Actions）

> 适用：GitHub Actions 额度用尽 / 计费受限时，用一台 Mac 出未签名 IPA。

## 前置

- macOS 15+，Xcode 26.x（`xcode-select -p` 指向 Xcode 26）
- Homebrew 安装：`brew install xcodegen cocoapods`

## 一键构建

```bash
git clone https://github.com/2744317644/LemonPlayer.git
cd LemonPlayer
bash scripts/build-local.sh
```

产物：`.build/LemonPlayer-unsigned.ipa` + `.sha256`。

## 手动步骤（等价）

```bash
xcodegen generate --spec project.yml
pod install
xcodebuild archive \
  -workspace LemonPlayer.xcworkspace \
  -scheme LemonPlayer \
  -configuration Release \
  -sdk iphoneos \
  -archivePath .build/LemonPlayer.xcarchive \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir -p .build/Payload
cp -R .build/LemonPlayer.xcarchive/Products/Applications/LemonPlayer.app .build/Payload/
cd .build && zip -qrX LemonPlayer-unsigned.ipa Payload

# 发布到 GitHub Release（示例）
gh release create v1.0.3 \
  --title "v1.0.3" \
  --notes "文件接口修复 + 新图标" \
  LemonPlayer-unsigned.ipa LemonPlayer-unsigned.ipa.sha256
```

## 安装

`LemonPlayer-unsigned.ipa` 用 Sideloadly / AltStore 自签安装（7 天有效，覆盖安装保留数据）。

## 另一种选择：临时公开仓库换取免费 Actions

GitHub 对 **public 仓库**的 standard runners 免费（含 macOS）。若可以短暂公开：

1. Settings → General → Danger Zone → Change visibility → **Make public**
2. Actions 里重跑 `build`（或 push 一次）
3. 下载 artifact / Release
4. 再改回 private

> 公开期间任何人都能看到源码（本仓库无密钥、无证书；`.gitignore` 已排除本地探测脚本）。
