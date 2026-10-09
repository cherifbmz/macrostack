"""Recreate the geometric app icon with Pillow (not needed for builds)."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

assets = Path(__file__).resolve().parents[1] / "MacroStack" / "Assets.xcassets"
folder = assets / "AppIcon.appiconset"
folder.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), (15, 21, 18))
draw = ImageDraw.Draw(image)
for radius in range(600, 0, -1):
    strength = max(0, 1 - radius / 600)
    color = (int(15 + 12 * strength), int(21 + 23 * strength), int(18 + 16 * strength))
    draw.ellipse((512 - radius, 470 - radius, 512 + radius, 470 + radius), fill=color)
for offset, color in [(54, (55, 83, 58)), (27, (87, 130, 76)), (0, (168, 232, 122))]:
    draw.rounded_rectangle((213, 213 + offset, 811, 757 + offset), radius=140, outline=color, width=24)
draw.ellipse((331, 303, 693, 665), outline=(168, 232, 122), width=30)
draw.ellipse((388, 360, 636, 608), outline=(80, 121, 78), width=12)
draw.ellipse((474, 446, 550, 522), fill=(205, 250, 179))
draw.ellipse((694, 283, 730, 319), fill=(168, 232, 122))
image.save(folder / "AppIcon.png")
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
(folder / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2), encoding="utf-8")
