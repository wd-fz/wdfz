"""Bake diegetic school print, chalk glyphs and the detached shadow for Godot."""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[2] / "assets/campus/anomalies/writing"


def bake(font_path):
    rng = np.random.default_rng(418)

    def font(px):
        return ImageFont.truetype(str(font_path), px, index=2)

    def grain(image, strength):
        pixels = np.asarray(image, dtype=float)
        return Image.fromarray(
            np.uint8(np.clip(pixels + rng.normal(0, strength, (*pixels.shape[:2], 1)), 0, 255))
        )

    board = Image.new("RGB", (704, 280), "#293736")
    d = ImageDraw.Draw(board)
    for i in range(160):
        x, y = rng.integers([4, 4], [662, 267])
        d.line((x, y, x + rng.integers(3, 45), y + rng.integers(-2, 3)), fill="#34413e")
    d.rectangle((3, 3, 700, 276), outline="#857d66", width=3)
    d.rectangle((10, 10, 693, 269), outline="#52615b", width=1)
    d.text((28, 11), "值日记录", font=font(20), fill="#a2aaa0")
    d.text((582, 14), "高二  /  值日", font=font(15), fill="#9ba397")
    d.line((28, 48, 675, 48), fill="#77857a")
    d.text((106, 122), "下一次", font=font(49), fill="#374740")
    d.text((30, 224), "黑板擦过了。", font=font(18), fill="#59685e")
    d.line((473, 236, 661, 236), fill="#505f54")
    grain(board, 2.9).save(OUT / "blackboard.webp", quality=88, method=6)
    paper = Image.new("RGB", (384, 512), "#c6c1aa")
    d = ImageDraw.Draw(paper)
    d.rectangle((12, 12, 371, 499), outline="#77786b", width=2)
    d.text((28, 23), "晚自习点名册", font=font(39), fill="#323d3b")
    d.text((32, 79), "高二年级    /    当日留存", font=font(19), fill="#535c52")
    d.line((25, 112, 357, 112), fill="#6b7266", width=2)
    for i, name in enumerate(["孟  宁", "周  晴", "陆  野", "姜  言", "", "季  秋", "陈  雨"]):
        y = 129 + 42 * i
        d.line((28, y + 31, 353, y + 31), fill="#959887")
        d.text((34, y), f"{i + 1:02}", font=font(16), fill="#6a7369")
        d.text((93, y - 4), name, font=font(24), fill="#3a413d")
        d.text((287, y), "到" if i != 4 else "缺", font=font(18), fill="#76483e" if i == 4 else "#535e53")
    d.line((71, 122, 71, 413), fill="#949586")
    d.line((253, 122, 253, 413), fill="#949586")
    d.text((31, 449), "值班签名", font=font(18), fill="#646c61")
    for x, y in [(40, 20), (346, 20)]:
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill="#797667")
    d.line((220, 473, 341, 469), fill="#8b8b7b")
    grain(paper, 2.3).save(OUT / "register.webp", quality=89, method=6)
    # The top row is indexed by the shader, including the clock's colon. Each
    # lower row carries one student's actual name, drawn into the marked entry.
    glyph = Image.new("L", (896, 320))
    d = ImageDraw.Draw(glyph)
    for i, s in enumerate("0123456789:下一次"):
        d.text((i * 64 + 32, 32), s, font=font(52), anchor="mm", fill=255)
    for row, s in enumerate(["林澈", "乔禾", "沈墨", "许棠"]):
        d.text((64, 96 + row * 64), s, font=font(48), anchor="mm", fill=255)
    ink = np.array(glyph)
    ink[(rng.random(ink.shape) < 0.07) & (ink > 0)] = 95
    Image.fromarray(ink).save(OUT / "writing-ink.png", optimize=True)
    # One arm hangs low; the other is raised, with daylight visible between the fingers.
    mask = Image.new("L", (256, 384))
    d = ImageDraw.Draw(mask)
    d.ellipse((126, 41, 181, 105), fill=255)
    d.polygon(
        [
            (134, 92),
            (163, 90),
            (163, 120),
            (190, 132),
            (197, 180),
            (177, 207),
            (166, 227),
            (107, 232),
            (104, 188),
            (103, 144),
            (114, 122),
            (135, 112),
        ],
        fill=255,
    )
    d.line([(177, 139), (204, 192), (199, 224)], fill=247, width=19)
    d.ellipse((191, 216, 207, 238), fill=247)
    d.line([(115, 133), (84, 164), (62, 105)], fill=255, width=16)
    d.ellipse((50, 83, 69, 112), fill=255)
    for j in range(5):
        x = 50 + j * 4
        d.line([(x + 5, 100), (x - 2, 78 - j % 3 * 5), (x - 5, 67 - j % 3 * 5)], fill=246, width=3)
    for pts, w in [
        ([(123, 216), (134, 284), (114, 350), (105, 363)], 21),
        ([(154, 220), (172, 286), (163, 337), (153, 348)], 19),
    ]:
        d.line(pts, fill=255, width=w)
    shade = Image.new("RGBA", mask.size, (14, 16, 20, 0))
    shade.putalpha(mask.filter(ImageFilter.GaussianBlur(1.8)))
    shade.save(OUT / "late-shadow.png", optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--font", type=Path, default=Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc")
    )
    OUT.mkdir(parents=True, exist_ok=True)
    bake(parser.parse_args().font)
