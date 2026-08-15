from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Design/AppIcon/accord-manual-honda-inspired-v2.png"
APP_ICON_SET = ROOT / "Resources/Assets.xcassets/AppIcon.appiconset"
DESIGN_DIR = ROOT / "Design/AppIcon"

CANVAS_SIZE = 1024
GLYPH_WIDTH = 840


def extracted_glyph() -> Image.Image:
    source = Image.open(SOURCE).convert("RGB")
    red, green, blue = source.split()
    competing_channel = ImageChops.lighter(green, blue)
    red_dominance = ImageChops.subtract(red, competing_channel)
    alpha = red_dominance.point(
        lambda value: 0 if value <= 3 else min(255, round((value - 3) * 255 / 72))
    )

    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError("The source artwork does not contain a detectable red mark")

    alpha = alpha.crop(bounds)
    height = round(GLYPH_WIDTH * alpha.height / alpha.width)
    alpha = alpha.resize((GLYPH_WIDTH, height), Image.Resampling.LANCZOS)

    glyph = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    glyph.putalpha(alpha)
    return glyph


def render_icon(glyph: Image.Image, background: str, foreground: str) -> Image.Image:
    icon = Image.new("RGB", (CANVAS_SIZE, CANVAS_SIZE), background)
    mark = Image.new("RGB", glyph.size, foreground)
    origin = (
        (CANVAS_SIZE - glyph.width) // 2,
        (CANVAS_SIZE - glyph.height) // 2,
    )
    icon.paste(mark, origin, glyph.getchannel("A"))
    return icon


def main() -> None:
    APP_ICON_SET.mkdir(parents=True, exist_ok=True)
    DESIGN_DIR.mkdir(parents=True, exist_ok=True)

    glyph = extracted_glyph()
    glyph.save(DESIGN_DIR / "accord-manual-glyph-transparent.png", optimize=True)

    variants = {
        "AppIcon-Default.png": ("#FFFFFF", "#CC0000"),
        "AppIcon-Dark.png": ("#190006", "#FF5967"),
        "AppIcon-Tinted.png": ("#161616", "#FFFFFF"),
    }

    rendered: list[Image.Image] = []
    for filename, (background, foreground) in variants.items():
        icon = render_icon(glyph, background, foreground)
        icon.save(APP_ICON_SET / filename, optimize=True)
        rendered.append(icon)

    preview = Image.new("RGB", (CANVAS_SIZE * 3, CANVAS_SIZE), "#E8E8ED")
    for index, icon in enumerate(rendered):
        preview.paste(icon, (index * CANVAS_SIZE, 0))
    preview.resize((1536, 512), Image.Resampling.LANCZOS).save(
        DESIGN_DIR / "app-icon-variants-preview.png", optimize=True
    )


if __name__ == "__main__":
    main()
