# 刮削规则与开发者 API（v1.0.5）

## 一、目录 → 番剧的归类规则

1. **以最底层文件夹作为一部番剧**：同一文件夹下的 `01.mkv`、`02.mkv`… 归为同一部。
2. **附属目录向上取父目录**：`Fonts`、`OP`、`ED`、`OP&ED`、`SPs`、`Scans`、`CDs`、`Menu`、`Extras`、`特典`、`字幕`、`映像特典`、`预告` 等目录里的文件不算正片；
   如果最底层目录是这些名字，就把**上一级目录**当番剧目录。
3. **季目录/画质目录也向上**：`Season 1`、`S02`、`第二季`、`1080p HEVC 简繁` 这类包装目录继续向上找。
4. **同名目录合并**：同一部番被拆到多个同名目录（不同季/重复目录）时按清洗后的标题合并。
5. **只收视频**：`fileType=2` 或视频扩展名（mkv/mp4/ts/m2ts/avi…）；字幕、字体、图片、音乐不参与。

## 二、标题清洗与识别

- 去 `[字幕组]`、`[Ma10p_1080p]`、`[BDRip]` 等括号与画质/编码标记；
- **保留季标记**（`第三季`、`S02`、`②`、`∬`），否则第三季会被匹配成第二季；
- 罗马音/英文名直接作为关键词搜 Bangumi（Bangumi 本身索引别名）；
- 匹配策略：取前 5 个候选 → 归一化相似度（Levenshtein 比例）+ 季数加权（+0.3 / 错季 -0.25）；
  相似度 < 0.55、或要求第 N 季但候选没有该季标记 → 判未匹配，宁缺毋滥；
- **非番剧跳过**：LIVE/演唱会/Music Video/歌曲欣赏/谈话/广播/花絮 等不做番剧匹配；
- Bangumi 未命中时可选 TMDB 兜底（设置里填 API Key）。

## 三、开发者 API（可选，仅用于本地刮削工具）

官方文档：光鸭开发者 API v1.1（`https://dapi.guangyapan.com`）。

| 项 | 说明 |
|---|---|
| 凭据 | 会员账号 → TOKEN 管理 → 成为开发者，得到 `client_id` / `client_secret` |
| 请求头 | `client_id`、`nonce`（16–32 位随机）、`timestamp`（Unix 秒）、`sign` |
| 签名 | `source = client_id=&client_secret=&nonce=&timestamp=` → `hex(sha512(md5_raw_bytes(source)))` |
| 列目录 | `POST /userres/v1/file/get_file_list`（body: parentId/page/pageSize/orderBy/sortType） |
| 限制 | 同时有效开发者凭据 2 个；接收方 TOKEN 只用于 `/developer/v1` 上传转移，**不能读列表** |

> ⚠️ 不要把 `client_secret` / 接收方 TOKEN 提交到仓库或日志；本地脚本用参数传入，输出写到 `.tmp/`（已 gitignore）。

## 四、本地演练脚本

```bash
# 1) 不需要凭据，先用内置示例树验证规则
python scripts/guangya_scrape.py --mock

# 2) 真实扫描（开发者凭据）
python scripts/guangya_scrape.py \
  --client-id <client_id> --client-secret <client_secret> \
  --out .tmp/scrape-live
```

输出：`.tmp/scrape-live.md` / `.json`（目录 → 番剧 → Bangumi 匹配结果）。

## 五、实测结果（2026-11-06，用户网盘）

- 递归扫描 **1163 个目录 / 20 部番剧**（并发 8，约 1 分钟）
- 季数匹配正确：`约会大作战 第三季/第四季/第五季` 分别命中对应 Bangumi 条目
- 非番剧（Animelo LIVE、Music Video、歌曲欣赏、谈话）自动跳过
- 剧场版、日文原名（からかい上手の高木さん②/③、五等分の花嫁∬/∽）均正确识别

## 六、App 内实现位置

| 层 | 文件 |
|---|---|
| 目录规则 | `Packages/LemonMedia/Sources/LemonMedia/SeriesFolderResolver.swift` |
| 标题匹配 | `Packages/LemonMedia/Sources/LemonMedia/TitleMatcher.swift` |
| 分组编排 | `Packages/LemonMedia/Sources/LemonMedia/LibraryScraper.swift` |
| 递归扫描 | `Packages/LemonGuangya/Sources/LemonGuangya/Files/GuangyaFileService.swift`（`listAllMedia`） |
| 媒体库状态机 | `Sources/LemonPlayer/Features/Library/LibraryViewModel.swift` |
| 本地演练脚本 | `scripts/guangya_scrape.py` |
