"""Verify the machine type of every executable component in a Windows app image."""
import argparse
import struct
from pathlib import Path


def machine_type(path: Path) -> int:
    with path.open("rb") as binary:
        if binary.read(2) != b"MZ":
            raise ValueError(f"{path.name}: invalid DOS header")
        binary.seek(0x3C)
        pe_offset, = struct.unpack("<I", binary.read(4))
        binary.seek(pe_offset)
        if binary.read(4) != b"PE\0\0":
            raise ValueError(f"{path.name}: invalid PE header")
        machine, = struct.unpack("<H", binary.read(2))
        return machine


def verify(image: Path) -> None:
    required = {
        "OrangeCellSettings.exe", "OrangeCellBroker.exe", "OrangeCellServer.exe",
        "OrangeCellDeployer.exe", "OrangeCellDataDeploy.exe", "rime.dll",
        "OrangeCellTSFx64.dll", "OrangeCellTSFx86.dll", "OrangeCellTSFarm64.dll",
    }
    # Everything else is x64 (services run emulated on Windows on ARM).
    special = {"OrangeCellTSFx86.dll": 0x014C, "OrangeCellTSFarm64.dll": 0xAA64}
    files = sorted(p for p in image.iterdir() if p.is_file() and p.suffix.lower() in {".exe", ".dll"})
    missing = required - {p.name for p in files}
    if missing:
        raise ValueError(f"Missing image components: {sorted(missing)}")
    for path in files:
        expected = special.get(path.name, 0x8664)
        actual = machine_type(path)
        if actual != expected:
            raise ValueError(f"{path.name}: PE machine {actual:04x}, expected {expected:04x}")
        print(f"{path.name}: PE machine {actual:04x}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    verify(args.image)
