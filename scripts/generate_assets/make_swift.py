"""Draw the two first-tier ships on the same 48-pixel grid. Run this file to rebuild."""

from PIL import ImageDraw

from generate_core_assets import OUTPUT_DIR, new_sprite, save_image


def finish_first_hull(image, outline, shadow, mid, lit, ice):
    # Keep both pilots' silhouette, barrel tips and engine sockets on the same grid.
    mask = image.getchannel("A")
    draw = ImageDraw.Draw(image)
    for mirror in (False, True):
        def facet(points, color):
            draw.polygon([(47 - x if mirror else x, y) for x, y in points], fill=color)

        facet([(2, 38), (7, 30), (18, 22), (21, 19), (19, 26), (10, 32)], lit if not mirror else mid)
        facet([(4, 36), (18, 25), (20, 25), (17, 28), (8, 34)], mid if not mirror else shadow)
        facet([(15, 7), (16, 7), (16, 10), (15, 10)], mid)
        facet([(17, 35), (20, 34), (21, 37), (21, 40), (19, 42), (16, 39)], shadow)
        facet([(17, 36), (20, 36), (20, 40), (17, 40)], outline)
        facet([(17, 36), (20, 36), (20, 37), (17, 37)], mid)
        facet([(18, 39), (20, 39), (20, 40), (18, 40)], lit)

    # One lit nose ridge and an offset canopy reflection give the wings a clear front.
    draw.polygon([(23, 2), (24, 3), (27, 16), (25, 19), (20, 18), (21, 11)], shadow)
    draw.polygon([(23, 2), (24, 4), (24, 13), (21, 18), (21, 12)], lit)
    draw.line([(23, 3), (22, 8), (21, 14)], fill=ice)
    draw.polygon([(23, 12), (25, 12), (27, 17), (27, 23), (24, 26), (20, 24), (20, 18)], outline)
    draw.polygon([(23, 14), (25, 15), (26, 19), (25, 22), (22, 23), (21, 20)], mid)
    draw.polygon([(23, 14), (25, 15), (24, 18), (22, 21), (21, 19)], lit)
    draw.line([(23, 15), (22, 17)], fill=ice)
    draw.polygon([(20, 25), (24, 24), (28, 25), (27, 31), (25, 35), (22, 35), (20, 31)], outline)
    draw.polygon([(23, 25), (26, 26), (26, 31), (24, 34), (22, 33), (22, 29)], shadow)
    # Texture y=29..30 sits at the collision center (0, 8) with the existing 1.45× scale.
    draw.rectangle((23, 27, 24, 33), fill=lit)
    draw.rectangle((23, 29, 24, 30), fill="#edfcff")
    image.putalpha(mask)


def hull(second_pilot):
    image = new_sprite(48, 48)
    draw = ImageDraw.Draw(image)
    outline, shadow, mid, lit, ice = (
        ("#211d38", "#473b68", "#7d6caa", "#aa98d8", "#e1daff") if second_pilot
        else ("#0b1d30", "#193d59", "#326f97", "#62acd0", "#b6ecfa")
    )
    # Each wing is reflected about the same half-pixel centerline.
    for right in (False, True):
        def panel(points, color):
            draw.polygon([(47 - x if right else x, y) for x, y in points], fill=color)

        panel([(23, 1), (20, 6), (19, 17), (16, 22), (7, 29), (2, 36),
               (1, 39), (14, 34), (16, 36), (16, 41), (18, 43), (21, 42),
               (22, 38), (23, 37)], outline)
        panel([(23, 4), (21, 8), (20, 20), (16, 25), (8, 31), (4, 36),
               (15, 32), (18, 35), (18, 40), (20, 40), (21, 35), (23, 35)], shadow)
        panel([(23, 5), (22, 9), (21, 20), (17, 25), (9, 32), (6, 35),
               (17, 31), (20, 34), (23, 31)], mid)
        panel([(20, 24), (12, 30), (9, 33), (18, 29), (21, 28)], lit)
        # Primary barrels align with the existing opening volley at (±12, -24).
        panel([(15, 7), (16, 7), (17, 23), (15, 25)], shadow)
        panel([(15, 7), (16, 7), (16, 10), (15, 10)], lit)
        panel([(17, 36), (20, 35), (20, 40), (17, 40)], outline)
        panel([(18, 38), (19, 38), (19, 40), (18, 40)], lit)
    draw.polygon([(23, 5), (24, 5), (26, 16), (26, 20), (21, 20), (21, 16)], fill=lit)
    draw.rectangle((21, 19, 26, 26), fill=outline)
    draw.rectangle((22, 20, 25, 24), fill=mid)
    draw.rectangle((22, 20, 24, 21), fill=ice)
    if second_pilot:
        draw.rectangle((19, 28, 20, 30), fill=ice)
        draw.rectangle((27, 28, 28, 30), fill=ice)
    else:
        finish_first_hull(image, outline, shadow, mid, lit, ice)
    return image


if __name__ == "__main__":
    first, second = hull(False), hull(True)
    assert first.getchannel("A").tobytes() == second.getchannel("A").tobytes()
    for pilot, image in enumerate((first, second), 1):
        save_image(image, OUTPUT_DIR / "player" / f"swift_p{pilot}.png")
    exhaust = new_sprite(16, 10)
    draw = ImageDraw.Draw(exhaust)
    for x in (2, 13):
        draw.rectangle((x - 1, 0, x + 1, 4), fill=(152, 207, 255, 215))
        draw.line((x, 4, x, 8), fill=(104, 172, 231, 160))
        draw.point((x, 1), fill="white")
    save_image(exhaust, OUTPUT_DIR / "player" / "swift_exhaust.png")
