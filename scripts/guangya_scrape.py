#!/usr/bin/env python3
"""光鸭云盘刮削演练脚本（Windows 本地可跑）。

两种数据来源：
1. --mock：内置一颗示例目录树，不需要任何凭据，用来演练「最底层文件夹分类 +
   Fonts/OP/ED/SPs 向上取父目录 + 罗马音标题清洗 + Bangumi 匹配」。
2. 开发者凭据（--client-id/--client-secret）：按光鸭开发者 API v1.1 签名鉴权，
   用 https://dapi.guangyapan.com 的 /userres/v1/file/get_file_list 递归列盘。

注意：接收方 TOKEN（形如 TOKEN2026...）只用于 /developer/v1 上传转移，
不能读取文件列表；刮削需要开发者 client_id/client_secret（会员账号
「TOKEN 管理 → 成为开发者」）。

签名算法（官方文档）：
  source = client_id=&client_secret=&nonce=&timestamp=
  sign = hex(sha512(md5_raw_bytes(source)))
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import secrets
import string
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

# Windows 控制台默认 GBK，标题里出现 ∬ 等字符会崩；统一 UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

DAPI = "https://dapi.guangyapan.com"
BGM_SEARCH = "https://api.bgm.tv/v0/search/subjects"
UA = "LemonPlayer/1.0 (scrape-practice)"

NOISE_TOKENS = {
    "font", "fonts", "op", "ops", "ed", "eds", "oped", "opeds",
    "sp", "sps", "special", "specials", "ncop", "nced", "nc", "menu",
    "scan", "scans", "cd", "cds", "ost", "soundtrack", "music", "mv",
    "pv", "preview", "cm", "extras", "extra", "bonus", "tokuten",
    "sub", "subs", "subtitle", "subtitles", "booklet", "artbook", "art",
    "creditless", "clean", "logo", "trailer", "teaser", "sample",
}
NOISE_CN = ["字体", "字幕", "特典", "映像", "番外", "原声", "画集", "周边",
            "歌词", "歌詞", "预告", "花絮", "扫描", "扫图", "音乐", "菜单"]
QUALITY = {
    "1080p", "720p", "2160p", "480p", "4k", "8bit", "10bit", "hevc", "avc",
    "x264", "x265", "h264", "h265", "bdrip", "webrip", "web-dl", "webdl",
    "bluray", "blu-ray", "flac", "aac", "chs", "cht", "gb", "big5",
    "简繁", "简中", "繁中", "内封", "内嵌", "外挂", "双语",
}


@dataclass
class Node:
    id: str
    name: str
    parent_id: str
    is_folder: bool
    file_type: int | None = None
    children: list[str] = field(default_factory=list)


VIDEO_EXTS = {
    "mkv", "mp4", "m4v", "mov", "ts", "m2ts", "mts", "avi", "webm",
    "flv", "wmv", "rmvb", "rm", "mpg", "mpeg", "vob", "iso",
}


def is_noise_file(name: str) -> bool:
    """NCOP/NCED/OP/ED/PV/CM/SP/Menu 这类附属视频不算正片。"""
    base = name.rsplit(".", 1)[0]
    candidates = re.findall(r"[\[【（(]([^\]】）)]+)[\]】）)]", base) + [base]
    for candidate in candidates:
        lowered = candidate.lower()
        tokens = [t for t in re.split(r"[^0-9a-z]+", lowered) if t]
        if any(t in NOISE_TOKENS for t in tokens):
            return True
        if re.match(r"^(ncop|nced|op|ed|sp|pv|cm)\d{0,3}(?:[\s\-_]|$)", lowered):
            return True
    return False


def is_video_file(node: Node) -> bool:
    if node.file_type == 2:
        return True
    ext = node.name.rsplit(".", 1)[-1].lower() if "." in node.name else ""
    return ext in VIDEO_EXTS


@dataclass
class SeriesGroup:
    folder_id: str
    folder_name: str
    title: str
    files: list[Node] = field(default_factory=list)
    bangumi_id: int | None = None
    bangumi_title: str | None = None
    episode_titles: dict[int, str] = field(default_factory=dict)


# ---------------------------------------------------------------- 目录规则

def is_noise_folder(name: str) -> bool:
    stripped = name.strip()
    if not stripped:
        return False
    if any(keyword in stripped for keyword in NOISE_CN):
        return True
    tokens = [t for t in re.split(r"[^0-9A-Za-z]+", stripped.lower()) if t]
    if not tokens:
        return False
    if all(token in NOISE_TOKENS for token in tokens):
        return True
    return len(tokens) == 1 and tokens[0] in NOISE_TOKENS


def is_season_folder(name: str) -> bool:
    lowered = name.lower().replace(" ", "").replace("_", "")
    return bool(
        re.fullmatch(r"(season|s)\d{1,2}", lowered)
        or re.fullmatch(r"第[0-9一二三四五六七八九十]+季", name)
    )


def is_quality_folder(name: str) -> bool:
    stripped = re.sub(r"[\[\]()（）【】_]", " ", name.lower())
    words = [w for w in re.split(r"[^0-9A-Za-z\u4e00-\u9fff]+", stripped) if w]
    if not words:
        return False
    hits = [w for w in words if w in QUALITY or re.fullmatch(r"\d{3,4}p", w)]
    return len(hits) >= max(1, len(words) - 1)


def clean_title(raw: str) -> str:
    text = raw
    for pattern in (r"\[[^\]]*\]", r"\([^)]*\)", r"【[^】]*】", r"（[^）]*）"):
        text = re.sub(pattern, " ", text)
    text = re.sub(
        r"(?i)\b(\d{3,4}p|4k|8bit|10bit|hevc|avc|x264|x265|h264|h265|bdrip|webrip|web-dl|bluray|flac|aac|chs|cht)\b",
        " ",
        text,
    )
    text = re.sub(r"(?i)\b(season\s*\d{1,2}|s\d{1,2})\b", " ", text)
    text = re.sub(r"第[0-9一二三四五六七八九十]+季", " ", text)
    text = text.replace("_", " ").replace(".", " ")
    text = re.sub(r"\s+", " ", text).strip(" -–—~·:：,，")

    if text:
        return text

    # 整名都在括号里：取最像标题的一段
    candidates = re.findall(r"[\[【（(]([^\]】）)]+)[\]】）)]", raw)
    scored = [
        c for c in candidates
        if not is_noise_folder(c) and not is_quality_folder(c)
    ]
    if not scored:
        return raw
    return max(scored, key=lambda c: (bool(re.search(r"[\u4e00-\u9fff]", c)), c.count(" "), len(c)))


def resolve_series_folder(node_id: str, nodes: dict[str, Node], max_depth: int = 8) -> Node | None:
    current = node_id
    last = None
    depth = 0
    while depth < max_depth and current and current in nodes:
        node = nodes[current]
        last = node
        if is_noise_folder(node.name) or is_season_folder(node.name) or is_quality_folder(node.name):
            current = node.parent_id
            depth += 1
            continue
        return node
    return last


def search_title(title: str) -> str:
    """搜索用标题：去括号/画质，但保留季数标记（第三季/②/∬）。"""
    text = title
    for pattern in (r"\[[^\]]*\]", r"\([^)]*\)", r"【[^】]*】", r"（[^）]*）"):
        text = re.sub(pattern, " ", text)
    text = re.sub(
        r"(?i)\b(\d{3,4}p|4k|8bit|10bit|hevc|avc|x264|x265|h264|h265|bdrip|webrip|web-dl|bluray|flac|aac|chs|cht)\b",
        " ",
        text,
    )
    text = text.replace("_", " ").replace(".", " ")
    return re.sub(r"\s+", " ", text).strip(" -–—~·:：,，") or title


def search_keywords(title: str) -> list[str]:
    cleaned = clean_title(title)
    keys = [cleaned] if cleaned else []
    stripped = re.sub(r"[^\w\s]", " ", cleaned, flags=re.UNICODE)
    stripped = re.sub(r"\s+", " ", stripped).strip()
    if stripped and stripped != cleaned:
        keys.append(stripped)
    return keys or [title]


# ---------------------------------------------------------------- 标题匹配

SEASON_PATTERNS = [
    (r"第([0-9一二三四五六七八九十]+)季", None),
    (r"(?i)\bseason\s*(\d{1,2})\b", None),
    (r"(?i)\bs(\d{1,2})\b", None),
    (r"②", 2), (r"③", 3), (r"④", 4), (r"Ⅱ", 2), (r"Ⅲ", 3), (r"∬", 2),
]

CN_NUM = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6,
          "七": 7, "八": 8, "九": 9, "十": 10}


def extract_season(title: str) -> int | None:
    for pattern, fixed in SEASON_PATTERNS:
        match = re.search(pattern, title)
        if not match:
            continue
        if fixed is not None:
            return fixed
        raw = match.group(1)
        if raw.isdigit():
            return int(raw)
        return CN_NUM.get(raw)
    return None


def season_mentioned(title: str, season: int) -> bool:
    markers = [
        f"第{season}季", f"Season {season}", f"S{season:02d}", f"S{season}",
    ]
    if season == 2:
        markers += ["②", "Ⅱ", "∬", "第二季"]
    if season == 3:
        markers += ["③", "Ⅲ", "第三季"]
    if season == 4:
        markers += ["④", "Ⅳ", "第四季"]
    return any(marker in title for marker in markers)


def explicit_season(title: str) -> int | None:
    return extract_season(title)


def similarity(lhs: str, rhs: str) -> float:
    from difflib import SequenceMatcher

    def norm(text: str) -> str:
        text = clean_title(text).lower()
        return re.sub(r"[\s_\-–—·:：,，!！?？'’\"“”()（）\[\]【】]", "", text)

    a, b = norm(lhs), norm(rhs)
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


NON_ANIME_KEYWORDS = [
    "live", "concert", "music video", "演唱", "音乐会", "歌曲", "谈话",
    "radio", "广播", "guitar hero", "吉他英雄", "making", "花絮", "专访",
]


def looks_like_non_anime(title: str) -> bool:
    lowered = title.lower()
    return any(keyword in lowered for keyword in NON_ANIME_KEYWORDS)


def pick_best_bangumi(
    title: str,
    candidates: list[dict[str, Any]],
) -> dict[str, Any] | None:
    season = extract_season(title)
    best = None
    best_score = 0.0
    for item in candidates:
        names = [item.get("name") or "", item.get("name_cn") or ""]
        score = max(similarity(title, name) for name in names)
        if season is not None and season > 1:
            if any(season_mentioned(name, season) for name in names):
                score += 0.3
            else:
                other = next(
                    (s for s in (2, 3, 4, 5) if s != season
                     and any(season_mentioned(name, s) for name in names)),
                    None,
                )
                if other is not None:
                    score -= 0.25
        if score > best_score:
            best = item
            best_score = score
    if best is None or best_score < 0.55:
        # 罗马音/英文标题与中文条目名相似度天然很低：信任 Bangumi 搜索排序取第一条
        if candidates and not re.search(r"[\u4e00-\u9fff]", title):
            return candidates[0]
        return None

    # 想要第 N 季却只匹配到“明确是其他季”的条目：宁可判未匹配
    if season is not None and season > 1:
        names = [best.get("name") or "", best.get("name_cn") or ""]
        if not any(season_mentioned(name, season) for name in names):
            other = next(
                (s for s in (2, 3, 4, 5) if s != season
                 and any(season_mentioned(name, s) for name in names)),
                None,
            )
            if other is not None:
                return None
    return best


# ---------------------------------------------------------------- 光鸭 API

def make_sign(client_id: str, client_secret: str, nonce: str, timestamp: int) -> str:
    source = (
        f"client_id={client_id}&client_secret={client_secret}"
        f"&nonce={nonce}&timestamp={timestamp}"
    )
    md5_bytes = hashlib.md5(source.encode("utf-8")).digest()
    return hashlib.sha512(md5_bytes).hexdigest()


class GuangyaClient:
    def __init__(self, client_id: str, client_secret: str, host: str = DAPI):
        self.client_id = client_id
        self.client_secret = client_secret
        self.host = host.rstrip("/")

    def post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        nonce = secrets.token_hex(16)
        timestamp = int(time.time())
        headers = {
            "Content-Type": "application/json",
            "client_id": self.client_id,
            "nonce": nonce,
            "timestamp": str(timestamp),
            "sign": make_sign(self.client_id, self.client_secret, nonce, timestamp),
        }
        request = urllib.request.Request(
            self.host + path,
            data=json.dumps(body).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")[:300]
            raise RuntimeError(f"{path} HTTP {error.code}: {detail}") from error

    def list_page(self, parent_id: str, page: int, page_size: int = 100) -> dict[str, Any]:
        return self.post(
            "/userres/v1/file/get_file_list",
            {
                "parentId": parent_id,
                "page": page,
                "pageSize": page_size,
                "orderBy": 3,
                "sortType": 0,
                "fileTypes": [],
            },
        )


def scan_tree(
    client: GuangyaClient,
    max_folders: int = 5000,
    max_files: int = 50000,
    workers: int = 8,
) -> tuple[dict[str, Node], list[Node]]:
    from concurrent.futures import ThreadPoolExecutor

    nodes: dict[str, Node] = {}
    files: list[Node] = []

    def list_dir(parent: str) -> tuple[str, list[dict[str, Any]]]:
        items: list[dict[str, Any]] = []
        page = 0
        while page < 50:
            try:
                payload = client.list_page(parent, page)
            except Exception as error:  # 单目录失败不阻断
                print(f"[warn] {parent} 第 {page} 页失败：{error}")
                break
            batch = (payload.get("data") or {}).get("list") or []
            items.extend(batch)
            if len(batch) < 100:
                break
            page += 1
        return parent, items

    frontier = [""]
    visited: set[str] = {""}
    while frontier:
        if len(nodes) >= max_folders or len(files) >= max_files:
            print(f"[warn] 达到上限：目录 {len(nodes)} / 文件 {len(files)}，结果可能不完整")
            break

        with ThreadPoolExecutor(max_workers=workers) as pool:
            directories = list(pool.map(list_dir, frontier))

        next_frontier: list[str] = []
        for parent, items in directories:
            for item in items:
                node = Node(
                    id=str(item.get("fileId")),
                    name=str(item.get("fileName", "")),
                    parent_id=str(item.get("parentId") or ""),
                    is_folder=item.get("resType") == 2,
                    file_type=item.get("fileType"),
                )
                if node.id in nodes:
                    continue
                nodes[node.id] = node
                if node.is_folder:
                    if node.id not in visited:
                        visited.add(node.id)
                        next_frontier.append(node.id)
                else:
                    files.append(node)
        frontier = next_frontier
        print(f"[scan] 已访问目录 {len(visited)}，累计文件 {len(files)}", flush=True)

    return nodes, files


# ---------------------------------------------------------------- Bangumi

def bangumi_search(keyword: str, retries: int = 2) -> list[dict[str, Any]]:
    body = json.dumps({"keyword": keyword, "filter": {"type": [2]}}).encode("utf-8")
    request = urllib.request.Request(
        BGM_SEARCH + "?limit=5",
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": UA},
        method="POST",
    )
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.loads(response.read().decode("utf-8"))
            return payload.get("data") or []
        except Exception:
            if attempt + 1 >= retries:
                return []
            time.sleep(1.0)
    return []


# ---------------------------------------------------------------- 分集标题

FXBGM = "https://fxbgm.tv"


def fetch_episode_titles(subject_id: int) -> dict[int, str]:
    """拉 Bangumi 分集中文标题：优先 fxbgm /p1/，失败回退官方 /v0/。

    参考 C:\\Users\\柠墨白\\WorkBuddy\\script\\bangumi_episodes.py。
    """
    for api in ("v0", "p1"):
        try:
            if api == "p1":
                url = f"{FXBGM}/p1/subjects/{subject_id}/episodes?limit=100&offset=0"
            else:
                url = f"https://api.bgm.tv/v0/episodes?subject_id={subject_id}&type=0&limit=100&offset=0"
            request = urllib.request.Request(url, headers={
                "User-Agent": UA,
                "Accept": "application/json, text/plain, */*",
                "Referer": FXBGM + "/",
            })
            with urllib.request.urlopen(request, timeout=20) as response:
                data = json.loads(response.read().decode("utf-8"))
            rows = data if isinstance(data, list) else (data.get("data") or [])
            titles: dict[int, str] = {}
            for row in rows:
                if int(row.get("type") or 0) != 0:
                    continue
                # ep 是本季内的集数（1..N），sort 是全系列连续集数；文件按本季编号，优先 ep
                number = row.get("ep")
                if number in (None, ""):
                    number = row.get("sort")
                try:
                    number = int(float(number))
                except (TypeError, ValueError):
                    continue
                name = (row.get("nameCN") or row.get("name_cn") or row.get("name") or "").strip()
                if number > 0 and name:
                    titles[number] = name
            if titles:
                return titles
        except Exception:
            continue
    return {}


def parse_episode_number(name: str) -> int | None:
    base = name.rsplit(".", 1)[0]
    patterns = [
        r"\[(\d{1,4})(?:v\d)?\]",
        r"(?:^|[^0-9])E(?:P)?(\d{1,4})(?:[^0-9]|$)",
        r"第(\d{1,4})[话話集]",
        r"[\s\-_](\d{1,4})(?:v\d)?(?:[^0-9]|$)",
    ]
    for pattern in patterns:
        match = re.search(pattern, base, flags=re.IGNORECASE)
        if match:
            try:
                return int(match.group(1))
            except ValueError:
                continue
    return None


# ---------------------------------------------------------------- 演练

def mock_tree() -> tuple[dict[str, Node], list[Node]]:
    nodes: dict[str, Node] = {}
    files: list[Node] = []

    def folder(fid: str, name: str, parent: str = "") -> None:
        nodes[fid] = Node(fid, name, parent, True)

    def file(fid: str, name: str, parent: str, ext: str = "mkv") -> None:
        files.append(Node(fid, name, parent, False))

    folder("root_anime", "番剧")
    folder("bangdream", "[Nekomoe kissaten&VCB-Studio] BanG Dream! It's MyGO!!!!!", "root_anime")
    folder("mygo_fonts", "Fonts", "bangdream")
    folder("mygo_op", "OP", "bangdream")
    folder("mygo_sps", "SPs", "bangdream")
    folder("mygo_ncop", "NCOP", "bangdream")
    folder("mygo_nced", "NCED", "bangdream")
    for i in range(1, 4):
        file(f"mygo_{i}", f"[Nekomoe kissaten&VCB-Studio] BanG Dream! It's MyGO!!!!! [{i:02d}][Ma10p_1080p][x265_flac].mkv", "bangdream")
    file("mygo_font", "FZLanTingHei.ttf", "mygo_fonts")
    file("mygo_op1", "[NCOP] MyGO!!!!!.mkv", "mygo_op")
    file("mygo_ncop1", "[NCOP] MyGO!!!!! 01.mkv", "mygo_ncop")
    file("mygo_nced1", "[NCED] MyGO!!!!! 01.mkv", "mygo_nced")
    file("mygo_sp1", "[SP01] Menu.mkv", "mygo_sps")

    folder("frieren", "Sousou no Frieren", "root_anime")
    folder("frieren_s1", "Season 1", "frieren")
    folder("frieren_fonts", "Fonts", "frieren_s1")
    for i in range(1, 4):
        file(f"frieren_{i}", f"Sousou no Frieren - {i:02d} [1080p][HEVC].mkv", "frieren_s1")
    file("frieren_font", "SourceHanSans.ttf", "frieren_fonts")

    folder("bocchi", "[DBD-Raws][孤独摇滚!][01-12][1080P][BDRip]", "root_anime")
    folder("bocchi_ed", "ED", "bocchi")
    for i in range(1, 3):
        file(f"bocchi_{i}", f"[DBD-Raws][孤独摇滚!][{i:02d}][1080P][BDRip][HEVC-10bit][FLAC].mkv", "bocchi")
    file("bocchi_ed1", "[NCED] 孤独摇滚!.mkv", "bocchi_ed")

    folder("frieren_box", "[DBD-Raws][葬送的芙莉莲][01-28][1080P][BDRip]", "root_anime")
    file("frieren_box_1", "[DBD-Raws][葬送的芙莉莲][01][1080P][BDRip].mkv", "frieren_box")

    return nodes, files


def build_groups(nodes: dict[str, Node], files: list[Node]) -> list[SeriesGroup]:
    groups: dict[str, SeriesGroup] = {}
    for node in files:
        if not is_video_file(node):
            continue
        if is_noise_file(node.name):
            continue
        # OP/ED/SPs/Fonts 等附属目录里的视频不是正片
        direct_parent = nodes.get(node.parent_id)
        if direct_parent is not None and is_noise_folder(direct_parent.name):
            continue

        series = resolve_series_folder(node.parent_id, nodes)
        key = series.id if series else "unknown"
        name = series.name if series else "未分类"

        group = groups.get(key)
        if group is None:
            group = SeriesGroup(folder_id=key, folder_name=name, title=clean_title(name))
            groups[key] = group
        group.files.append(node)

    # 同一部番可能被拆成多个同名目录（不同季目录/重复目录）：按标题合并
    merged: dict[str, SeriesGroup] = {}
    for group in groups.values():
        normalized = re.sub(r"[\s_\-–—·:：,，!！?？'’\"“”()（）\[\]【】]", "", group.title).lower()
        existing = merged.get(normalized)
        if existing is None:
            merged[normalized] = group
            continue
        existing.files.extend(group.files)
        if len(group.files) > len(existing.files):
            existing.folder_id = group.folder_id
            existing.folder_name = group.folder_name
            existing.title = group.title

    return sorted(merged.values(), key=lambda g: g.title)


def main() -> int:
    parser = argparse.ArgumentParser(description="光鸭云盘刮削演练")
    parser.add_argument("--client-id", default="")
    parser.add_argument("--client-secret", default="")
    parser.add_argument("--host", default=DAPI)
    parser.add_argument("--mock", action="store_true", help="使用内置示例目录树")
    parser.add_argument("--no-bangumi", action="store_true")
    parser.add_argument("--max-folders", type=int, default=5000)
    parser.add_argument("--max-files", type=int, default=50000)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--out", default=".tmp/scrape-report")
    args = parser.parse_args()

    if args.mock:
        nodes, files = mock_tree()
        print(f"[mock] 目录 {len(nodes)} 个，文件 {len(files)} 个")
    else:
        if not args.client_id or not args.client_secret:
            print(
                "缺少开发者凭据。接收方 TOKEN（TOKEN2026...）不能读取文件列表；\n"
                "请用会员账号在「TOKEN 管理 → 成为开发者」获取 client_id / client_secret，\n"
                "或加 --mock 先演练目录规则。",
                file=sys.stderr,
            )
            return 2
        client = GuangyaClient(args.client_id, args.client_secret, args.host)
        print("[live] 正在递归扫描光鸭云盘（dapi）…")
        nodes, files = scan_tree(
            client,
            max_folders=args.max_folders,
            max_files=args.max_files,
            workers=args.workers,
        )
        print(f"[live] 目录 {len(nodes)} 个，文件 {len(files)} 个")

    groups = build_groups(nodes, files)
    print(f"\n解析出 {len(groups)} 部番剧：")
    for group in groups:
        print(f"  - {group.title}  ({len(group.files)} 个视频)  来源目录: {group.folder_name}")

    if not args.no_bangumi:
        print("\n查询 Bangumi（1 req/s）…")
        for group in groups:
            if looks_like_non_anime(group.title):
                print(f"  {group.title} -> 跳过（非番剧：LIVE/MV/谈话等）")
                continue
            matched = None
            keywords = [search_title(group.title)] + search_keywords(group.title)
            for keyword in dict.fromkeys(keywords):
                candidates = bangumi_search(keyword)
                time.sleep(1.0)
                matched = pick_best_bangumi(group.title, candidates)
                if matched:
                    break
            if matched:
                group.bangumi_id = matched.get("id")
                group.bangumi_title = matched.get("name_cn") or matched.get("name")
                if group.bangumi_id:
                    group.episode_titles = fetch_episode_titles(int(group.bangumi_id))
            print(f"  {group.title} -> {group.bangumi_title or '未匹配'} (id={group.bangumi_id})")
            if group.episode_titles:
                sample = list(group.episode_titles.items())[:3]
                print("      分集标题：" + " | ".join(f"{n:02d} {t}" for n, t in sample))

    out_base = Path(args.out)
    out_base.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "mock": args.mock,
        "series": [
            {
                "title": group.title,
                "folder": group.folder_name,
                "files": [f.name for f in group.files],
                "episodes": [
                    {
                        "episode": parse_episode_number(f.name),
                        "title": group.episode_titles.get(parse_episode_number(f.name) or 0),
                        "file": f.name,
                    }
                    for f in group.files
                ],
                "bangumi_id": group.bangumi_id,
                "bangumi_title": group.bangumi_title,
            }
            for group in groups
        ],
    }
    out_base.with_suffix(".json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    md = [f"# 刮削演练报告（{'mock' if args.mock else 'live'}）", ""]
    for group in groups:
        md.append(f"## {group.title}（{len(group.files)} 集）")
        md.append(f"- 识别：{group.bangumi_title or '未匹配'}（Bangumi id: {group.bangumi_id}）")
        md.append(f"- 来源目录：{group.folder_name}")
        md.append("")
        for file in group.files[:8]:
            number = parse_episode_number(file.name)
            title = group.episode_titles.get(number or 0)
            label = f"{number:02d} {title}" if number and title else file.name
            md.append(f"  - {label}")
        md.append("")
    out_base.with_suffix(".md").write_text("\n".join(md), encoding="utf-8")
    print(f"\n报告：{out_base.with_suffix('.md')} / {out_base.with_suffix('.json')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
