// Offline only. Pass the extracted PixelFX checkout pinned in docs/art_audio_pipeline.md.
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

if (!process.argv[2]) throw new Error("Usage: node make_pixelfx.mjs /path/to/pixelfx");
const source = pathToFileURL(resolve(process.argv[2], "src") + "/");
const { createFrame, painterFor, hex, Rng, flare } = await import(new URL("core/index.js", source));
const { spikes, star, stone } = await import(new URL("fx/impacts/_lib.js", source));
const { rock } = await import(new URL("fx/explosions/_lib.js", source));
const out = fileURLToPath(new URL("../../assets/sprites/explosion/", import.meta.url));

function saveStrip(name, frames) {
  const { w, h } = frames[0];
  if (frames.some(f => !f.color.some(Boolean))) throw new Error("Empty frame in " + name);
  const png = `
from PIL import Image
import sys
w, h, n = map(int, sys.argv[1:4])
strip = Image.new("RGBA", (w*n, h))
for i in range(n):
    strip.paste(Image.frombytes("RGBA", (w, h), sys.stdin.buffer.read(4*w*h)), (i*w, 0))
strip.save(sys.argv[4])
`;
  execFileSync("python3", ["-c", png, w, h, frames.length, resolve(out, name)],
    { input: Buffer.concat(frames.map(f => Buffer.from(f.color.buffer))) });
}

// PixelFX places the spark 24 pixels above its declared pivot. Crop and rotate
// around the actual contact pixel (116,60), preserving the pixel at (15,15).
const rays = spikes(new Rng(6), 9, Math.PI - 0.08, { len: [7, 10.5], w: [1.0, 1.4], fwd: 0.9, back: 0.4 });
for (const ray of rays) if (Math.cos(ray.a - Math.PI) < -0.2) ray.len *= 0.8;
const ice = ["#446b86", "#82bdd2", "#c2e4f1", "#e5f8ff"].map(hex);
const hits = [];
for (let i = 0; i < 6; i++) {
  const atlas = createFrame(152, 100);
  const p = painterFor(atlas);
  if (i < 3) {
    star(p, 116, 60, rays, [0.64, 0.78, 0.68][i], [0.80, 0.59, 0.38][i], ice, 1, 2.2);
  } else {
    for (const ray of rays.filter(r => r.len > 7)) {
      const tip = ray.len * (0.51 + 0.038 * i), base = tip - (7 - i);
      p.line(116 + Math.cos(ray.a) * base, 60 + Math.sin(ray.a) * base,
        116 + Math.cos(ray.a) * tip, 60 + Math.sin(ray.a) * tip, ice[1]);
    }
  }
  const cell = createFrame(31, 31);
  for (let y = 0; y < 31; y++)
    for (let x = 0; x < 31; x++)
      cell.color[y * 31 + x] = atlas.color[(60 + x - 15) * atlas.w + (116 - y + 15)];
  hits.push(cell);
}
saveStrip("ordinary_hit.png", hits);

const fire = ["#763e39", "#ac5235", "#ed8c48", "#ffc87c", "#fff2cb"].map(hex);
const hotRock = [fire[4], fire[4], fire[3], fire[2], fire[1], fire[0]];
const metal = stone("#a9674f");
const bursts = [];
for (let i = 0; i < 9; i++) {
  const cell = createFrame(60, 60);
  const p = painterFor(cell).place(30, 30);
  if (i < 4) {
    p.circle(0, 0, [8, 9, 6, 3][i], fire[1]);
    p.circle(0, 0, [6, 6, 4, 2][i], fire[2]);
    flare(p, 0, 0, [18, 15, 11, 6][i], 1, fire);
  }
  for (const [j, angle] of [0.28, 1.23, 2.57, 3.53, 4.52, 5.67].entries()) {
    const dist = 7 + (14 + j % 3 * 2) * (1 - (1 - i / 8) ** 2);
    rock(p, { x: Math.cos(angle) * dist, y: Math.sin(angle) * dist,
      s: (2.9 - i * 0.16) * (0.75 + j % 3 * 0.18), a: angle + i * 0.4,
      life: 1, heat: 0.95 - i * 0.09 }, metal, hotRock);
  }
  bursts.push(cell);
}
saveStrip("ordinary_death.png", bursts);
