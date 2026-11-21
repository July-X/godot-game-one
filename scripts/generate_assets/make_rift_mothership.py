"""Render the original Rift Mothership variants on a 64×48 pixel grid."""

from pathlib import Path

from PIL import Image, ImageDraw


def mothership(variant: int) -> Image.Image:
    image = Image.new("RGBA", (64, 48))
    draw = ImageDraw.Draw(image)

    def plate(color: str, *points: tuple[int, int]) -> None:
        draw.polygon(points, fill=color)

    def pair(color: str, *points: tuple[int, int]) -> None:
        plate(color, *points)
        plate(color, *((63 - x, y) for x, y in points))

    # Stage silhouettes differ at the shoulder and the recess behind it.
    shoulder, shoulder_y, notch, wing_y = (
        (17, 14, 10, 33),
        (15, 12, 9, 34),
        (13, 11, 7, 36),
        (16, 12, 8, 35),
        (14, 15, 9, 34),
    )[variant - 1]
    pair("#152130", (25, 10), (shoulder, shoulder_y), (notch, 20), (2, 24),
         (1, wing_y), (6, wing_y + 4), (14, wing_y + 1), (21, 42), (31, 39))
    pair("#29384a", (19, 17), (notch, 22), (3, 25), (3, wing_y),
         (7, wing_y + 1), (14, wing_y - 2), (22, 37))
    pair("#394a5b", (notch, 22), (4, 26), (4, 29), (10, 26), (17, 25), (21, 19))
    pair("#202d3c", (9, 29), (17, 26), (20, 28), (15, 32), (9, wing_y))

    pair("#273849", (28, 9), (shoulder, shoulder_y), (notch + 3, 23),
         (notch + 2, 29), (16, 37), (20, 42), (28, 42), (33, 31))
    pair("#748b9e", (26, 11), (shoulder + 1, shoulder_y + 1), (notch + 5, 23),
         (notch + 3, 28), (20, 33), (26, 29), (31, 20))
    pair("#9aafbe", (26, 11), (shoulder + 1, shoulder_y + 1), (notch + 5, 23),
         (notch + 6, 25), (22, 21), (26, 16))
    pair("#536b82", (notch + 3, 28), (20, 33), (26, 29), (28, 24), (24, 32),
         (21, 38), (17, 36))
    pair("#8095a8", (21, 33), (25, 30), (24, 36), (22, 39), (19, 37))
    pair("#233241", (19, 39), (22, 40), (26, 38), (26, 43), (21, 45), (19, 43))
    pair("#618799", (21, 41), (24, 40), (24, 42), (21, 43))

    plate("#1a2d3f", (28, 2), (35, 2), (38, 10), (38, 22), (36, 30),
          (39, 39), (36, 44), (27, 44), (24, 39), (27, 30), (25, 22), (25, 10))
    plate("#8298aa", (28, 4), (35, 4), (36, 11), (35, 24), (33, 31),
          (35, 37), (29, 37), (30, 30), (27, 23), (27, 11))
    plate("#b4c6d0", (29, 4), (34, 4), (35, 8), (34, 12), (29, 12), (28, 8))
    plate("#172b3c", (30, 5), (33, 5), (33, 16), (32, 20), (31, 20), (30, 16))
    plate("#83bbcb", (31, 10), (32, 10), (32, 16), (31, 16))
    plate("#455f73", (28, 22), (30, 25), (33, 25), (35, 22), (33, 30), (30, 30))
    plate("#96aebb", (31, 27), (32, 27), (32, 32), (31, 32))
    plate("#304859", (28, 39), (35, 39), (34, 42), (29, 42))
    for y in range(26, 26 + 2 * min(variant, 3), 2):
        pair("#86a5b4", (23, y), (24, y), (24, y + 1), (23, y + 1))

    return image.resize((128, 96), Image.Resampling.NEAREST)


if __name__ == "__main__":
    output = Path(__file__).resolve().parents[2] / "assets/sprites/enemies/boss"
    for number in range(1, 6):
        mothership(number).save(output / f"boss_{number:02d}.png")
    mothership(1).save(output / "boss.png")
