#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$root/addon"
manifest="$source_dir/package-manifest.txt"
output="${1:-$root/dist/@aviorstudio_gd-redis.zip}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
test -f "$manifest"
if [ -n "$(find "$source_dir" -type l -print -quit)" ]; then echo "Package source contains a symlink" >&2; exit 1; fi
(cd "$source_dir" && find . -type f ! -name package-manifest.txt -printf '%P\n' | LC_ALL=C sort) > "$stage/actual.txt"
if ! diff -u "$manifest" "$stage/actual.txt"; then echo "Package contents differ from addon/package-manifest.txt" >&2; exit 1; fi
package_root="$stage/package"
mkdir -p "$package_root" "$(dirname "$output")"
while IFS= read -r path; do
  case "$path" in ""|/*|*".."*) echo "Unsafe package path: $path" >&2; exit 1;; esac
  mkdir -p "$package_root/$(dirname "$path")"
  cp "$source_dir/$path" "$package_root/$path"
done < "$manifest"
rm -f "$output"
(cd "$package_root" && zip -X -q "$output" -@ < "$manifest")
sha256sum "$output"
