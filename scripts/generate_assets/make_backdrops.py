"""Bake the original '远行与裂隙' concept into two display-only textures."""

from pathlib import Path

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 800, 450
Y, X = np.indices((HEIGHT, WIDTH), dtype=float)
BASE = np.array([10, 16, 32])
DEST = Path(__file__).resolve().parents[2] / "assets" / "background"


def noise(seed, shape):
    rng = np.random.default_rng(seed)
    cells = Image.fromarray(rng.integers(0, 256, shape, dtype=np.uint8))
    return np.asarray(cells.resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC)) / 255 - 0.5


def cruise():
    broad = noise(43, (7, 14))
    small = noise(44, (39, 65))
    arc = np.exp(-((Y - (94 + 0.23 * X + broad * 80)) / 95) ** 2)
    edge = np.clip((X - WIDTH * 0.36) / (WIDTH * 0.6), 0, 1)
    haze = arc * (0.12 + edge * 0.65) * np.clip(0.52 + broad * 0.8, 0, 1)
    sky = BASE + haze[..., None] * np.array([10, 22, 38])
    dx = (X - WIDTH * 0.92) / 144
    dy = (Y - 72) / 144
    rad = np.hypot(dx, dy)
    pole = np.sqrt(np.maximum(0, 1 - rad * rad))
    light = np.clip(-0.87 * dx - 0.26 * dy + 0.18 * pole, 0, 1) ** 1.6
    band = 0.55 + 0.18 * np.sin((dy + dx * 0.33 + broad * 0.09) * 37)
    band += 0.14 * np.sin((dy + dx * 0.33 + small * 0.035) * 96) + 0.13 * small
    rim = np.exp(-np.abs(rad - 0.985) * 78) * light
    disk = (BASE * 0.66 + light[..., None] * (band[..., None] * np.array([25, 46, 70]) + 6)
            + rim[..., None] * np.array([15, 27, 40]))
    halo = np.exp(-np.maximum(rad - 1, 0) * 49) * light
    outside = sky + halo[..., None] * np.array([9, 16, 29])
    cut = np.clip((1.004 - rad) * 140, 0, 1)
    return outside * (1 - cut[..., None]) + disk * cut[..., None]


def rift():
    broad = noise(210, (8, 12))
    wisps = noise(211, (34, 50))
    radial = np.hypot((X - WIDTH * 0.5) * 1.18, Y + 300)
    distance = radial + broad * 71 + wisps * 14
    outer = np.clip(np.abs(X - WIDTH * 0.5) / (WIDTH * 0.46), 0, 1)
    sky = np.broadcast_to([10, 12, 25], (HEIGHT, WIDTH, 3)).astype(float).copy()
    arc = np.exp(-((distance - 492) / 74) ** 2)
    echo = np.exp(-((distance - 574) / 26) ** 2)
    filament = 0.60 + 0.19 * np.cos(distance * 0.06 + wisps * 2.5) + broad * 0.5
    dust = (arc * filament + echo * 0.17) * (0.065 + outer ** 1.7 * 0.84)
    sky += dust[..., None] * np.array([42, 35, 66])
    return sky


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    for name, pixels in (("cruise", cruise()), ("rift", rift())):
        Image.fromarray(np.uint8(np.clip(np.round(pixels), 0, 255))).save(
            DEST / f"{name}.png", optimize=True
        )
