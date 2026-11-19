from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path


SIZE = 64
SCALE = 3
BIG = SIZE * SCALE
pixels = [[(0, 0, 0, 0) for _ in range(BIG)] for _ in range(BIG)]
cx = cy = (BIG - 1) / 2
radius = 29.0 * SCALE


def inside_polygon(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if (yi > y) != (yj > y):
            crossing = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < crossing:
                inside = not inside
        j = i
    return inside


land_shapes = [
    [(20, 19), (23, 16), (28, 17), (29, 20), (26, 22), (25, 26), (22, 24)],
    [(36, 18), (42, 19), (46, 23), (44, 27), (40, 26), (38, 29), (35, 26)],
    [(31, 30), (37, 29), (40, 33), (37, 39), (33, 40), (30, 36)],
    [(18, 36), (22, 34), (25, 38), (23, 43), (19, 42)],
]

for py in range(BIG):
    y = (py + 0.5) / SCALE - 32
    for px in range(BIG):
        x = (px + 0.5) / SCALE - 32
        distance = math.hypot(x, y)
        if distance > 30.0:
            continue

        if distance >= 27.7:
            color = (180, 226, 239, 255)
        else:
            color = (18, 47, 68, 255)

            land = any(inside_polygon(x + 32, y + 32, shape) for shape in land_shapes)
            if land:
                color = (92, 190, 133, 255)
            else:
                longitude = (
                    abs((x / 13.5) ** 2 + (y / 28.0) ** 2 - 1.0) < 0.045
                    or abs((x / 23.0) ** 2 + (y / 28.0) ** 2 - 1.0) < 0.035
                )
                latitude = any(
                    abs(abs(y) - level) < 0.8
                    and abs(x) < math.sqrt(max(0.0, 27.0**2 - level**2))
                    for level in (10.0, 19.0)
                )
                if longitude or latitude:
                    color = (92, 154, 181, 255)
        pixels[py][px] = color


small: list[list[tuple[int, int, int, int]]] = []
for y in range(SIZE):
    row = []
    for x in range(SIZE):
        samples = [
            pixels[y * SCALE + sy][x * SCALE + sx]
            for sy in range(SCALE)
            for sx in range(SCALE)
        ]
        row.append(
            tuple(sum(sample[channel] for sample in samples) // len(samples) for channel in range(4))
        )
    small.append(row)

raw = b"".join(
    b"\x00" + bytes(channel for pixel in small[y] for channel in pixel)
    for y in range(SIZE)
)


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


png = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">2I5B", SIZE, SIZE, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(raw, level=9))
    + png_chunk(b"IEND", b"")
)
ico_header = struct.pack("<HHH", 0, 1, 1)
ico_entry = struct.pack("<BBBBHHII", SIZE, SIZE, 0, 0, 1, 32, len(png), 22)

destination = Path(__file__).with_name("world-dock.ico")
destination.write_bytes(ico_header + ico_entry + png)
print(f"Wrote {destination} ({len(png)} byte PNG icon payload)")
