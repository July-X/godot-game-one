#!/usr/bin/env python3
"""
Pixel Art Asset Generator for Space Bullet Hell
- Primary: Uses Replicate API (cloud AI) for pixel art generation
- Fallback: Pillow-based procedural pixel art (works without API key)
"""

import io
import math
import os
import time
import urllib.parse
from pathlib import Path

import requests
from PIL import Image, ImageDraw

# Pillow 10+ moved NEAREST to Image.Resampling.NEAREST
try:
    _NEAREST = Image.Resampling.NEAREST  # Pillow >= 10
except AttributeError:
    _NEAREST = _NEAREST  # Pillow < 10

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
OUTPUT_DIR = PROJECT_ROOT / "assets" / "sprites"

# ── Cloud AI Provider ──────────────────────────────────────────────
# Pollinations.ai - free, no API key required
# Priority: Pollinations.ai > Replicate (if token set) > Pillow fallback

USE_CLOUD = True  # set False to force Pillow-only mode
REPLICATE_TOKEN = os.environ.get("REPLICATE_API_TOKEN")


# ── Helpers ────────────────────────────────────────────────────────


def save_image(img, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(f"  ✓ Saved: {path.relative_to(PROJECT_ROOT)}")


def quantize_pixel_art(img, max_colors: int = 32):
    """Remove anti-aliasing by quantizing to a limited palette."""
    if img.mode == "RGBA":
        r, g, b, a = img.split()
        rgb = Image.merge("RGB", (r, g, b))
        rgb = rgb.quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT)
        rgb = rgb.convert("RGB")
        r2, g2, b2 = rgb.split()
        img = Image.merge("RGBA", (r2, g2, b2, a))
    else:
        img = img.quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT)
        img = img.convert("RGBA")
    return img


