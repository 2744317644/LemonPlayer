# 回归清单（发布前必跑）

> 每轮迭代结束 / 发版前执行；结果记录到 `docs/PROGRESS.md` 日志。
> 当前版本：M2（登录 + 目录浏览）

## 自动化（CI）

| 编号 | 项目 | 命令 | 通过标准 |
|---|---|---|---|
| A-01 | 包内单测 | `swift test --package-path Packages/LemonCore` 等 4 个包 | 全绿 |
| A-02 | 模拟器构建 | `xcodebuild build -scheme LemonPlayer -destination generic/platform=iOS Simulator` | 成功 |
| A-03 | 未签名 IPA | `xcodebuild archive ... CODE_SIGNING_ALLOWED=NO` + Payload/zip | 产出 artifact |

## 手工（真机）

### M2：登录与浏览

| 编号 | 步骤 | 预期 |
|---|---|---|
| J-01a | 首次启动 | 展示登录页与二维码，2 分钟内可扫 |
| J-01b | 用光鸭 App 扫码确认 | 5 秒内进入「网盘」页 |
| J-01c | 杀进程重开 | 自动进入主页（无需重扫） |
| J-01d | 等待 access_token 过期后浏览 | 自动刷新，不打断操作 |
| J-02a | 浏览根目录 | 列表显示文件/目录、大小、时间 |
| J-02b | 进入子目录 → 返回上一级 | 面包屑正确，列表刷新 |
| J-02c | 切换排序（时间/名称） | 顺序变化，且刷新后保持 |
| J-02d | 下拉刷新 | 重新拉取第一页 |
| J-02e | 断网后浏览 | 显示错误与重试按钮，不闪退 |
| J-02f | 退出登录 | 回到登录页，Keychain 凭据清除 |

### 已知未覆盖（后续里程碑）

- 播放、字幕、媒体库、下载、画中画/AirPlay：见 REQUIREMENTS 的 J-01~J-05。

## 记录模板

```
日期：
构建版本 / commit：
Android/iOS 版本：
执行人：
结果：A-01 ✅ A-02 ✅ A-03 ✅ / J-01a ✅ ...
问题：
```
