"""Rebuild the desktop artwork with Pillow; no game runtime is needed."""
from pathlib import Path
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "branding"
OUT.mkdir(parents=True, exist_ok=True)
SCALE = 4
SIZE = 256
DARK = "#122633"
TURQUOISE = "#39e4bc"
WHITE = "#f5faf8"


def pentagon(cx, cy, radius, rotation):
    return [(cx + radius * math.cos(rotation + i * math.tau / 5),
             cy + radius * math.sin(rotation + i * math.tau / 5)) for i in range(5)]


patches = [pentagon(128, 122, 23, -math.pi / 2)]
for i in range(5):
    angle = -math.pi / 2 + i * math.tau / 5
    patches.append(pentagon(128 + 63 * math.cos(angle),
                            122 + 63 * math.sin(angle), 22, angle))

svg_polygons = "\n".join(
    '<polygon points="' + ' '.join(f'{x:.2f},{y:.2f}' for x, y in points) + '"/>'
    for points in patches)
svg_seams = "\n".join(
    f'<path d="M {x:.2f},{y:.2f} L {128 + 63 * math.cos(-math.pi / 2 + i * math.tau / 5):.2f},{122 + 63 * math.sin(-math.pi / 2 + i * math.tau / 5):.2f}"/>'
    for i, (x, y) in enumerate(patches[0]))
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
<rect x="8" y="8" width="240" height="240" rx="52" fill="{DARK}"/>
<rect x="27" y="29" width="202" height="198" rx="24" fill="{TURQUOISE}"/>
<g fill="none" stroke="{DARK}" stroke-width="5" opacity=".45">
<path d="M 128,29 V 227"/><circle cx="128" cy="128" r="42"/>
<path d="M 27,88 H 52 V 168 H 27 M 229,88 H 204 V 168 H 229"/></g>
<ellipse cx="133" cy="193" rx="65" ry="15" fill="{DARK}" opacity=".28"/>
<circle cx="128" cy="122" r="76" fill="{DARK}"/>
<circle cx="128" cy="122" r="70" fill="{WHITE}"/>
<defs><clipPath id="ball"><circle cx="128" cy="122" r="70"/></clipPath></defs>
<g clip-path="url(#ball)" fill="{DARK}">{svg_polygons}</g>
<g clip-path="url(#ball)" fill="none" stroke="{DARK}" stroke-width="3">{svg_seams}</g>
<circle cx="105" cy="83" r="8" fill="white" opacity=".6"/>
</svg>
'''
(OUT / "based-football.svg").write_text(svg, encoding="utf-8")

image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
draw = ImageDraw.Draw(image)


def box(coords):
    return tuple(round(v * SCALE) for v in coords)


def line(points, fill, width):
    draw.line([(round(x * SCALE), round(y * SCALE)) for x, y in points],
              fill=fill, width=width * SCALE)


draw.rounded_rectangle(box((8, 8, 248, 248)), radius=52 * SCALE, fill=DARK)
draw.rounded_rectangle(box((27, 29, 229, 227)), radius=24 * SCALE, fill=TURQUOISE)
pitch_line = "#27917e"
line([(128, 29), (128, 227)], pitch_line, 5)
draw.ellipse(box((86, 86, 170, 170)), outline=pitch_line, width=5 * SCALE)
line([(27, 88), (52, 88), (52, 168), (27, 168)], pitch_line, 5)
line([(229, 88), (204, 88), (204, 168), (229, 168)], pitch_line, 5)
draw.ellipse(box((68, 178, 198, 208)), fill="#2eb29a")
draw.ellipse(box((52, 46, 204, 198)), fill=DARK)
draw.ellipse(box((58, 52, 198, 192)), fill=WHITE)
ball_layer = Image.new("RGBA", image.size)
ball_draw = ImageDraw.Draw(ball_layer)
for points in patches:
    ball_draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=DARK)
for i, (x, y) in enumerate(patches[0]):
    angle = -math.pi / 2 + i * math.tau / 5
    ball_draw.line([(round(x * SCALE), round(y * SCALE)),
                    (round((128 + 63 * math.cos(angle)) * SCALE),
                     round((122 + 63 * math.sin(angle)) * SCALE))], fill=DARK, width=3 * SCALE)
mask = Image.new("L", image.size)
ImageDraw.Draw(mask).ellipse(box((58, 52, 198, 192)), fill=255)
image.alpha_composite(Image.composite(ball_layer, Image.new("RGBA", image.size), mask))
draw = ImageDraw.Draw(image)
draw.ellipse(box((97, 75, 113, 91)), fill="white")
image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
image.save(OUT / "based-football.png")
image.save(OUT / "based-football.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
print(f"ICON_BUILT: {OUT}")
