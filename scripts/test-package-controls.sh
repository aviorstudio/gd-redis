#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
valid="$root/dist/@aviorstudio_gd-redis.zip"
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
expect_rejected() {
  if "$root/scripts/verify-package.sh" "$1" >/dev/null 2>&1; then
    echo "FAIL: package gate accepted $2" >&2; exit 1
  fi
  echo "PASS package gate rejected $2"
}
python3 - "$valid" "$scratch" <<'PY'
import pathlib, shutil, stat, sys, zipfile
valid, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with zipfile.ZipFile(valid) as source:
    entries = [(i, source.read(i)) for i in source.infolist() if not i.is_dir()]
def write(name, selected, extra=None):
    with zipfile.ZipFile(out/name, 'w') as z:
        for info, data in selected: z.writestr(info, data)
        if extra: z.writestr(*extra)
write('missing.zip', entries[:-1])
write('unexpected.zip', entries, ('tests/dev.gd', b'development artifact'))
write('traversal.zip', entries, ('../escape.gd', b'unsafe'))
link = zipfile.ZipInfo('link.gd'); link.create_system = 3; link.external_attr = (stat.S_IFLNK | 0o777) << 16
write('symlink.zip', entries, (link, b'plugin.gd'))
PY
for kind in missing unexpected traversal symlink; do expect_rejected "$scratch/$kind.zip" "$kind archive"; done
"$root/scripts/verify-package.sh" "$valid"
echo "PASS package controls restored"
