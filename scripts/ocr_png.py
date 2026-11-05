#!/usr/bin/env python3
"""Windows 本地 OCR：读取 iOS 截图里的文字（Windows.Media.Ocr，zh-Hans）。

用法：
  python scripts/ocr_png.py .tmp/frames/frame-xxx.png
  python scripts/ocr_png.py --bottom 0.55 <png>     # 只看下半屏（字幕/控制层）
  python scripts/ocr_png.py --json <png>            # 带坐标输出，便于定位
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from winsdk.windows.globalization import Language
from winsdk.windows.graphics.imaging import BitmapDecoder
from winsdk.windows.media.ocr import OcrEngine
from winsdk.windows.storage import FileAccessMode, StorageFile

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")


async def recognize(path: str) -> tuple[int, int, list[dict]]:
    engine = OcrEngine.try_create_from_language(Language("zh-Hans-CN"))
    if engine is None:
        engine = OcrEngine.try_create_from_user_profile_languages()
    if engine is None:
        raise RuntimeError("本机没有可用的 OCR 语言包（需要 zh-Hans 或英文）")

    file = await StorageFile.get_file_from_path_async(str(Path(path).resolve()))
    stream = await file.open_async(FileAccessMode.READ)
    decoder = await BitmapDecoder.create_async(stream)
    bitmap = await decoder.get_software_bitmap_async()
    width, height = int(decoder.pixel_width), int(decoder.pixel_height)
    result = await engine.recognize_async(bitmap)

    lines = []
    for line in result.lines:
        words = list(line.words)
        rect = words[0].bounding_rect if words else None
        lines.append({
            "text": line.text,
            "x": round(rect.x, 1) if rect else 0,
            "y": round(rect.y, 1) if rect else 0,
        })
    return width, height, lines


def main() -> int:
    parser = argparse.ArgumentParser(description="OCR iOS 截图（Windows 自带引擎）")
    parser.add_argument("image")
    parser.add_argument("--bottom", type=float, default=0.0,
                        help="只看 y 比例大于该值的行，如 0.55 表示下半屏")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    width, height, lines = asyncio.run(recognize(args.image))
    if args.bottom > 0:
        lines = [line for line in lines if line["y"] / max(height, 1) >= args.bottom]

    if args.json:
        print(json.dumps({"width": width, "height": height, "lines": lines},
                         ensure_ascii=False, indent=2))
    else:
        print(f"# {Path(args.image).name}  {width}x{height}")
        for line in lines:
            print(f"[y={line['y']:6.0f}] {line['text']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