def new_sprite(w: int, h: int):
    """Create transparent RGBA sprite."""
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def remove_background(img, tolerance: int = 40):
    """Remove solid background from AI-generated sprite.

    Detects background color from corner pixels and makes matching
    pixels transparent. Also handles anti-aliased edges.
    """
    # Sample background color from four corners
    w, h = img.size
    corners = [
        img.getpixel((0, 0)),
        img.getpixel((w - 1, 0)),
        img.getpixel((0, h - 1)),
        img.getpixel((w - 1, h - 1)),
    ]
    # Average corner colors as background color
    bg_r = sum(c[0] for c in corners) // 4
    bg_g = sum(c[1] for c in corners) // 4
    bg_b = sum(c[2] for c in corners) // 4

    # Raster: set matching pixels transparent, also handle edges
    pixels = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 10:
                continue
            # Color distance from background
            dr = abs(r - bg_r)
            dg = abs(g - bg_g)
            db = abs(b - bg_b)
            dist = max(dr, dg, db)
            if dist < tolerance:
                # Fully transparent if very close to bg
                if dist < tolerance // 2:
                    pixels[x, y] = (r, g, b, 0)
                else:
                    # Semi-transparent for anti-aliased edges
                    alpha = int(255 * (dist - tolerance // 2) / (tolerance // 2))
                    pixels[x, y] = (r, g, b, min(a, alpha))
    return img


# ── Cloud AI Generation ────────────────────────────────────────────


def ai_generate_sprite(prompt: str, width: int, height: int):
    """Generate sprite via free cloud API. Returns None on failure.

    Tries: Pollinations.ai → (optionally) Replicate → None
    """
    img = _try_pollinations(prompt, width, height)
    if img:
        return img
    if REPLICATE_TOKEN:
        img = _try_replicate(prompt, width, height)
        if img:
            return img
    return None


def _try_pollinations(prompt: str, width: int, height: int):
    """Free text-to-image via Pollinations.ai. No API key needed."""
    if not USE_CLOUD:
        return None
    try:
        full_prompt = (
            f"pixel art {prompt}, retro game sprite, "
            f"limited palette, no anti-aliasing, crisp pixels, no background"
        )
        url = (
            f"https://image.pollinations.ai/prompt/"
            f"{urllib.parse.quote(full_prompt)}"
        )
        resp = requests.get(
            url,
            params={"width": width, "height": height, "nologo": "true", "seed": 42, "model": "flux"},
            timeout=60,
        )
        resp.raise_for_status()
        img = Image.open(io.BytesIO(resp.content)).convert("RGBA")
        img = remove_background(img)
        img = img.resize((width, height), _NEAREST)
        img = quantize_pixel_art(img, 24)
        print("  ☁ Generated via Pollinations.ai")
        return img
    except Exception as e:
        print(f"  ⚠ Pollinations error: {e}")
    return None


def _try_replicate(prompt: str, width: int, height: int):
    """Fallback: Replicate API (requires token + credits)."""
    try:
        import replicate  # type: ignore[import-untyped]
        output = replicate.run(
            "black-forest-labs/flux-schnell",
            input={
                "prompt": f"pixel art game sprite, {prompt}, retro 8-bit style, no background",
                "num_outputs": 1,
                "num_inference_steps": 4,
                "output_format": "png",
            },
        )
        if output:
            for url in output:
                resp = requests.get(url, timeout=30)
                resp.raise_for_status()
                img = Image.open(io.BytesIO(resp.content)).convert("RGBA")
                img = remove_background(img)
                img = img.resize((width, height), _NEAREST)
                img = quantize_pixel_art(img, 24)
                print("  ☁ Generated via Replicate")
                return img
    except Exception as e:
        print(f"  ⚠ Replicate error: {e}")
    return None


# ── Player Ship ────────────────────────────────────────────────────


def make_player_ship():
    """64x64 top-down pixel art spaceship."""
    img = new_sprite(64, 64)
    draw = ImageDraw.Draw(img)
    cx = 32

    BODY = (28, 77, 191)
    DARK = (15, 40, 100)
    LIGHT = (60, 130, 240)
    COCKPIT = (100, 200, 255)
    GUN = (180, 180, 200)
    WING = (20, 55, 140)
    STRIPE = (230, 180, 50)
    FIRE = (255, 120, 30)

    # Flame
    for i in range(3):
        fx = cx - 6 + i * 6
        draw.rectangle((fx - 2, 58, fx + 2, 63), fill=FIRE)

    # Main fuselage
    draw.polygon([(cx - 8, 44), (cx + 8, 44), (cx + 12, 20), (cx - 12, 20)], fill=BODY)
    draw.polygon([(cx - 12, 20), (cx + 12, 20), (cx + 18, 48), (cx - 18, 48)], fill=DARK)
    draw.rectangle((cx - 4, 22, cx + 4, 46), fill=LIGHT)

    # Nose
    draw.polygon([(cx - 10, 20), (cx + 10, 20), (cx, 6)], fill=BODY)
    draw.polygon([(cx - 6, 20), (cx + 6, 20), (cx, 8)], fill=LIGHT)

    # Wings
    for dy in range(-1, 5):
        yy = 28 + dy * 3
        shrink = dy * 2
        draw.polygon([(cx - 18 + shrink, yy), (cx - 12, yy - 4), (cx - 12, yy + 4)], fill=WING)
        draw.polygon([(cx + 18 - shrink, yy), (cx + 12, yy - 4), (cx + 12, yy + 4)], fill=WING)

    # Wingtip lights
    draw.rectangle((cx - 26, 36, cx - 22, 38), fill=(255, 50, 50))
    draw.rectangle((cx + 22, 36, cx + 26, 38), fill=(50, 200, 50))

    # Cockpit
    draw.ellipse((cx - 6, 14, cx + 6, 24), fill=COCKPIT)
    draw.ellipse((cx - 4, 16, cx + 4, 22), fill=(180, 230, 255))

    # Guns
    draw.rectangle((cx - 16, 16, cx - 12, 20), fill=GUN)
    draw.rectangle((cx + 12, 16, cx + 16, 20), fill=GUN)

    # Stripes
    draw.rectangle((cx - 10, 40, cx + 10, 42), fill=STRIPE)

    return quantize_pixel_art(img, 20)


# ── Enemies ────────────────────────────────────────────────────────


def make_enemy_type0():
    """48x48 red diamond chaser."""
    img = new_sprite(48, 48)
    draw = ImageDraw.Draw(img)
    cx, cy = 24, 24

    draw.polygon([(cx, 4), (cx + 16, cy), (cx, 44), (cx - 16, cy)], fill=(180, 30, 20))
    draw.polygon([(cx, 10), (cx + 10, cy), (cx, 38), (cx - 10, cy)], fill=(220, 50, 30))

    # Eyes
    draw.ellipse((cx - 8, cy - 6, cx - 2, cy + 2), fill=(255, 230, 50))
    draw.ellipse((cx + 2, cy - 6, cx + 8, cy + 2), fill=(255, 230, 50))
    draw.ellipse((cx - 6, cy - 4, cx - 3, cy), fill=(0, 0, 0))
    draw.ellipse((cx + 3, cy - 4, cx + 6, cy), fill=(0, 0, 0))

    return quantize_pixel_art(img, 16)


def make_enemy_type1():
    """48x48 green zigzag."""
    img = new_sprite(48, 48)
    draw = ImageDraw.Draw(img)
    cx, cy = 24, 24

    draw.polygon([(cx, 4), (cx + 18, 10), (cx + 18, 38), (cx, 44), (cx - 18, 38), (cx - 18, 10)], fill=(20, 150, 40))
    draw.polygon([(cx, 8), (cx + 12, 13), (cx + 12, 35), (cx, 40), (cx - 12, 35), (cx - 12, 13)], fill=(30, 190, 50))

    # Eyes
    draw.ellipse((cx - 8, cy - 4, cx - 2, cy + 3), fill=(255, 230, 50))
    draw.ellipse((cx + 2, cy - 4, cx + 8, cy + 3), fill=(255, 230, 50))
    draw.ellipse((cx - 6, cy - 2, cx - 3, cy + 1), fill=(0, 0, 0))
    draw.ellipse((cx + 3, cy - 2, cx + 6, cy + 1), fill=(0, 0, 0))

    # Antennae
    draw.line((cx - 6, 4, cx - 6, 0), fill=(30, 190, 50), width=2)
    draw.line((cx + 6, 4, cx + 6, 0), fill=(30, 190, 50), width=2)
    draw.ellipse((cx - 8, -2, cx - 4, 2), fill=(255, 230, 50))
    draw.ellipse((cx + 4, -2, cx + 8, 2), fill=(255, 230, 50))

    return quantize_pixel_art(img, 16)


def make_enemy_type2():
    """48x48 purple orbit/alien."""
    img = new_sprite(48, 48)
    draw = ImageDraw.Draw(img)
    cx, cy = 24, 24

    draw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=(140, 20, 180))

    for angle_deg in range(0, 360, 45):
        rad = math.radians(angle_deg)
        sx = cx + int(math.cos(rad) * 14)
        sy = cy + int(math.sin(rad) * 14)
        ex = cx + int(math.cos(rad) * 20)
        ey = cy + int(math.sin(rad) * 20)
        draw.line((sx, sy, ex, ey), fill=(180, 40, 220), width=3)

    draw.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), fill=(170, 60, 210))

    draw.ellipse((cx - 7, cy - 5, cx - 2, cy + 2), fill=(255, 230, 50))
    draw.ellipse((cx + 2, cy - 5, cx + 7, cy + 2), fill=(255, 230, 50))
    draw.ellipse((cx - 5, cy - 3, cx - 3, cy), fill=(0, 0, 0))
    draw.ellipse((cx + 3, cy - 3, cx + 5, cy), fill=(0, 0, 0))

    return quantize_pixel_art(img, 16)


