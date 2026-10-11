"""Fetch the pinned portable Blender used for local map conversion, not installation."""
from __future__ import annotations

import hashlib
from pathlib import Path
import urllib.request
import zipfile

VERSION = "4.5.14"
ARCHIVE = f"blender-{VERSION}-windows-x64.zip"
SHA256 = "b9533d2397ac1984db4466fb23a7a4649391cca93f6e84209f9bcc60d071c8b9"
ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools" / "blender"


def main() -> Path:
    executable = TOOLS / ARCHIVE.removesuffix(".zip") / "blender.exe"
    if executable.exists():
        print(executable, flush=True)
        return executable
    TOOLS.mkdir(parents=True, exist_ok=True)
    archive = TOOLS / ARCHIVE
    archive_valid = False
    if archive.exists():
        with archive.open("rb") as data:
            archive_valid = hashlib.file_digest(data, "sha256").hexdigest() == SHA256
    if not archive_valid:
        url = f"https://download.blender.org/release/Blender4.5/{ARCHIVE}"
        request = urllib.request.Request(url, headers={"User-Agent": "BlockfieldMapImport/1.0"})
        temporary = archive.with_suffix(".zip.tmp")
        with urllib.request.urlopen(request, timeout=60) as source, temporary.open("wb") as target:
            total = 0
            report = 0
            while chunk := source.read(2 * 1024 * 1024):
                target.write(chunk)
                total += len(chunk)
                if total // (32 * 1024 * 1024) > report:
                    report = total // (32 * 1024 * 1024)
                    print(f"Blender download: {total / 1048576:.0f} MiB", flush=True)
        with temporary.open("rb") as data:
            actual = hashlib.file_digest(data, "sha256").hexdigest()
        if actual != SHA256:
            raise ValueError(f"Blender archive SHA256 mismatch: {actual}")
        temporary.replace(archive)
    with zipfile.ZipFile(archive) as bundle:
        base = TOOLS.resolve()
        for item in bundle.infolist():
            if not (base / item.filename).resolve().is_relative_to(base):
                raise ValueError("Unsafe archive path")
        print("Extracting hash-verified portable Blender", flush=True)
        bundle.extractall(base)
    print(executable, flush=True)
    return executable


if __name__ == "__main__":
    main()
