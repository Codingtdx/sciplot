from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


REPO_ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = REPO_ROOT / "app/macos/Assets.xcassets/AppIcon.appiconset"
ASSET_ROOT = REPO_ROOT / "app/macos/Assets.xcassets"


def _rounded_rect(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], radius: float, fill, outline=None, width: int = 1) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def _draw_icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    _rounded_rect(
        shadow_draw,
        (78 * scale, 92 * scale, 946 * scale, 960 * scale),
        210 * scale,
        (31, 44, 72, 84),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(1, int(24 * scale))))
    image.alpha_composite(shadow)

    draw = ImageDraw.Draw(image)
    outer = (72 * scale, 64 * scale, 952 * scale, 944 * scale)
    _rounded_rect(draw, outer, 210 * scale, (225, 242, 248, 232), (255, 255, 255, 190), max(1, int(6 * scale)))

    for y, alpha in ((112, 82), (170, 44), (230, 30)):
        draw.arc(
            (108 * scale, y * scale, 916 * scale, (y + 760) * scale),
            205,
            338,
            fill=(255, 255, 255, alpha),
            width=max(1, int(7 * scale)),
        )

    page = (224 * scale, 214 * scale, 800 * scale, 824 * scale)
    _rounded_rect(draw, page, 74 * scale, (255, 255, 255, 246), (196, 213, 224, 170), max(1, int(5 * scale)))

    grid_color = (111, 130, 145, 42)
    for i in range(1, 6):
        x = (224 + i * 96) * scale
        draw.line((x, 284 * scale, x, 742 * scale), fill=grid_color, width=max(1, int(2 * scale)))
    for i in range(1, 5):
        y = (284 + i * 92) * scale
        draw.line((286 * scale, y, 744 * scale, y), fill=grid_color, width=max(1, int(2 * scale)))

    axis_color = (57, 70, 83, 150)
    draw.line((286 * scale, 742 * scale, 744 * scale, 742 * scale), fill=axis_color, width=max(2, int(7 * scale)))
    draw.line((286 * scale, 284 * scale, 286 * scale, 742 * scale), fill=axis_color, width=max(2, int(7 * scale)))

    points = [
        (318, 690),
        (382, 636),
        (444, 620),
        (506, 546),
        (570, 482),
        (634, 502),
        (700, 384),
    ]
    smooth_points: list[tuple[float, float]] = []
    for start, end in zip(points, points[1:]):
        for step in range(10):
            t = step / 10
            x = start[0] + (end[0] - start[0]) * t
            y = start[1] + (end[1] - start[1]) * t - math.sin(t * math.pi) * 18
            smooth_points.append((x * scale, y * scale))
    smooth_points.append((points[-1][0] * scale, points[-1][1] * scale))

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.line(smooth_points, fill=(31, 132, 255, 90), width=max(5, int(34 * scale)), joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(max(1, int(5 * scale))))
    image.alpha_composite(glow)
    draw = ImageDraw.Draw(image)
    draw.line(smooth_points, fill=(11, 111, 226, 255), width=max(4, int(23 * scale)), joint="curve")
    draw.line(smooth_points, fill=(122, 197, 255, 230), width=max(2, int(9 * scale)), joint="curve")

    for x, y in points[1:-1]:
        radius = 18 * scale
        draw.ellipse(
            ((x * scale) - radius, (y * scale) - radius, (x * scale) + radius, (y * scale) + radius),
            fill=(255, 255, 255, 238),
            outline=(11, 111, 226, 230),
            width=max(1, int(5 * scale)),
        )

    draw.arc((144 * scale, 112 * scale, 880 * scale, 856 * scale), 210, 316, fill=(255, 255, 255, 86), width=max(1, int(12 * scale)))
    return image


def main() -> None:
    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    (ASSET_ROOT / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )

    entries = [
        ("16x16", "1x", 16, "AppIcon-16.png"),
        ("16x16", "2x", 32, "AppIcon-32.png"),
        ("32x32", "1x", 32, "AppIcon-32.png"),
        ("32x32", "2x", 64, "AppIcon-64.png"),
        ("128x128", "1x", 128, "AppIcon-128.png"),
        ("128x128", "2x", 256, "AppIcon-256.png"),
        ("256x256", "1x", 256, "AppIcon-256.png"),
        ("256x256", "2x", 512, "AppIcon-512.png"),
        ("512x512", "1x", 512, "AppIcon-512.png"),
        ("512x512", "2x", 1024, "AppIcon-1024.png"),
    ]
    rendered: set[int] = set()
    for _, _, pixel_size, filename in entries:
        if pixel_size in rendered:
            continue
        rendered.add(pixel_size)
        _draw_icon(pixel_size).save(ICON_DIR / filename)

    contents = {
        "images": [
            {"filename": filename, "idiom": "mac", "scale": scale, "size": logical_size}
            for logical_size, scale, _, filename in entries
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (ICON_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