# ── Boss ────────────────────────────────────────────────────────────


def make_boss_sprite():
    """128x96 pixel art boss."""
    img = new_sprite(128, 96)
    draw = ImageDraw.Draw(img)
    cx, cy = 64, 48

    # Engine flames
    for i in range(5):
        fx = cx - 16 + i * 8
        draw.rectangle((fx - 3, 85, fx + 3, 95), fill=(255, 100, 20))
        draw.rectangle((fx - 2, 80, fx + 2, 85), fill=(255, 60, 10))

    # Main hull
    draw.polygon([(cx - 36, 80), (cx + 36, 80), (cx + 40, 30), (cx - 40, 30)], fill=(100, 12, 8))
    draw.polygon([(cx - 28, 80), (cx + 28, 80), (cx + 32, 34), (cx - 32, 34)], fill=(130, 18, 12))

    # Wings
    draw.polygon([(cx - 60, 60), (cx - 36, 40), (cx - 36, 70), (cx - 60, 76)], fill=(80, 8, 6))
    draw.polygon([(cx + 60, 60), (cx + 36, 40), (cx + 36, 70), (cx + 60, 76)], fill=(80, 8, 6))

    # Armor plates
    for i in range(4):
        px = cx - 24 + i * 16
        draw.rectangle((px, 38, px + 6, 72), fill=(80, 10, 8))

    # Nose
    draw.polygon([(cx - 16, 30), (cx + 16, 30), (cx, 10)], fill=(130, 18, 12))
    draw.polygon([(cx - 10, 30), (cx + 10, 30), (cx, 12)], fill=(160, 24, 16))

    # Cockpit
    draw.ellipse((cx - 12, 22, cx + 12, 36), fill=(30, 80, 120))
    draw.ellipse((cx - 8, 24, cx + 8, 34), fill=(50, 140, 200))

    # Cannons
    for side in (-1, 1):
        bx = cx + side * 28
        draw.rectangle((bx - 3, 30, bx + 3, 44), fill=(160, 160, 180))

    # Turrets
    for side in (-1, 1):
        tx = cx + side * 50
        draw.ellipse((tx - 6, 52, tx + 6, 64), fill=(120, 120, 140))
        draw.rectangle((tx - 2, 44, tx + 2, 52), fill=(160, 160, 180))

    # Shield ring
    draw.ellipse((cx - 48, cy - 24, cx + 48, cy + 24), outline=(60, 130, 220), width=2)

    return quantize_pixel_art(img, 24)


