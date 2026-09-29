"""Package Sanad's generated master logo into platform-sized assets.

Run: python3 tools/generate_brand_assets.py (requires Pillow).
Artwork and generation prompt: docs/sanad-brand-motion.md.
Preserve the approved silhouette while packaging a high-contrast launcher mark.
"""

import json
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
ICON_CANVAS = (32, 80, 138)
MARK_LIGHT = (242, 247, 252)
MARK_ACCENT = (156, 201, 250)
LAUNCH_SIZE = 96  # Must match SanadLaunch and LaunchScreen.storyboard.


@lru_cache(maxsize=2)
def base_icon(rounded=False):
    source = ROOT / "assets/images/sanad-logo.png"
    with Image.open(source) as source_image:
        image = source_image.convert("RGBA")
    if image.width != image.height:
        raise ValueError("The approved Sanad logo must be square.")
    # Keep the generated silhouette exact, but lift every opaque pixel into a
    # light range that remains legible against the deep brand canvas. Source
    # luminance retains the distinction between the two supporting figures.
    luminance = ImageOps.grayscale(image.convert("RGB"))
    mark = ImageOps.colorize(luminance, MARK_LIGHT, MARK_ACCENT).convert("RGBA")
    mark.putalpha(image.getchannel("A"))
    background = Image.new("RGBA", image.size, ICON_CANVAS + (255,))
    background.alpha_composite(mark)
    image = background.convert("RGB")
    if rounded:
        image = image.convert("RGBA")
        mask = Image.new("L", image.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, image.width - 1, image.height - 1),
            radius=image.width / 4,
            fill=255,
        )
        image.putalpha(mask)
    return image


def icon(size, *, rounded=False):
    return base_icon(rounded).resize((size, size), Image.Resampling.LANCZOS)


@lru_cache(maxsize=1)
def dark_base_icon():
    source = ROOT / "assets/images/sanad-logo.png"
    with Image.open(source) as source_image:
        alpha = source_image.convert("RGBA").getchannel("A")
    image = Image.new("RGBA", alpha.size, (0, 0, 0, 255))
    mark = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    mark.putalpha(alpha)
    image.alpha_composite(mark)
    return image.convert("RGB")


def dark_icon(size):
    return dark_base_icon().resize((size, size), Image.Resampling.LANCZOS)


def centered_mark(canvas_size, mark_size):
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    offset = (canvas_size - mark_size) // 2
    image.alpha_composite(icon(mark_size, rounded=True), (offset, offset))
    return image


def generate():
    icon(1024).save(ROOT / "assets/images/sanad-logo-contrast.png")

    # iOS requires opaque, square app icons; SpringBoard supplies its own mask.
    app_icons = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((app_icons / "Contents.json").read_text())
    for spec in contents["images"]:
        if "filename" not in spec:
            continue
        dimension = round(
            float(spec["size"].split("x")[0])
            * float(spec.get("scale", "1x").rstrip("x"))
        )
        is_dark = any(
            appearance.get("value") == "dark"
            for appearance in spec.get("appearances", [])
        )
        (dark_icon(dimension) if is_dark else icon(dimension)).save(
            app_icons / spec["filename"]
        )

    # Native launch art is centered in the complete window, not its safe area.
    launch = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for scale, filename in [
        (1, "LaunchImage.png"),
        (2, "LaunchImage@2x.png"),
        (3, "LaunchImage@3x.png"),
    ]:
        icon(LAUNCH_SIZE * scale, rounded=True).save(launch / filename)

    res = ROOT / "android/app/src/main/res"
    for density, scale in {
        "mdpi": 1, "hdpi": 1.5, "xhdpi": 2,
        "xxhdpi": 3, "xxxhdpi": 4,
    }.items():
        launcher = res / f"mipmap-{density}"
        launcher.mkdir(exist_ok=True)
        icon(round(48 * scale), rounded=True).save(launcher / "ic_launcher.png")
        drawables = res / f"drawable-{density}"
        drawables.mkdir(exist_ok=True)
        icon(round(LAUNCH_SIZE * scale), rounded=True).save(
            drawables / "sanad_launch.png"
        )
        # Android 12 sizes a splash drawable to 288dp; artwork stays 96dp and
        # inside the 192dp safe circle instead of being enlarged or clipped.
        centered_mark(round(288 * scale), round(LAUNCH_SIZE * scale)).save(
            drawables / "sanad_splash_android12.png"
        )
        # A 60dp mark is inside the 66dp adaptive icon safe zone on a 108dp canvas.
        centered_mark(round(108 * scale), round(60 * scale)).save(
            drawables / "sanad_launcher_foreground.png"
        )

    for size in [192, 512]:
        icon(size).save(ROOT / f"web/icons/Icon-{size}.png")
        # Maskable icons reserve the central 80% circle for meaningful artwork.
        # The opaque deep canvas absorbs device-specific outer masks while the
        # pale mark keeps strong contrast at launcher sizes.
        maskable = Image.new("RGB", (size, size), ICON_CANVAS)
        mark = icon(round(size * .68), rounded=True)
        offset = (size - mark.width) // 2
        maskable.paste(mark, (offset, offset), mark)
        maskable.save(ROOT / f"web/icons/Icon-maskable-{size}.png")
    icon(64, rounded=True).save(ROOT / "web/favicon.png")
    print("Sanad app icons and matching 96-point launch marks generated.")


if __name__ == "__main__":
    generate()
