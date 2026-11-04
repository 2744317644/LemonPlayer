#!/bin/bash
# 在 macOS 上本地构建 LemonPlayer 未签名 IPA（不依赖 GitHub Actions）
# 依赖：Xcode 26+、xcodegen、cocoapods、zip
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
echo "== 仓库：$ROOT"

command -v xcodegen >/dev/null || { echo "缺少 xcodegen：brew install xcodegen"; exit 1; }
command -v pod >/dev/null || { echo "缺少 CocoaPods：brew install cocoapods"; exit 1; }

echo "== 生成工程"
xcodegen generate --spec project.yml

echo "== 安装 Pods"
pod install

echo "== 归档（未签名）"
rm -rf .build/LemonPlayer.xcarchive .build/Payload
xcodebuild archive \
  -workspace LemonPlayer.xcworkspace \
  -scheme LemonPlayer \
  -configuration Release \
  -sdk iphoneos \
  -archivePath .build/LemonPlayer.xcarchive \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

echo "== 打包 IPA"
mkdir -p .build/Payload
cp -R .build/LemonPlayer.xcarchive/Products/Applications/LemonPlayer.app .build/Payload/
cd .build
zip -qrX LemonPlayer-unsigned.ipa Payload
shasum -a 256 LemonPlayer-unsigned.ipa | tee LemonPlayer-unsigned.ipa.sha256
du -h LemonPlayer-unsigned.ipa
echo "== 完成：$ROOT/.build/LemonPlayer-unsigned.ipa"
