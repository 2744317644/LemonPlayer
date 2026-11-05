# 开发期看真机画面（Windows）

DSH 的 `ios_sim_*` 工具需要 macOS + Xcode，本机是 Windows，用不了。
但可以用 Windows 上的 USB 投屏工具 **抓帧 + OCR**，实现"近实时看 App 状态"。

## 需要你做的

1. **下载工具**：[IosScreenCaptureTool](https://github.com/BieleckiLtd/IosScreenCaptureTool/releases)
   （Windows / USB 投屏 iPhone、iPad，MIT 协议）
2. 解压到例如 `E:\Tools\IosScreenCaptureTool.exe`
3. iPhone 数据线连电脑 → 手机上点「信任」
4. 打开工具（能看到手机画面即成功；保持运行）

## 我能做的（抓帧 + 读屏）

```powershell
# 抓一帧
python scripts/ios_capture.py --exe "E:\Tools\IosScreenCaptureTool.exe" --out .tmp\frames

# 抓一帧并 OCR（只看下半屏，适合校验字幕/控制条）
python scripts/ios_capture.py --exe "E:\Tools\IosScreenCaptureTool.exe" --out .tmp\frames --ocr --bottom 0.55

# 连续抓 5 帧（间隔 1 秒），用来观察播放/字幕是否在动
python scripts/ios_capture.py --exe "E:\Tools\IosScreenCaptureTool.exe" --out .tmp\frames --count 5 --interval 1
```

抓到的 PNG 在 `.tmp/frames/`；OCR 输出每行文字 + y 坐标，例如：

```
# frame-20261106-093012.png  2556x1179
[y=  1120] 字幕：示例字幕
[y=  1090] 00:55  26:14
```

由此可以判断：

- **方向**：`width > height` 即横屏（用来验证"进播放器默认横屏/回前台仍横屏"）；
- **字幕是否显示**：下半屏 OCR 出现字幕文本 → 内核/自绘字幕生效；
- **错误提示**：直接读到"字幕下载失败（HTTP 403）"这类文案；
- **状态**：按钮标签、时间、进度提示（如"已跳转到上次位置"是否自动消失）。

## 限制

- 我**看不到实时视频**（文本模型），只能按需抓帧 + OCR；工具窗口本身你可以实时看。
- 该工具只读画面，**不能代替点击**。真机上的操作还是你点；自动化点击需要 macOS 上的 WebDriverAgent（我们用 GitHub Actions 的 XCUITest 覆盖）。
- 抓帧耗时约 0.5–1.5s/帧，足够做"改完→重新装→抓一帧确认"的闭环。

## 闭环建议

改代码 → 推送 → CI 出 IPA → 你安装 → 你把手机停在目标界面 → 我抓帧 OCR 确认。
比来回发截图快很多，也避免我"猜"界面状态。

## 相关脚本

| 脚本 | 作用 |
|---|---|
| `scripts/ios_capture.py` | 调 IosScreenCaptureTool 抓帧（可循环、可接 OCR） |
| `scripts/ocr_png.py` | Windows.Media.Ocr（zh-Hans）读任意 PNG 文字 |
