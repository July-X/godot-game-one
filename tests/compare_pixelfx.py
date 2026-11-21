"""Compare the native Godot captures from pixelfx_probe.tscn (requires Pillow)."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def compare(root):
    takes = ("A", "B", "OFF", "A-clear", "B-clear", "OFF-clear")
    timeline = (root / "A/frames.jsonl").read_bytes()
    for take in takes:
        assert (root / take / "frames.jsonl").read_bytes() == timeline, f"{take}: different timeline"
    rows = [json.loads(line) for line in timeline.splitlines()]
    assert [r[0] for r in rows] == list(range(140))
    overlaps = {"A": 0, "B": 0}
    centers, dormant, first = {}, [], {}
    hit_frames, death_frames = [], []
    for tick, bullets, effects in rows:
        pictures = []
        for take in takes:
            with Image.open(root / take / f"frame_{tick:03}.png") as image:
                assert image.size == (1280, 720)
                pictures.append(image.convert("RGB"))
        a, b, off, a_clear, b_clear, off_clear = pictures
        diff = ImageChops.difference(b, off)
        if not effects:
            assert diff.getbbox() is None and ImageChops.difference(a, off).getbbox() is None, tick
            dormant.append(tick)
            continue
        # Bullet-free passes reveal paint underneath the foreground bullet.
        # 28 and 8 RGB levels exclude background and near-invisible fade pixels, respectively.
        touched = {"A": set(), "B": set()}
        for x, y in bullets:
            if all(abs(x - ex) > 45 or abs(y - ey) > 35 for _, ex, ey in effects):
                continue
            x, y = round(x), round(y)
            for py in range(y - 6, y + 7):
                for px in range(x - 20, x + 21):
                    point = (px, py)
                    reference = off.getpixel(point)
                    background = off_clear.getpixel(point)
                    if max(abs(l - r) for l, r in zip(reference, background)) < 28:
                        continue
                    for variant, clear, rendered in (("A", a_clear, a), ("B", b_clear, b)):
                        if max(abs(l - r) for l, r in zip(clear.getpixel(point), background)) < 8:
                            continue
                        assert rendered.getpixel(point) == reference, (variant, tick, point)
                        touched[variant].add(point)
        for variant in overlaps:
            overlaps[variant] += len(touched[variant])
        for crossed_tick, center in ((34, (640, 320)), (66, (640, 300))):
            if tick == crossed_tick and center in touched["B"]:
                centers[tick] = center
        if tick in (32, 64):
            origin = (640, 320 if tick == 32 else 300)
            background = off_clear.getpixel(origin)
            assert a_clear.getpixel(origin) == background, tick
            assert max(abs(l - r) for l, r in zip(b_clear.getpixel(origin), background)) > 128, tick
            first[tick] = [ImageChops.difference(a, off).getbbox(), diff.getbbox()]
            left, top, right, bottom = first[tick][1]
            assert 615 <= left < right <= 665 and 275 <= top < bottom <= 338, first[tick]
        if 32 <= tick <= 39 and diff.getbbox():
            hit_frames.append(tick)
        if 64 <= tick <= 73 and diff.crop((612, 274, 669, 312)).getbbox():
            death_frames.append(tick)
    assert hit_frames == list(range(32, 38)), hit_frames
    assert death_frames == list(range(64, 73)), death_frames
    assert set(centers) == {34, 66} and min(overlaps.values()) > 0
    for mode in ("start_shield_hit", "start_core_pickup"):
        with Image.open(root / "A" / f"{mode}.png") as original, Image.open(root / "B" / f"{mode}.png") as candidate:
            assert original.convert("RGBA").tobytes() == candidate.convert("RGBA").tobytes(), mode
    return dict(frames=len(rows), matching_foreground_pixels=overlaps, coincident_centers=centers,
                frames_without_effects=len(dormant), visible_hit=hit_frames, visible_death=death_frames,
                first_changed_bounds_A_B=first, identical_protected_modes=["shield", "core"])


if __name__ == "__main__":
    print(json.dumps(compare(Path(sys.argv[1])), indent=2))
