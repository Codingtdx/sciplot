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


def _rounded_rect_mask(size: int, box: tuple[float, float, float, float], radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(box, radius=radius, fill=255)
    return mask


def _diagonal_gradient(size: int, top_left: tuple[int, int, int], bottom_right: tuple[int, int, int]) -> Image.Image:
    gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = gradient.load()
    denominator = max(1, (size - 1) * 2)
    for y in range(size):
        for x in range(size):
            t = (x + y) / denominator
            r = round(top_left[0] * (1 - t) + bottom_right[0] * t)
            g = round(top_left[1] * (1 - t) + bottom_right[1] * t)
            b = round(top_left[2] * (1 - t) + bottom_right[2] * t)
            pixels[x, y] = (r, g, b, 255)
    return gradient


def _catmull_rom(points: list[tuple[float, float]], samples: int = 18) -> list[tuple[float, float]]:
    if len(points) < 2:
        return points

    expanded = [points[0], *points, points[-1]]
    output: list[tuple[float, float]] = []
    for index in range(1, len(expanded) - 2):
        p0, p1, p2, p3 = expanded[index - 1], expanded[index], expanded[index + 1], expanded[index + 2]
        for step in range(samples):
            t = step / samples
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * (
                (2 * p1[0])
                + (-p0[0] + p2[0]) * t
                + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
            )
            y = 0.5 * (
                (2 * p1[1])
                + (-p0[1] + p2[1]) * t
                + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
            )
            output.append((x, y))
    output.append(points[-1])
    return output


def _draw_icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    _rounded_rect(
        shadow_draw,
        (78 * scale, 90 * scale, 946 * scale, 958 * scale),
        224 * scale,
        (23, 38, 70, 92),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(1, int(28 * scale))))
    image.alpha_composite(shadow)

    outer = (70 * scale, 62 * scale, 954 * scale, 946 * scale)
    outer_mask = _rounded_rect_mask(size, outer, 224 * scale)
    glass = _diagonal_gradient(size, (250, 253, 249), (204, 236, 255))
    glass.putalpha(outer_mask.point(lambda alpha: round(alpha * 0.95)))
    image.alpha_composite(glass)

    draw = ImageDraw.Draw(image)
    _rounded_rect(
        draw,
        outer,
        224 * scale,
        fill=None,
        outline=(255, 255, 255, 218),
        width=max(1, int(7 * scale)),
    )
    _rounded_rect(
        draw,
        (92 * scale, 86 * scale, 932 * scale, 922 * scale),
        202 * scale,
        fill=None,
        outline=(44, 96, 140, 34),
        width=max(1, int(3 * scale)),
    )

    field = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    field_draw = ImageDraw.Draw(field)
    for radius, alpha in ((310, 36), (238, 26), (166, 18)):
        field_draw.ellipse(
            (
                (512 - radius) * scale,
                (508 - radius) * scale,
                (512 + radius) * scale,
                (508 + radius) * scale,
            ),
            outline=(30, 98, 156, alpha),
            width=max(1, int(5 * scale)),
        )
    for angle in range(-35, 55, 18):
        radians = math.radians(angle)
        cx, cy = 510 * scale, 510 * scale
        length = 590 * scale
        dx = math.cos(radians) * length / 2
        dy = math.sin(radians) * length / 2
        field_draw.line(
            (cx - dx, cy - dy, cx + dx, cy + dy),
            fill=(28, 96, 150, 20),
            width=max(1, int(3 * scale)),
        )
    field.putalpha(Image.composite(field.getchannel("A"), Image.new("L", (size, size), 0), outer_mask))
    image.alpha_composite(field)

    primary_points = [
        (198 * scale, 682 * scale),
        (292 * scale, 622 * scale),
        (390 * scale, 670 * scale),
        (486 * scale, 536 * scale),
        (572 * scale, 488 * scale),
        (662 * scale, 338 * scale),
        (804 * scale, 278 * scale),
    ]
    secondary_points = [
        (218 * scale, 566 * scale),
        (344 * scale, 522 * scale),
        (478 * scale, 454 * scale),
        (614 * scale, 390 * scale),
        (782 * scale, 202 * scale),
    ]
    primary_curve = _catmull_rom(primary_points)
    secondary_curve = _catmull_rom(secondary_points)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.line(primary_curve, fill=(0, 120, 255, 155), width=max(5, int(78 * scale)), joint="curve")
    glow_draw.line(secondary_curve, fill=(114, 91, 255, 96), width=max(4, int(42 * scale)), joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(max(1, int(15 * scale))))
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (size, size), 0), outer_mask))
    image.alpha_composite(glow)

    draw = ImageDraw.Draw(image)
    draw.line(secondary_curve, fill=(114, 95, 255, 168), width=max(2, int(18 * scale)), joint="curve")
    draw.line(primary_curve, fill=(0, 101, 255, 255), width=max(4, int(38 * scale)), joint="curve")
    draw.line(primary_curve, fill=(120, 221, 255, 240), width=max(2, int(13 * scale)), joint="curve")

    for x, y in primary_points[1:-1]:
        radius = 17 * scale
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=(246, 252, 255, 246),
            outline=(0, 103, 255, 220),
            width=max(1, int(4 * scale)),
        )

    draw.arc(
        (118 * scale, 92 * scale, 906 * scale, 882 * scale),
        206,
        322,
        fill=(255, 255, 255, 112),
        width=max(1, int(14 * scale)),
    )
    draw.arc(
        (172 * scale, 150 * scale, 858 * scale, 828 * scale),
        218,
        306,
        fill=(255, 255, 255, 70),
        width=max(1, int(7 * scale)),
    )
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
