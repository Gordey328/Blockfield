"""Publish a checked Web export at a sibling Pages path, preserving root files."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time
from github_api import api

ROOT = Path(__file__).resolve().parents[1]


def git(*args, cwd=ROOT):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                          text=True, check=True).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", type=Path, required=True)
    parser.add_argument("--slug", default="reduced")
    parser.add_argument("--repo", default="Gordey328/Blockfield")
    parser.add_argument("--seed-repo", type=Path, help="Existing local gh-pages checkout, read only")
    parser.add_argument("--update-existing", action="store_true", help="Replace the same canonical file set at an existing sibling path")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9-]*", args.slug):
        parser.error("Use one lowercase URL path component")
    folder = args.folder.resolve()
    metadata = json.loads((folder / "build-info.json").read_text(encoding="utf-8"))
    revision = metadata.get("source_commit", "")
    if metadata.get("source_dirty") is not False or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise RuntimeError("Requires a checked frozen clean source revision")
    git("cat-file", "-e", revision + "^{commit}")
    for name in ("index.html", "index.js", "index.wasm", "index.pck", ".nojekyll", "LICENSE.txt"):
        if not (folder / name).is_file():
            raise RuntimeError("Missing checked export: " + name)
    if (folder / ".git").exists():
        raise RuntimeError("Use a plain checked export, not a release checkout")
    paths = sorted(path for path in folder.rglob("*") if path.is_file())
    names = {path.relative_to(folder).as_posix() for path in paths}
    if any(path.is_symlink() or path.name in ("arsenal-touch.html", "arsenal-touch-tools.js") for path in paths):
        raise RuntimeError("Private helpers and symlinks are not canonical release files")
    pages = api("/repos/" + args.repo + "/pages")
    if pages.get("source") != {"branch": "gh-pages", "path": "/"}:
        raise RuntimeError("Expected existing gh-pages root hosting")
    workspace = ROOT / ".cache" / ("pages-variant-" + args.slug + "-" + str(time.time_ns()))
    workspace.parent.mkdir(parents=True, exist_ok=True)
    remote = "https://github.com/" + args.repo + ".git"
    if args.seed_repo:
        seed = args.seed_repo.resolve()
        if git("remote", "get-url", "origin", cwd=seed) != remote:
            raise RuntimeError("Seed belongs to another repository")
        git("clone", "--no-hardlinks", str(seed), str(workspace))
        git("remote", "set-url", "origin", remote, cwd=workspace)
        git("fetch", "origin", "gh-pages", cwd=workspace)
        git("checkout", "-B", "gh-pages", "origin/gh-pages", cwd=workspace)
    else:
        git("clone", "--depth", "1", "--single-branch", "--branch", "gh-pages",
            remote, str(workspace))
    git("config", "user.name", git("config", "user.name"), cwd=workspace)
    git("config", "user.email", git("config", "user.email"), cwd=workspace)
    git("config", "core.autocrlf", "false", cwd=workspace)
    target = workspace / args.slug
    if target.exists() and not args.update_existing:
        raise RuntimeError("Sibling path already exists; preserve it and inspect before updating")
    if args.update_existing:
        if not target.is_dir() or target.is_symlink():
            raise RuntimeError("Expected an existing regular sibling directory")
        old_paths = sorted(path for path in target.rglob("*") if path.is_file())
        if names != {path.relative_to(target).as_posix() for path in old_paths} or any(path.is_symlink() for path in old_paths):
            raise RuntimeError("Existing release file set differs; inspect additions/removals explicitly")
        for path in paths:
            shutil.copyfile(path, target / path.relative_to(folder))
    else:
        shutil.copytree(folder, target)
    for path in paths:
        copied = target / path.relative_to(folder)
        if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(copied.read_bytes()).digest():
            raise RuntimeError("Copied file differs: " + str(path))
    if any(not name.startswith(args.slug + "/") for name in git("diff", "--name-only", cwd=workspace).splitlines()):
        raise RuntimeError("Publication would change another Pages path")
    git("add", "--", args.slug, cwd=workspace)
    git("commit", "-m", "Publish checked Web development build at /" + args.slug + "/", cwd=workspace)
    # Concurrent root publication can advance gh-pages. Rebase this independent
    # directory addition onto it; never force-push or replace root assets.
    for attempt in range(3):
        try:
            git("push", "origin", "HEAD:gh-pages", cwd=workspace)
            break
        except subprocess.CalledProcessError:
            if attempt == 2:
                raise
            git("fetch", "origin", "gh-pages", cwd=workspace)
            git("rebase", "origin/gh-pages", cwd=workspace)
    queued = api("/repos/" + args.repo + "/pages/builds", "POST")
    url = pages["html_url"].rstrip("/") + "/" + args.slug + "/"
    result = {"status": queued.get("status"), "url": url, "source_commit": revision, "file_count": len(paths),
              "bundle_commit": git("rev-parse", "HEAD", cwd=workspace),
              "workspace": str(workspace)}
    (workspace / "publication.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2), flush=True)


if __name__ == "__main__":
    main()