# ── Powerups ───────────────────────────────────────────────────────


def make_powerup_spread():
    img = new_sprite(32, 32)
    draw = ImageDraw.Draw(img)
    cx, cy = 16, 16
    pts = []
    for i in range(10):
        a = i * math.pi / 5 - math.pi / 2
        r = 13 if i % 2 == 0 else 5
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=(30, 200, 50))
    return quantize_pixel_art(img, 8)


def make_powerup_speed():
    img = new_sprite(32, 32)
    draw = ImageDraw.Draw(img)
    cx, cy = 16, 16
    draw.polygon([(cx, 2), (cx + 12, cy), (cx, 30), (cx - 12, cy)], fill=(30, 100, 220))
    draw.polygon([(cx, 6), (cx + 8, cy), (cx, 26), (cx - 8, cy)], fill=(50, 150, 255))
    return quantize_pixel_art(img, 8)


def make_powerup_power():
    img = new_sprite(32, 32)
    draw = ImageDraw.Draw(img)
    cx, cy = 16, 16
    pts = []
    for i in range(6):
        a = i * math.pi / 3 - math.pi / 6
        pts.append((cx + 12 * math.cos(a), cy + 12 * math.sin(a)))
    draw.polygon(pts, fill=(220, 40, 30))
    return quantize_pixel_art(img, 8)


def make_powerup_heal():
    img = new_sprite(32, 32)
    cx, cy = 16, 16
    for y in range(32):
        for x in range(32):
            dx = (x - cx) / 13.0
            dy = (y - cy + 2) / 13.0
            val = (dx * dx + dy * dy - 1) ** 3 - dx * dx * dy * dy * dy
            if val <= 0:
                depth = math.sqrt(dx * dx + dy * dy) / 1.5
                r = int(220 * (1 - depth * 0.3))
                g = int(40 * (1 - depth * 0.3))
                b = int(50 * (1 - depth * 0.3))
                img.putpixel((x, y), (r, g, b, 255))
    return quantize_pixel_art(img, 8)


def make_powerup_bomb():
    img = new_sprite(32, 32)
    draw = ImageDraw.Draw(img)
    cx, cy = 16, 16
    draw.ellipse((cx - 11, cy - 8, cx + 11, cy + 12), fill=(220, 180, 30))
    draw.rectangle((cx - 1, cy - 14, cx + 1, cy - 8), fill=(140, 140, 150))
    draw.ellipse((cx - 3, cy - 17, cx + 3, cy - 13), fill=(255, 120, 20))
    draw.ellipse((cx - 5, cy - 4, cx + 1, cy + 2), fill=(255, 220, 60))
    return quantize_pixel_art(img, 8)


# ── Bullets ────────────────────────────────────────────────────────


def make_bullet_player(level: int = 1):
    """16x32 per-level bullet."""
    img = new_sprite(16, 32)
    draw = ImageDraw.Draw(img)
    cx = 8

    palette = {
        1: ((60, 140, 255), (120, 200, 255)),
        2: ((40, 200, 220), (100, 240, 255)),
        3: ((160, 60, 220), (200, 120, 255)),
        4: ((240, 200, 40), (255, 230, 100)),
    }
    body, tip = palette.get(level, palette[1])

    draw.polygon([(cx - 4, 30), (cx + 4, 30), (cx + 4, 6), (cx - 4, 6)], fill=body)
    draw.polygon([(cx - 3, 6), (cx + 3, 6), (cx, 1)], fill=tip)
    if level >= 3:
        draw.line((cx, 30, cx, 3), fill=(255, 255, 255), width=1)
    if level >= 4:
        draw.line((cx - 1, 28, cx - 1, 4), fill=(255, 255, 200), width=1)
        draw.line((cx + 1, 28, cx + 1, 4), fill=(255, 255, 200), width=1)

    return quantize_pixel_art(img, 8)


def make_bullet_enemy():
    """16x32 red bullet."""
    img = new_sprite(16, 32)
    draw = ImageDraw.Draw(img)
    cx = 8

    draw.polygon([(cx - 5, 30), (cx + 5, 30), (cx + 5, 6), (cx - 5, 6)], fill=(220, 50, 30))
    draw.polygon([(cx - 3, 6), (cx + 3, 6), (cx, 1)], fill=(255, 100, 60))
    draw.line((cx, 30, cx, 4), fill=(255, 150, 100), width=1)

    return quantize_pixel_art(img, 8)


