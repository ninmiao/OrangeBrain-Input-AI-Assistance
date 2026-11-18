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


def verify(image: Path, arch: str) -> None:
    native_type = {"x64": 0x8664, "arm64": 0xAA64}[arch]
    required = {
        "ZephyrSettings.exe", "ZephyrBroker.exe", "ZephyrServer.exe",
        "ZephyrDeployer.exe", "ZephyrDataDeploy.exe", "rime.dll",
        f"ZephyrTSF{arch}.dll",
    }
    compatibility_dll = "ZephyrTSFx86.dll"
    if arch == "x64":
        required.add(compatibility_dll)
    files = sorted(p for p in image.iterdir() if p.is_file() and p.suffix.lower() in {".exe", ".dll"})
    missing = required - {p.name for p in files}
    if missing:
        raise ValueError(f"Missing image components: {sorted(missing)}")
    for path in files:
        expected = 0x014C if arch == "x64" and path.name == compatibility_dll else native_type
        actual = machine_type(path)
        if actual != expected:
            raise ValueError(f"{path.name}: PE machine {actual:04x}, expected {expected:04x}")
        print(f"{path.name}: PE machine {actual:04x}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("architecture", choices=("x64", "arm64"))
    args = parser.parse_args()
    verify(args.image, args.architecture)
