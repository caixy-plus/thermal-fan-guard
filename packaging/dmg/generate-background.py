#!/usr/bin/env python3
"""Generate retina DMG background for MyFans installer app."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "background.png"

W, H = 1320, 880
SCALE = 2


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size, index=0)
            except OSError:
                continue
    return ImageFont.load_default()


def main() -> None:
    top = (248, 248, 250)
    bottom = (232, 234, 238)

    img = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(img)

    for y in range(H):
        t = y / (H - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line((0, y, W, y), fill=(r, g, b))

    title_font = load_font(48 * SCALE, bold=True)
    subtitle_font = load_font(22 * SCALE)
    hint_font = load_font(20 * SCALE)

    draw.text((W // 2, 88 * SCALE), "MyFans", font=title_font, fill=(29, 29, 31), anchor="mm")
    draw.text(
        (W // 2, 132 * SCALE),
        "Apple Silicon 风扇与温度守护",
        font=subtitle_font,
        fill=(110, 110, 115),
        anchor="mm",
    )

    draw.rounded_rectangle(
        (W // 2 - 290 * SCALE, 610 * SCALE, W // 2 + 290 * SCALE, 730 * SCALE),
        radius=16 * SCALE,
        fill=(255, 255, 255),
        outline=(210, 214, 220),
        width=2,
    )
    draw.text(
        (W // 2, 652 * SCALE),
        "双击「Install MyFans」开始安装",
        font=hint_font,
        fill=(29, 29, 31),
        anchor="mm",
    )
    draw.text(
        (W // 2, 690 * SCALE),
        "安装向导将引导您完成全部组件安装",
        font=hint_font,
        fill=(110, 110, 115),
        anchor="mm",
    )

    draw.ellipse(
        (W // 2 - 92 * SCALE, 210 * SCALE, W // 2 + 92 * SCALE, 394 * SCALE),
        outline=(198, 202, 208),
        width=2,
    )

    img.save(OUT, format="PNG", optimize=True)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
