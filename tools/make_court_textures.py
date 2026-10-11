"""Deterministic original surface textures; rebuild with Python and Pillow."""
from pathlib import Path
import math
import random
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "assets" / "court"
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(307)
size = 256
for name, strength in [("turf", 12), ("concrete", 8)]:
    texture = Image.new("RGB", (size, size))
    texture.putdata([(v, v, v) for v in
                     (rng.randint(235 - strength, 235 + strength) for _ in range(size * size))])
    if name == "turf":
        draw = ImageDraw.Draw(texture)
        for _ in range(2200):
            x, y = rng.randrange(size), rng.randrange(size)
            tone = rng.randint(210, 250)
            draw.line((x, y, x + 1, y - 2), fill=(tone, tone, tone))
    texture.save(OUT / f"{name}.png")

net = Image.new("RGBA", (256, 256))
draw = ImageDraw.Draw(net)
for x in range(0, 256, 64):
    draw.line((x, 0, x, 255), fill=(227, 229, 218, 255), width=4)
    draw.line((0, x, 255, x), fill=(227, 229, 218, 255), width=4)
net.save(OUT / "net.png")

shadow = Image.new("RGBA", (128, 128))
shadow.putdata([(8, 17, 22, round(90 * max(0, 1 - math.hypot((x - 63.5) / 63.5,
                                                           (y - 63.5) / 63.5)) ** 1.4))
                for y in range(128) for x in range(128)])
shadow.save(OUT / "contact-shadow.png")
print(f"TEXTURES_BUILT: {OUT}")
