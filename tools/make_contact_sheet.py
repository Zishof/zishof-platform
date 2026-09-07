"""Create a compact contact sheet for visual QA of screenshots or rendered pages."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--thumb-width", type=int, default=360)
    args = parser.parse_args()

    images = sorted(
        path
        for path in args.source.iterdir()
        if path.is_file() and path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    if not images:
        raise SystemExit(f"No images found in {args.source}")

    font = ImageFont.load_default()
    gap = 16
    label_height = 34
    tiles: list[tuple[Image.Image, str]] = []
    max_height = 0
    for path in images:
        with Image.open(path) as source:
            image = source.convert("RGB")
        height = max(1, int(image.height * args.thumb_width / image.width))
        image = image.resize((args.thumb_width, height), Image.Resampling.LANCZOS)
        max_height = max(max_height, height)
        tiles.append((image, path.name))

    rows = (len(tiles) + args.columns - 1) // args.columns
    width = gap + args.columns * (args.thumb_width + gap)
    tile_height = max_height + label_height
    height = gap + rows * (tile_height + gap)
    sheet = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(sheet)
    for index, (image, label) in enumerate(tiles):
        row, column = divmod(index, args.columns)
        x = gap + column * (args.thumb_width + gap)
        y = gap + row * (tile_height + gap)
        sheet.paste(image, (x, y))
        draw.rectangle(
            (x, y, x + args.thumb_width - 1, y + max_height - 1), outline="#cbd5e1"
        )
        draw.text((x, y + max_height + 7), label[:56], fill="#111827", font=font)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output, optimize=True)
    print(args.output)


if __name__ == "__main__":
    main()
