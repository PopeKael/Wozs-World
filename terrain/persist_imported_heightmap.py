#!/usr/bin/env python3
"""Promote OpenSimulator's validated baked terrain to its startup heightfield.

OpenSim 0.9.3's console `terrain load` installs the heightmap and stores it as
the region's baked/revert map. In this installation, the primary `terrain` row
still supplies startup height and remains unchanged by that command. This
explicit offline helper copies the server-serialized baked row to the matching
primary terrain row. It never runs during normal server startup.
"""

from __future__ import annotations

import configparser
import argparse
import gzip
import sqlite3
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "server" / "OpenSimulator-0.9.3.0" / "bin" / "OpenSim.db"
REGIONS_PATH = ROOT / "server" / "OpenSimulator-0.9.3.0" / "bin" / "Regions" / "Regions.ini"


def get_region_uuid() -> str:
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    config.read(REGIONS_PATH, encoding="utf-8-sig")
    if len(config.sections()) != 1:
        raise RuntimeError(f"Expected one region in {REGIONS_PATH}; found {config.sections()}")
    region_uuid = config[config.sections()[0]].get("RegionUUID", "").strip()
    if not region_uuid:
        raise RuntimeError("RegionUUID is missing from the active region config.")
    return region_uuid


def main(r32_path: Path) -> None:
    generated = r32_path.read_bytes()
    expected_length = 512 * 512 * 4
    if len(generated) != expected_length:
        raise RuntimeError(f"Expected a 1,048,576-byte R32 file, got {len(generated):,} bytes.")
    if not DB_PATH.is_file():
        raise RuntimeError(f"OpenSimulator database not found: {DB_PATH}")

    region_uuid = get_region_uuid()
    connection = sqlite3.connect(DB_PATH, timeout=10, isolation_level=None)
    try:
        connection.execute("PRAGMA busy_timeout = 10000")
        connection.execute("BEGIN IMMEDIATE")

        baked_row = connection.execute(
            "SELECT Revision, Heightfield FROM bakedterrain WHERE RegionUUID = ?",
            (region_uuid,),
        ).fetchone()
        if baked_row is None:
            raise RuntimeError("OpenSimulator has no bakedterrain row for the configured region.")
        revision, blob = baked_row
        unpacked = gzip.decompress(blob)
        width, height = struct.unpack("<II", unpacked[:8])
        if (width, height) != (512, 512) or len(unpacked) != expected_length + 8:
            raise RuntimeError(
                f"OpenSimulator's baked row is {width} x {height} with {len(unpacked):,} bytes; expected 512 x 512."
            )

        stored = struct.unpack("<%df" % (512 * 512), unpacked[8:])
        source = struct.unpack("<%df" % (512 * 512), generated)
        maximum_error = max(abs(a - b) for a, b in zip(stored, source))
        if maximum_error > 0.001:
            raise RuntimeError(
                f"The OpenSimulator baked row does not match the generated R32 (max error {maximum_error:.6f} m)."
            )

        active_count = connection.execute(
            "SELECT COUNT(*) FROM terrain WHERE RegionUUID = ?", (region_uuid,)
        ).fetchone()[0]
        if active_count != 1:
            raise RuntimeError(f"Expected one active terrain row for the region; found {active_count}.")

        connection.execute(
            "UPDATE terrain SET Revision = ?, Heightfield = ? WHERE RegionUUID = ?",
            (revision, blob, region_uuid),
        )
        check = connection.execute(
            "SELECT Revision, Heightfield FROM terrain WHERE RegionUUID = ?", (region_uuid,)
        ).fetchone()
        if check != (revision, blob):
            raise RuntimeError("Primary terrain row did not match the validated OpenSimulator baked row.")
        connection.execute("COMMIT")
        print(
            f"Promoted OpenSimulator's validated 512 x 512 baked terrain to the startup terrain row "
            f"(revision {revision}; max R32 error {maximum_error:.6f} m)."
        )
    except Exception:
        if connection.in_transaction:
            connection.execute("ROLLBACK")
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--r32", required=True, type=Path, help="Generated 512 x 512 R32 heightmap to verify")
    arguments = parser.parse_args()
    main(arguments.r32.resolve())