# ── Explosion ──────────────────────────────────────────────────────


def make_explosion_frames():
    """8 frames of 64x64 explosion."""
    frames = []
    for f in range(8):
        img = new_sprite(64, 64)
        cx, cy = 32, 32
        progress = f / 7.0
        radius = 6 + progress * 22
        r_outer = int(radius)
        r_inner = max(2, int(radius * 0.4))

        px = img.load()
        for y in range(64):
            for x in range(64):
                dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
                if dist < r_outer:
                    t = dist / r_outer
                    brightness = 1 - progress
                    alpha = int(255 * brightness * (1 - t * 0.6))
                    if alpha > 0:
                        r_val = min(255, int(255 * brightness))
                        g_val = min(255, int(150 * (1 - t)))
                        b_val = int(50 * (1 - t))
                        px[x, y] = (r_val, g_val, b_val, alpha)
                if dist < r_inner:
                    r, g, b, a = px[x, y]
                    px[x, y] = (min(255, r + 100), min(255, g + 100), min(255, b + 100), min(255, a + 200))

        frames.append(quantize_pixel_art(img, 16))
    return frames


# ── Main Pipeline ──────────────────────────────────────────────────


def main():
    print("=" * 60)
    print("Pixel Art Asset Generator")
    print(f"Mode: {'Cloud (Pollinations.ai)' if USE_CLOUD else 'Pillow Placeholder'}")
    print("=" * 60)

    print("\n[1/4] Player Ship (64x64)")
    img = ai_generate_sprite(
        "top-down pixel art spaceship, blue hull, forward facing, retro space shooter, "
        "symmetric, wings, cockpit, engine, 64x64, game sprite, no background",
        64, 64,
    ) or make_player_ship()
    save_image(img, OUTPUT_DIR / "player" / "base.png")
    time.sleep(2.0)

    print("\n[2/4] Enemies")
    enemy_makers = [make_enemy_type0, make_enemy_type1, make_enemy_type2]
    enemy_prompts = [
        "red diamond enemy spaceship, pixel art, 48x48, angry face, retro shooter",
        "green square enemy spaceship, pixel art, 48x48, mechanical, retro shooter",
        "purple circular enemy spaceship, pixel art, 48x48, alien, retro shooter",
    ]
    for etype in range(3):
        print(f"  Enemy type {etype}...")
        img = ai_generate_sprite(enemy_prompts[etype], 48, 48) or enemy_makers[etype]()
        save_image(img, OUTPUT_DIR / "enemies" / f"type_{etype}.png")
        time.sleep(2.0)

    print("\n[3/4] Boss")
    img = ai_generate_sprite(
        "large dark red pixel art battleship, top-down view, 128x96, "
        "menacing, heavy armor, cannons, retro space shooter boss",
        128, 96,
    ) or make_boss_sprite()
    save_image(img, OUTPUT_DIR / "boss" / "boss.png")
    time.sleep(2.0)

    print("\n[4/4] Powerups (32x32)")
    powerup_data = [
        ("spread", "green star pixel art icon, retro game powerup, 32x32", make_powerup_spread),
        ("speed", "blue diamond pixel art icon, retro game powerup, 32x32", make_powerup_speed),
        ("power", "red hexagon pixel art icon, retro game powerup, 32x32", make_powerup_power),
        ("heal", "pink heart pixel art icon, retro game powerup, 32x32", make_powerup_heal),
        ("bomb", "yellow bomb pixel art icon, retro game powerup, 32x32", make_powerup_bomb),
    ]
    for ptype, prompt, maker in powerup_data:
        print(f"  {ptype}...")
        img = ai_generate_sprite(prompt, 32, 32) or maker()
        save_image(img, OUTPUT_DIR / "powerups" / f"{ptype}.png")
        time.sleep(1.5)

    # ── Secondary Assets ───────────────────────────────────────
    print("\n--- Secondary Assets ---")

    print("[5] Player Bullets (16x32)")
    for level in range(1, 5):
        save_image(make_bullet_player(level), OUTPUT_DIR / "bullets" / f"player_lv{level}.png")

    print("[6] Enemy Bullet")
    save_image(make_bullet_enemy(), OUTPUT_DIR / "bullets" / "enemy.png")

    print("[7] Explosion Frames (64x64)")
    for i, frame in enumerate(make_explosion_frames()):
        save_image(frame, OUTPUT_DIR / "explosion" / f"frame_{i}.png")

    print("\n" + "=" * 60)
    print("Generation Complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
