#!/usr/bin/env python3
"""Predecode curated original OpenSpades impact/fire sounds to native-style PCM.

Inputs are the pinned original source/r33 package, never the imported Vorbis
derivatives. OpenSpades OpusAudioStream reads 48 kHz floats and ALDevice.cpp
floors float * 32768 before an int16 cast. Preserve that quantization explicitly;
FFmpeg's direct pcm_s16le conversion has different rounding. These derivatives
remain bundled with the game and its existing original license/credit notices.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import wave

from import_openspades import read_resources, sha256, write_if_changed

ROOT = Path(__file__).resolve().parents[1]
FORMAT = "blockfield-impact-pcm-v1"
UPSTREAM_COMMIT = "dcf449c845d509bbde9d79239b32d201c1389961"
PACK_SHA256 = "0927dc323a0b3aba0ee8d1d68d6b544b00fe654740fead6d1faad37aac77a2ad"
MAX_TOTAL_PCM_BYTES = 8 * 1024 * 1024
MAX_FILE_PCM_BYTES = 2 * 1024 * 1024
IMPORT_PARAMS = {
    "force/8_bit": "false",
    "force/mono": "false",
    "force/max_rate": "false",
    "force/max_rate_hz": "48000",
    "edit/trim": "false",
    "edit/normalize": "false",
    "edit/loop_mode": "1",
    "edit/loop_begin": "0",
    "edit/loop_end": "-1",
    "compress/mode": "0",
}


def curated_paths() -> list[str]:
    paths = ["Misc/BlockDestroy", "Misc/BlockFall", "Weapons/Impacts/Block"]
    paths += [f"Weapons/Impacts/{kind}{number}"
              for kind in ("Ricochet", "Water") for number in range(1, 5)]
    paths += [f"Weapons/SMG/{kind}{number}"
              for kind in ("V2Local", "V2Third", "V2AmbienceSmall", "V2AmbienceLarge")
              for number in range(1, 5)]
    for weapon in ("SMG", "Rifle"):
        paths += [f"Weapons/{weapon}/{name}"
                  for name in ("FireFar", "FireStereo", "ShellDrop1", "ShellDrop2", "ShellWater")]
    paths += [f"Weapons/Rifle/{name}" for name in
              ("FireLocal", "Fire1", "Fire2", "Fire3", "V2AmbienceSmall", "V2AmbienceLarge")]
    paths += [f"Weapons/Shotgun/{name}" for name in
              ("FireLocal", "Fire", "FireFar", "FireStereo", "V2AmbienceSmall", "V2AmbienceLarge")]
    # Shotgun shell contacts use the original Rifle resources; do not invent
    # nonexistent Shotgun/Shell*.opus originals or duplicate their PCM.
    return sorted(f"Sounds/{path}.opus" for path in paths)


def opus_metadata(content: bytes) -> dict:
    """Read authoritative OpusHead and final EOS granule, without transcoding."""
    position = 0
    first_packet = bytearray()
    first_done = False
    serial = None
    last_granule = None
    last_flags = 0
    while position < len(content):
        if content[position:position + 5] != b"OggS\x00" or position + 27 > len(content):
            raise ValueError("Invalid/truncated Ogg page")
        flags = content[position + 5]
        granule, page_serial = struct.unpack_from("<QI", content, position + 6)
        if serial is None:
            serial = page_serial
        elif page_serial != serial:
            raise ValueError("Chained/multiplexed Opus is outside the curated source contract")
        count = content[position + 26]
        segments = content[position + 27:position + 27 + count]
        payload = position + 27 + count
        end = payload + sum(segments)
        if len(segments) != count or end > len(content):
            raise ValueError("Truncated Ogg lacing/payload")
        if not first_done:
            for size in segments:
                first_packet.extend(content[payload:payload + size])
                payload += size
                if size < 255:
                    first_done = True
                    break
        last_granule, last_flags = granule, flags
        position = end
    if not first_done or first_packet[:8] != b"OpusHead" or len(first_packet) < 19:
        raise ValueError("Missing OpusHead")
    if not last_flags & 4 or last_granule == 0xffffffffffffffff:
        raise ValueError("Missing final Opus EOS granule")
    channels = first_packet[9]
    pre_skip, input_rate, gain = struct.unpack_from("<HIh", first_packet, 10)
    if channels not in (1, 2) or first_packet[18] != 0:
        raise ValueError("Curated originals must use mono/stereo Opus mapping family 0")
    frames = last_granule - pre_skip
    if frames <= 0:
        raise ValueError("Invalid Opus frame count")
    return {"channels": channels, "mix_rate": 48000, "frames": frames,
            "pre_skip": pre_skip, "input_rate": input_rate, "header_gain_q8_db": gain}


def native_pcm(float_bytes: bytes) -> tuple[bytes, dict]:
    if len(float_bytes) % 4:
        raise ValueError("Float decoder returned a partial sample")
    output = bytearray(len(float_bytes) // 2)
    overflow = 0
    peak = 0.0
    for sample, (value,) in enumerate(struct.iter_unpack("<f", float_bytes)):
        if not math.isfinite(value):
            raise ValueError(f"Non-finite decoded sample at {sample}")
        peak = max(peak, abs(value))
        integer = math.floor(value * 32768.0)
        if not -32768 <= integer <= 32767:
            overflow += 1
        # Make the pinned native int16 cast's two's-complement result explicit.
        # Report every overflow rather than silently changing it to saturation.
        struct.pack_into("<h", output, sample * 2, (integer + 32768) % 65536 - 32768)
    return bytes(output), {"sample_count": len(float_bytes) // 4,
                           "nonfinite_samples": 0, "overflow_samples": overflow,
                           "peak_abs_float": peak, "decoded_float_sha256": sha256(float_bytes)}


def decode_original(content: bytes, metadata: dict, ffmpeg: Path) -> tuple[bytes, dict]:
    command = [str(ffmpeg), "-hide_banner", "-loglevel", "error",
               "-c:a", "libopus", "-i", "pipe:0", "-map", "0:a:0",
               "-vn", "-sn", "-dn", "-c:a", "pcm_f32le", "-f", "f32le", "pipe:1"]
    result = subprocess.run(command, input=content, capture_output=True, timeout=30, check=False)
    if result.returncode:
        raise ValueError("Original libopus decode failed: " + result.stderr.decode("utf-8", "replace").strip())
    expected = metadata["frames"] * metadata["channels"] * 4
    if len(result.stdout) != expected:
        raise ValueError(f"Opus EOS length mismatch: {len(result.stdout)} float bytes != {expected}")
    return native_pcm(result.stdout)


def make_wav(pcm: bytes, metadata: dict) -> bytes:
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(metadata["channels"])
        wav.setsampwidth(2)
        wav.setframerate(metadata["mix_rate"])
        wav.writeframes(pcm)
    return output.getvalue()


def ensure_import(output: Path, relative: str) -> None:
    source_file = "res://assets/openspades/" + relative
    destination = "res://.godot/imported/" + Path(relative).name + "-" + hashlib.md5(source_file.encode()).hexdigest() + ".sample"
    text = ('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n'
            f'path="{destination}"\n\n[deps]\n\nsource_file="{source_file}"\n'
            f'dest_files=["{destination}"]\n\n[params]\n\n' +
            "\n".join(f"{key}={value}" for key, value in IMPORT_PARAMS.items()) + "\n")
    path = (output / relative).with_suffix(".wav.import")
    if path.exists():
        # Preserve UIDs and remap fields emitted by a subsequent Godot import.
        verify_import(path)
    else:
        write_if_changed(path, text.encode("utf-8"))


def verify_import(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    params = text.split("[params]", 1)[-1]
    values = dict(line.strip().split("=", 1) for line in params.splitlines()
                  if "=" in line and not line.lstrip().startswith(";"))
    for key, expected in IMPORT_PARAMS.items():
        if values.get(key) != expected:
            raise ValueError(f"{path}: {key} must equal {expected}")


def original_sources(source: Path, pack: Path, output: Path) -> dict:
    if sha256(pack.read_bytes()) != PACK_SHA256:
        raise ValueError("Expected the pinned OpenSpades r33 package SHA256")
    resources, _licenses = read_resources(source, pack)
    original_manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    records = {row["virtual_path"]: row for row in original_manifest["assets"]}
    for virtual in curated_paths():
        resource = resources.get(virtual)
        record = records.get(virtual)
        if resource is None or record is None or resource.placeholder:
            raise ValueError(f"Missing original curated resource: {virtual}")
        if sha256(resource.content) != record["source_sha256"] or resource.source != record["source"]:
            raise ValueError(f"Original source differs from bundled provenance: {virtual}")
    return resources


def generate(source: Path, pack: Path, output: Path, ffmpeg: Path) -> dict:
    resources = original_sources(source, pack, output)
    version = subprocess.run([str(ffmpeg), "-version"], capture_output=True, text=True, timeout=10, check=True).stdout.splitlines()[0]
    manifest = {"format": FORMAT, "upstream": "https://github.com/yvt/openspades",
                "upstream_version": "v0.1.3", "upstream_commit": UPSTREAM_COMMIT,
                "dev_pack": "r33", "pack_sha256": PACK_SHA256,
                "decoder": {"program": "FFmpeg", "version": version, "binary_sha256": sha256(ffmpeg.read_bytes()),
                            "input_decoder": "libopus", "output": "interleaved pcm_f32le",
                            "quantization": "floor(float32 * 32768), explicit two's-complement int16 wrap; no dithering",
                            "source_reference": "Sources/Core/OpusAudioStream.cpp; Sources/Audio/ALDevice.cpp:59-75,96-143"},
                "licenses": "Existing licenses/ original r33/OpenSpades notices; bundled game derivatives only",
                "files": {}, "total_pcm_bytes": 0, "total_wav_bytes": 0,
                "total_nonfinite_samples": 0, "total_overflow_samples": 0}
    for virtual in curated_paths():
        resource = resources[virtual]
        metadata = opus_metadata(resource.content)
        pcm, measurements = decode_original(resource.content, metadata, ffmpeg)
        if len(pcm) > MAX_FILE_PCM_BYTES:
            raise ValueError(f"Individual PCM exceeds 2 MiB: {virtual}")
        manifest["total_pcm_bytes"] += len(pcm)
        if manifest["total_pcm_bytes"] > MAX_TOTAL_PCM_BYTES:
            raise ValueError("Curated PCM exceeds the approved 8 MiB cap")
        wav = make_wav(pcm, metadata)
        relative = "impact_pcm/" + virtual.removeprefix("Sounds/").removesuffix(".opus") + ".wav"
        write_if_changed(output / relative, wav)
        ensure_import(output, relative)
        manifest["files"][virtual] = {"output": relative, **metadata, **measurements,
                                       "source": resource.source, "source_bytes": len(resource.content),
                                       "source_sha256": sha256(resource.content), "pcm_bytes": len(pcm),
                                       "pcm_sha256": sha256(pcm), "output_bytes": len(wav), "output_sha256": sha256(wav)}
        manifest["total_wav_bytes"] += len(wav)
        manifest["total_overflow_samples"] += measurements["overflow_samples"]
    write_if_changed(output / "impact_pcm_manifest.json", (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8"))
    return manifest


def verify(source: Path, pack: Path, output: Path) -> dict:
    resources = original_sources(source, pack, output)
    manifest = json.loads((output / "impact_pcm_manifest.json").read_text(encoding="utf-8"))
    if manifest["format"] != FORMAT or manifest["pack_sha256"] != PACK_SHA256 or sorted(manifest["files"]) != curated_paths():
        raise ValueError("PCM manifest format/source/curation mismatch")
    total_pcm = total_wav = overflow = 0
    for virtual, row in manifest["files"].items():
        metadata = opus_metadata(resources[virtual].content)
        if row["source_sha256"] != sha256(resources[virtual].content):
            raise ValueError(f"PCM original hash mismatch: {virtual}")
        for key, expected in metadata.items():
            if row[key] != expected:
                raise ValueError(f"PCM {key} differs from Opus header/EOS: {virtual}")
        relative = "impact_pcm/" + virtual.removeprefix("Sounds/").removesuffix(".opus") + ".wav"
        if row["output"] != relative:
            raise ValueError(f"Unexpected PCM derivative path: {virtual}")
        wav_bytes = (output / relative).read_bytes()
        if sha256(wav_bytes) != row["output_sha256"] or len(wav_bytes) != row["output_bytes"]:
            raise ValueError(f"WAV output hash/length mismatch: {virtual}")
        with wave.open(io.BytesIO(wav_bytes), "rb") as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes(), wav.getcomptype()) != (metadata["channels"], 2, 48000, metadata["frames"], "NONE"):
                raise ValueError(f"WAV sample format mismatch: {virtual}")
            pcm = wav.readframes(metadata["frames"])
        if len(pcm) != metadata["frames"] * metadata["channels"] * 2 or len(pcm) != row["pcm_bytes"] or sha256(pcm) != row["pcm_sha256"]:
            raise ValueError(f"WAV PCM data hash/length mismatch: {virtual}")
        if row["nonfinite_samples"] != 0 or row["sample_count"] != metadata["frames"] * metadata["channels"]:
            raise ValueError(f"Invalid decode measurements: {virtual}")
        if len(pcm) > MAX_FILE_PCM_BYTES:
            raise ValueError(f"PCM file cap exceeded: {virtual}")
        verify_import((output / relative).with_suffix(".wav.import"))
        total_pcm += len(pcm)
        total_wav += len(wav_bytes)
        overflow += row["overflow_samples"]
    if total_pcm > MAX_TOTAL_PCM_BYTES or total_pcm != manifest["total_pcm_bytes"] or total_wav != manifest["total_wav_bytes"] or overflow != manifest["total_overflow_samples"] or manifest["total_nonfinite_samples"] != 0:
        raise ValueError("PCM aggregate measurements/cap mismatch")
    return {"format": FORMAT, "files": len(manifest["files"]), "total_pcm_bytes": total_pcm,
            "total_wav_bytes": total_wav, "nonfinite_samples": 0, "overflow_samples": overflow,
            "largest_pcm_bytes": max(row["pcm_bytes"] for row in manifest["files"].values()), "verified": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / ".cache/openspades")
    parser.add_argument("--pack", type=Path, default=ROOT / ".cache/assets/OpenSpadesDevPackage-r33.zip")
    parser.add_argument("--output", type=Path, default=ROOT / "game/assets/openspades")
    parser.add_argument("--ffmpeg", type=Path, default=shutil.which("ffmpeg"))
    parser.add_argument("--verify", action="store_true", help="Verify original/PCM/WAV hashes and lossless Godot import settings")
    args = parser.parse_args()
    try:
        if not args.verify:
            if args.ffmpeg is None or not args.ffmpeg.is_file():
                raise ValueError("Supply --ffmpeg with a trusted binary supporting libopus")
            generate(args.source, args.pack, args.output, args.ffmpeg.resolve())
        print(json.dumps(verify(args.source, args.pack, args.output), indent=2))
        return 0
    except (ValueError, OSError, KeyError, subprocess.SubprocessError, wave.Error) as error:
        print(f"Impact PCM conversion failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
