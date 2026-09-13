#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-$root/dist/@aviorstudio_gd-redis.zip}"
manifest="$root/addon/package-manifest.txt"
python3 - "$archive" "$manifest" <<'PY'
import pathlib, stat, sys, zipfile
expected = pathlib.Path(sys.argv[2]).read_text().splitlines()
with zipfile.ZipFile(sys.argv[1]) as package:
    infos = package.infolist()
    names = [entry.filename.rstrip('/') for entry in infos if not entry.is_dir()]
    if names != expected:
        raise SystemExit(f"closed manifest mismatch\nexpected={expected!r}\nactual={names!r}")
    for entry in infos:
        path = pathlib.PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit(f"unsafe archive path: {entry.filename}")
        if stat.S_ISLNK(entry.external_attr >> 16):
            raise SystemExit(f"archive symlink rejected: {entry.filename}")
print(f"PASS closed package manifest ({len(expected)} files)")
PY
sha256sum "$archive"
