#!/usr/bin/env python3
"""Generate a unique, native 512x512 OpenSimulator R32 island template."""

from __future__ import annotations

import argparse
import json
import math
import random
import secrets
import struct
import zlib
from pathlib import Path

SIZE = 512
SEA_LEVEL = 20.0
PRESETS = Path(__file__).resolve().parent / "presets"


def smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


class Noise:
    def __init__(self, seed: int, step: int = 32) -> None:
        self.step = step
        self.rng = random.Random(seed)
        self.grid = [[self.rng.uniform(-1.0, 1.0) for _ in range(SIZE // step + 2)] for _ in range(SIZE // step + 2)]

    def at(self, x: int, y: int) -> float:
        x = max(0, min(SIZE - 1, x))
        y = max(0, min(SIZE - 1, y))
        gx, gy = x / self.step, y / self.step
        ix, iy = int(gx), int(gy)
        tx, ty = smooth(gx - ix), smooth(gy - iy)
        a = self.grid[iy][ix] * (1.0 - tx) + self.grid[iy][ix + 1] * tx
        b = self.grid[iy + 1][ix] * (1.0 - tx) + self.grid[iy + 1][ix + 1] * tx
        return a * (1.0 - ty) + b * ty


def gauss(value: float, centre: float, spread: float) -> float:
    return math.exp(-((value - centre) / spread) ** 2)


def atoll_height(x: int, y: int, noise: Noise, shape: tuple[float, float, float]) -> float:
    cx, cy, gap_angle = shape
    dx, dy = x - cx, y - cy
    radius = math.hypot(dx * (1.0 + 0.08 * math.sin(math.atan2(dy, dx) * 3)), dy)
    angle = math.atan2(dy, dx)
    gap = math.exp(-((math.atan2(math.sin(angle - gap_angle), math.cos(angle - gap_angle))) / 0.28) ** 4)
    ring = gauss(radius, 132 + 7 * noise.at(x, y), 17)
    land = ring * (1.0 - gap * 0.96)
    submerged_shelf = gauss(radius, 130, 32) * 9
    height = -34 + submerged_shelf + land * (66 + 12 * noise.at(x, y))
    # A broad, low landing shelf on the western arm.
    shelf = gauss(x, cx - 120, 22) * gauss(y, cy - 8, 26)
    height += shelf * 24
    return height


def archipelago_height(x: int, y: int, noise: Noise, centres: list[tuple[float, float]]) -> float:
    heights = [47, 38, 44, 34]
    land = 0.0
    shelf = 0.0
    for i, ((cx, cy), peak) in enumerate(zip(centres, heights)):
        scale = 1.0 + 0.07 * noise.at(x + i * 37, y - i * 23)
        radius = math.hypot((x - cx) / (78 * scale), (y - cy) / (61 * scale))
        island = max(0.0, 1.0 - radius)
        land = max(land, island ** 0.72 * peak)
        shelf = max(shelf, max(0.0, 1.22 - radius) * 14)
    return -32 + shelf + land + noise.at(x, y) * land * 0.10


def mountain_height(x: int, y: int, noise: Noise, shape: tuple[float, float, float, float]) -> float:
    cx, cy, peak_x, peak_y = shape
    radius = math.hypot((x - cx) / 1.04, (y - cy) / 0.96)
    island = max(0.0, 1.0 - radius / 214)
    foothill = island ** 0.8 * 43
    summit = gauss(x, peak_x, 78) * gauss(y, peak_y, 83) * 118
    ridges = gauss(x, cx - 72, 38) * gauss(y, cy + 38, 66) * 34
    detail = noise.at(x, y) * island * 13
    return -36 + foothill + summit + ridges + detail


def shape_parameters(kind: str, seed: int):
    rng = random.Random(seed ^ 0xA7011)
    if kind == "atoll":
        return (256 + rng.uniform(-14, 14), 256 + rng.uniform(-14, 14), rng.uniform(-0.82, -0.58))
    if kind == "archipelago":
        rng = random.Random(seed ^ 0x4A11)
        centres = [(256, 352), (350, 256), (256, 160), (162, 256)]
        return [(x + rng.uniform(-12, 12), y + rng.uniform(-12, 12)) for x, y in centres]
    rng = random.Random(seed ^ 0xB017A1)
    cx, cy = 256 + rng.uniform(-18, 18), 256 + rng.uniform(-18, 18)
    return (cx, cy, cx + rng.uniform(-22, 22), cy + rng.uniform(-22, 22))


def height_for(kind: str, x: int, y: int, noise: Noise, shape) -> float:
    if kind == "atoll":
        return atoll_height(x, y, noise, shape)
    if kind == "archipelago":
        return archipelago_height(x, y, noise, shape)
    return mountain_height(x, y, noise, shape)


def landing_for(kind: str, shape) -> tuple[int, int]:
    if kind == "atoll":
        cx, cy, _ = shape
        return round(cx - 120), round(cy - 8)
    if kind == "archipelago":
        cx, cy = shape[0]
        return round(cx), round(cy)
    cx, cy, _, _ = shape
    return round(cx - 80), round(cy)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_preview(path: Path, rows: list[list[float]]) -> None:
    pixels = bytearray()
    for y in range(SIZE - 1, -1, -1):
        pixels.append(0)
        for x in range(SIZE):
            h = rows[y][x]
            if h < SEA_LEVEL - 0.5:
                d = min(1.0, max(0.0, (h + 38) / (SEA_LEVEL + 38)))
                rgb = (int(11 + 29 * d), int(45 + 65 * d), int(81 + 67 * d))
            elif h < SEA_LEVEL + 8:
                rgb = (194, 177, 122)
            else:
                d = min(1.0, max(0.0, (h - SEA_LEVEL) / 120))
                rgb = (int(55 + 68 * d), int(104 + 68 * d), int(52 + 35 * d))
            pixels.extend(rgb)
    image = b"\x89PNG\r\n\x1a\n"
    image += png_chunk(b"IHDR", struct.pack(">2I5B", SIZE, SIZE, 8, 2, 0, 0, 0))
    image += png_chunk(b"IDAT", zlib.compress(bytes(pixels), 9))
    image += png_chunk(b"IEND", b"")
    path.write_bytes(image)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", choices=("random", "atoll", "archipelago", "mountain"), default="random")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=lambda x: int(x, 0), help="Optional integer seed; random when omitted")
    args = parser.parse_args()

    seed = args.seed if args.seed is not None else secrets.randbits(64)
    rng = random.Random(seed)
    template = args.template if args.template != "random" else rng.choice(("atoll", "archipelago", "mountain"))
    preset = json.loads((PRESETS / f"{template}.json").read_text(encoding="utf-8"))
    if preset["size"] != SIZE:
        raise SystemExit("All WOW terrain templates must be 512 × 512.")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    stem = f"wow-{template}-{seed:016x}"
    r32_path = args.output_dir / f"{stem}.r32"
    png_path = args.output_dir / f"{stem}.png"
    metadata_path = args.output_dir / f"{stem}.json"
    if any(p.exists() for p in (r32_path, png_path, metadata_path)):
        raise SystemExit("Output already exists; refusing to overwrite generated terrain.")

    noise = Noise(seed)
    shape = shape_parameters(template, seed)
    rows: list[list[float]] = []
    minimum, maximum = float("inf"), float("-inf")
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            value = max(-45.0, min(180.0, height_for(template, x, y, noise, shape)))
            row.append(value)
            minimum, maximum = min(minimum, value), max(maximum, value)
        rows.append(row)

    with r32_path.open("xb") as f:
        for row in rows:
            f.write(struct.pack("<" + "f" * SIZE, *row))
    write_preview(png_path, rows)
    lx, ly = landing_for(template, shape)
    meta = {
        "template": template,
        "seed": seed,
        "size": [SIZE, SIZE],
        "sea_level_m": SEA_LEVEL,
        "min_height_m": round(minimum, 3),
        "max_height_m": round(maximum, 3),
        "landing_m": [lx, ly, round(rows[ly][lx] + 2.0, 2)],
        "heightmap": r32_path.name,
        "preview": png_path.name,
        "format": "OpenSimulator R32, little-endian float metres, south-to-north rows",
    }
    metadata_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    if r32_path.stat().st_size != SIZE * SIZE * 4:
        raise SystemExit("Generated R32 has an invalid size.")
    print(json.dumps({"metadata": str(metadata_path), **meta}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
