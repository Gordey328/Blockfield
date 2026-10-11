"""Build a pinned, single-thread Godot Web template using an installed toolchain.

This does not download tools or replace Godot's globally installed templates.
Use the resulting ZIP as an explicit custom release template when exporting.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2"
REVISION = "ed1daf0bf001b61586d9930840f2f1394092c079"
TEMPLATE_NAME = "godot.web.template_release.wasm32.nothreads.zip"
TEMPLATE_MEMBERS = {
    "godot.js", "godot.wasm", "godot.html", "godot.audio.worklet.js",
    "godot.audio.position.worklet.js", "godot.service.worker.js", "godot.offline.html",
}
BASE_OPTIONS = {
    "platform": "web", "target": "template_release", "arch": "wasm32",
    "threads": "no", "dlink_enabled": "no", "production": "yes",
    "debug_symbols": "no", "dev_build": "no", "optimize": "size", "lto": "auto",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while part := source.read(1024 * 1024):
            digest.update(part)
    return digest.hexdigest()


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def query(command: list[str], *, cwd: Path | None = None,
          env: dict[str, str] | None = None) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", timeout=60)
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()[-2000:]
        raise RuntimeError(f"Prerequisite failed: {command[0]}\n{detail}")
    return result.stdout.strip()


def source_identity(source: Path, expected_revision: str | None) -> dict:
    required = ("SConstruct", "version.py", "platform/web/detect.py",
                "platform/web/SCsub", "platform/web/emscripten_helpers.py")
    for name in required:
        if not (source / name).is_file():
            raise RuntimeError(f"Godot source is missing {name}: {source}")
    if (source / "custom.py").exists():
        raise RuntimeError("Remove unintended source/custom.py before building; use --profile")
    values = {}
    for node in ast.parse((source / "version.py").read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            try:
                values[node.targets[0].id] = ast.literal_eval(node.value)
            except (ValueError, TypeError):
                pass
    version = ".".join(str(values.get(key, "")) for key in ("major", "minor", "patch"))
    if version != VERSION or values.get("status") != "stable":
        raise RuntimeError(f"Expected Godot {VERSION}.stable source; found {version}.{values.get('status')}")
    # Never let a source archive inherit this project's enclosing Git identity.
    if not (source / ".git").exists():
        raise RuntimeError("--source must be an actual pinned Godot Git checkout, not an unverified archive")
    revision = query(["git", "rev-parse", "HEAD"], cwd=source)
    if expected_revision and not revision.startswith(expected_revision):
        raise RuntimeError(f"Godot revision mismatch: expected {expected_revision}, found {revision}")
    dirty = query(["git", "status", "--porcelain", "--untracked-files=no"], cwd=source)
    if dirty:
        raise RuntimeError("Godot source has tracked changes; use a clean pinned checkout")
    return {
        "path": str(source), "version": version + ".stable", "revision": revision,
        "tracked_changes": False,
        "file_sha256": {name: sha256(source / name) for name in required},
    }


def profile_identity(profile: Path) -> dict:
    if not profile.is_file():
        raise RuntimeError(f"Missing build profile: {profile}")
    options = {}
    # SCons executes profiles as Python. Keep this reproducible profile declarative.
    for node in ast.parse(profile.read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            continue
        if not isinstance(node, ast.Assign) or len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name):
            raise RuntimeError("Build profile must contain only literal variable assignments and a docstring")
        try:
            value = ast.literal_eval(node.value)
        except (ValueError, TypeError) as failure:
            raise RuntimeError("Build profile values must be literal") from failure
        options[node.targets[0].id] = value
    return {"path": str(profile), "sha256": sha256(profile), "options": options}


def toolchain_environment(emsdk: Path, scons_dir: Path | None, node: Path | None) -> dict[str, str]:
    config = emsdk / ".emscripten"
    emscripten = emsdk / "upstream" / "emscripten"
    if not config.is_file() or not (emscripten / "emcc.py").is_file():
        raise RuntimeError(f"Install and activate the pinned Emscripten SDK first: {emsdk}")
    node_name = "node.exe" if sys.platform == "win32" else "node"
    if node is None:
        # emsdk installs node.exe directly in its version folder on Windows;
        # Unix packages commonly keep the executable in a bin subdirectory.
        candidates = sorted({*(emsdk / "node").glob("*/" + node_name),
                             *(emsdk / "node").glob("*/bin/" + node_name)})
        if len(candidates) != 1:
            raise RuntimeError("Expected exactly one installed emsdk Node; select its executable with --node")
        node = candidates[0]
    if not node.is_file():
        raise RuntimeError(f"Missing Node executable: {node}")
    env = os.environ.copy()
    env["EMSDK"] = str(emsdk)
    env["EM_CONFIG"] = str(config)
    env["EMSDK_NODE"] = str(node.resolve())
    env["PATH"] = os.pathsep.join((str(emscripten), str(emsdk), str(node.parent), env.get("PATH", "")))
    if scons_dir:
        if not (scons_dir / "SCons" / "__init__.py").is_file():
            raise RuntimeError(f"--scons-dir must contain an installed SCons package: {scons_dir}")
        env["PYTHONPATH"] = os.pathsep.join(part for part in (str(scons_dir), env.get("PYTHONPATH", "")) if part)
    return env


def toolchain_identity(python: Path, emsdk: Path, env: dict[str, str],
                       emscripten_version: str, scons_version: str) -> dict:
    python_version = query([str(python), "-c", "import platform; print(platform.python_version())"], env=env)
    found_scons = query([str(python), "-c", "import SCons; print(SCons.__version__)"], env=env)
    if found_scons != scons_version:
        raise RuntimeError(f"SCons mismatch: expected {scons_version}, found {found_scons}")
    emcc = emsdk / "upstream" / "emscripten" / "emcc.py"
    emcc_output = query([str(python), str(emcc), "--version"], env=env)
    match = re.search(r"\b(\d+\.\d+\.\d+)\b", emcc_output)
    found_emscripten = match.group(1) if match else None
    if found_emscripten != emscripten_version:
        raise RuntimeError(f"Emscripten mismatch: expected {emscripten_version}, found {found_emscripten}")
    if tuple(int(part) for part in emscripten_version.split(".")) < (4, 0, 9):
        raise RuntimeError("This build preserves stock thin LTO and requires Emscripten >= 4.0.9")
    linker = emsdk / "upstream" / "bin" / ("wasm-ld.exe" if sys.platform == "win32" else "wasm-ld")
    linker_help = query([str(linker), "--help"], env=env)
    if "--thinlto-jobs" not in linker_help:
        raise RuntimeError("Pinned wasm-ld must support --thinlto-jobs for the memory-bounded build")
    return {
        "python": str(python), "python_version": python_version,
        "scons_version": found_scons,
        "scons_package": query([str(python), "-c", "import SCons; print(SCons.__file__)"], env=env),
        "emsdk": str(emsdk),
        "emscripten_version": found_emscripten, "emcc_version_text": emcc_output,
        "emscripten_git_revision": query(["git", "rev-parse", "HEAD"], cwd=emcc.parent)
            if (emcc.parent / ".git").exists() else None,
        "emsdk_git_revision": query(["git", "rev-parse", "HEAD"], cwd=emsdk)
            if (emsdk / ".git").exists() else None,
        "config_sha256": sha256(emsdk / ".emscripten"), "emcc_sha256": sha256(emcc),
        "linker": str(linker), "linker_version": query([str(linker), "--version"], env=env),
        "node": env["EMSDK_NODE"], "node_version": query([env["EMSDK_NODE"], "--version"], env=env),
    }


def write_metadata(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def compile_template(command: list[str], source: Path, env: dict[str, str], log: Path) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    last_report = started
    print("Building: " + subprocess.list2cmdline(command), flush=True)
    with log.open("w", encoding="utf-8") as output:
        output.write("Working directory: " + str(source) + "\n")
        output.write("Command: " + subprocess.list2cmdline(command) + "\n")
        output.flush()
        process = subprocess.Popen(command, cwd=source, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        try:
            assert process.stdout is not None
            for line in process.stdout:
                output.write(line)
                output.flush()
                now = time.monotonic()
                if now - last_report >= 30:
                    print(f"Build {int(now - started)}s: {line.strip()[-160:]}", flush=True)
                    last_report = now
            return process.wait()
        except BaseException:
            stop_process(process)
            raise


def template_identity(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(TEMPLATE_MEMBERS) or set(names) != TEMPLATE_MEMBERS:
            raise RuntimeError(f"Unexpected custom template members: {names}")
        if failure := archive.testzip():
            raise RuntimeError(f"Corrupt template member: {failure}")
        wasm = archive.read("godot.wasm")
        if not wasm.startswith(b"\x00asm\x01\x00\x00\x00"):
            raise RuntimeError("Template does not contain a valid WebAssembly v1 module")
        members = {}
        for name in sorted(names):
            payload = wasm if name == "godot.wasm" else archive.read(name)
            members[name] = {
                "bytes": len(payload), "gzip9_bytes": len(gzip.compress(payload, compresslevel=9, mtime=0)),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": sha256(path), "members": members,
            "gzip_measurement": "local deterministic gzip9; not an observed server transfer"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / ".cache" / "godot-web-source")
    parser.add_argument("--profile", type=Path, default=ROOT / "tools" / "web_template" / "blockfield.py")
    parser.add_argument("--emsdk", type=Path, default=ROOT / ".cache" / "emsdk")
    parser.add_argument("--python", type=Path, default=Path(sys.executable), help="Python with SCons installed")
    parser.add_argument("--scons-dir", type=Path, help="Optional local pip --target directory containing SCons")
    parser.add_argument("--node", type=Path, help="Select emsdk Node if multiple versions are installed")
    parser.add_argument("--output", type=Path, default=ROOT / ".cache" / "web-template" / "blockfield-web-release.zip")
    parser.add_argument("--log", type=Path, default=ROOT / ".cache" / "logs" / "web-template-build.log")
    parser.add_argument("--metadata", type=Path, help="Defaults to --output with .json suffix")
    parser.add_argument("--jobs", type=int, default=2, help="Compile jobs, 1..min(logical CPUs, 16)")
    parser.add_argument("--link-jobs", type=int, default=2, help="Thin LTO jobs, 1..min(logical CPUs, 16)")
    parser.add_argument("--expected-source-revision", default=REVISION,
                        help="Expected Godot Git commit (defaults to the pinned 4.7.2 revision)")
    parser.add_argument("--expected-emscripten-version", default="4.0.11")
    parser.add_argument("--expected-scons-version", default="4.9.1")
    parser.add_argument("--dry-run", action="store_true", help="Validate prerequisites and print command; no compilation or output")
    parser.add_argument("--force", action="store_true", help="Allow replacing the explicitly selected output/log/metadata")
    args = parser.parse_args()
    maximum_jobs = min(os.cpu_count() or 1, 16)
    if not 1 <= args.jobs <= maximum_jobs or not 1 <= args.link_jobs <= maximum_jobs:
        parser.error(f"--jobs and --link-jobs must each be between 1 and {maximum_jobs}")
    source, profile, emsdk = (args.source.resolve(), args.profile.resolve(), args.emsdk.resolve())
    python, output, log = (args.python.resolve(), args.output.resolve(), args.log.resolve())
    metadata = (args.metadata or output.with_suffix(".json")).resolve()
    if not python.is_file():
        parser.error("--python must select an existing Python executable")
    if output.suffix.lower() != ".zip":
        parser.error("--output must end with .zip")
    if len({output, log, metadata}) != 3:
        parser.error("--output, --log and --metadata must be distinct paths")
    if not args.dry_run and not args.force:
        for path in (output, log, metadata):
            if path.exists():
                parser.error(f"Preserve existing artifact: {path}; use another path or explicit --force")
    started = time.monotonic()
    data = {
        "kind": "blockfield-custom-godot-web-template", "status": "preflight", "started_utc": timestamp(),
        "source": source_identity(source, args.expected_source_revision),
        "profile": profile_identity(profile), "jobs": args.jobs, "link_jobs": args.link_jobs,
        "compile_options": dict(BASE_OPTIONS), "log": str(log),
    }
    env = toolchain_environment(emsdk, args.scons_dir.resolve() if args.scons_dir else None,
                                args.node.resolve() if args.node else None)
    # Emscripten's Windows wrappers explicitly consume EMSDK_PYTHON. Do not let
    # `emcc.bat` select an unrelated PATH Python or the Windows Store alias.
    env["EMSDK_PYTHON"] = str(python)
    env["EMCC_CORES"] = str(args.jobs)
    env["BINARYEN_CORES"] = str(args.link_jobs)
    data["toolchain_parallelism"] = {"EMCC_CORES": args.jobs, "BINARYEN_CORES": args.link_jobs}
    data["toolchain"] = toolchain_identity(python, emsdk, env, args.expected_emscripten_version,
                                             args.expected_scons_version)
    command = [str(python), "-m", "SCons", f"-j{args.jobs}", f"profile={profile.as_posix()}",
               *(f"{key}={value}" for key, value in BASE_OPTIONS.items()),
               f"linkflags=-Wl,--thinlto-jobs={args.link_jobs}"]
    data["command"] = command
    data["compile_options"]["linkflags"] = f"-Wl,--thinlto-jobs={args.link_jobs}"
    if args.dry_run:
        data["status"] = "dry-run"
        print(json.dumps(data, indent=2), flush=True)
        return
    data["status"] = "building"
    write_metadata(metadata, data)
    try:
        code = compile_template(command, source, env, log)
        data["returncode"] = code
        if code:
            raise RuntimeError(f"Godot Web template compilation failed with exit {code}; see {log}")
        if sha256(profile) != data["profile"]["sha256"]:
            raise RuntimeError("Build profile changed during compilation; rebuild the frozen profile")
        if source_identity(source, args.expected_source_revision) != data["source"]:
            raise RuntimeError("Godot source changed during compilation; rebuild the frozen source")
        built = source / "bin" / TEMPLATE_NAME
        if not built.is_file():
            raise RuntimeError(f"Successful SCons did not produce the expected template: {built}")
        identity = template_identity(built)
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_suffix(output.suffix + ".tmp")
        shutil.copyfile(built, temporary)
        temporary.replace(output)
        identity["source_path"] = identity["path"]
        identity["path"] = str(output)
        data["template"] = identity
        data["status"] = "built"
    except BaseException as failure:
        data["status"] = "failed"
        data["error"] = str(failure) or type(failure).__name__
        raise
    finally:
        data["finished_utc"] = timestamp()
        data["elapsed_seconds"] = round(time.monotonic() - started, 3)
        if log.is_file():
            data["log_sha256"] = sha256(log)
        write_metadata(metadata, data)
    print(f"Template: {output}", flush=True)
    print(f"WASM: {data['template']['members']['godot.wasm']['bytes']:,} bytes; "
          f"gzip9: {data['template']['members']['godot.wasm']['gzip9_bytes']:,} bytes", flush=True)
    print(f"Metadata: {metadata}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as failure:
        raise SystemExit(str(failure)) from failure
