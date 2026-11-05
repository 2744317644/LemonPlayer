#!/usr/bin/env python3
"""从 Windows 上的 IosScreenCaptureTool 抓 iPhone/iPad 画面帧。

前置：
  1. iPhone/iPad 用数据线连电脑，手机上点“信任”；
  2. 下载并运行 BieleckiLtd/IosScreenCaptureTool（Windows，USB 投屏）；
  3. 本脚本通过它的 CLI `--capture-frame <png>` 抓帧。

用法：
  python scripts/ios_capture.py --exe "E:\\Tools\\IosScreenCaptureTool.exe" --out .tmp/frames
  python scripts/ios_capture.py --exe ... --out .tmp/frames --count 5 --interval 1
  python scripts/ios_capture.py --exe ... --out .tmp/frames --ocr --bottom 0.55
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

SEARCH_DIRS = [
    Path.cwd(),
    Path.home() / "Downloads",
    Path("E:/Tools"),
    Path("C:/Tools"),
    Path("C:/Program Files"),
]


def find_exe(explicit: str | None) -> Path | None:
    if explicit:
        path = Path(explicit)
        return path if path.exists() else None
    for directory in SEARCH_DIRS:
        if not directory.exists():
            continue
        hits = list(directory.glob("**/IosScreenCaptureTool.exe"))
        if hits:
            return hits[0]
    return None


def is_running(name: str = "IosScreenCaptureTool") -> bool:
    try:
        output = subprocess.run(
            ["tasklist", "/FI", f"IMAGENAME eq {name}.exe"],
            capture_output=True, text=True, timeout=10,
            encoding="utf-8", errors="replace",
        ).stdout
        return name.lower() in output.lower()
    except Exception:
        return False


def capture_once(exe: Path, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    target = out_dir / f"frame-{stamp}.png"
    result = subprocess.run(
        [str(exe), "--capture-frame", str(target)],
        capture_output=True, text=True, timeout=30,
        encoding="utf-8", errors="replace",
    )
    if result.returncode != 0 or not target.exists():
        raise RuntimeError(
            f"抓帧失败（exit {result.returncode}）："
            f"{(result.stderr or result.stdout or '').strip()[:300]}"
        )
    if target.stat().st_size < 10_000:
        raise RuntimeError(f"抓帧文件过小（{target.stat().st_size} B），手机可能没连上/未解锁")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="抓取 iPhone 画面帧（Windows）")
    parser.add_argument("--exe", default=None, help="IosScreenCaptureTool.exe 路径")
    parser.add_argument("--out", default=".tmp/frames")
    parser.add_argument("--count", type=int, default=1, help="抓多少帧")
    parser.add_argument("--interval", type=float, default=1.0, help="帧间隔秒")
    parser.add_argument("--ocr", action="store_true", help="抓完立即 OCR")
    parser.add_argument("--bottom", type=float, default=0.0, help="OCR 只看下半屏（0.55）")
    args = parser.parse_args()

    exe = find_exe(args.exe)
    if exe is None:
        print(
            "找不到 IosScreenCaptureTool.exe。\n"
            "下载：https://github.com/BieleckiLtd/IosScreenCaptureTool/releases\n"
            "解压后用 --exe 指定路径，例如：\n"
            '  python scripts/ios_capture.py --exe "E:\\Tools\\IosScreenCaptureTool.exe"',
            file=sys.stderr,
        )
        return 2

    if not is_running():
        print("[info] 工具未运行，启动镜像窗口…")
        subprocess.Popen([str(exe)])
        time.sleep(2.5)

    out_dir = Path(args.out)
    frames: list[Path] = []
    for index in range(args.count):
        try:
            frame = capture_once(exe, out_dir)
            frames.append(frame)
            print(f"[frame] {frame}  ({frame.stat().st_size} B)")
        except Exception as error:
            print(f"[error] {error}", file=sys.stderr)
            return 1
        if index + 1 < args.count:
            time.sleep(args.interval)

    if args.ocr:
        command = [sys.executable, str(Path(__file__).with_name("ocr_png.py")),
                   str(frames[-1])]
        if args.bottom > 0:
            command += ["--bottom", str(args.bottom)]
        subprocess.run(command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
