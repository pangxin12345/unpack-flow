#!/usr/bin/env bash
set -Eeuo pipefail

project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
engine=${UNPACK_FLOW_ENGINE:-$project/scripts/unpack-flow}
root=$(mktemp -d "${TMPDIR:-/tmp}/unpack-flow-path-safety.XXXXXX")
root=$(CDPATH= cd -- "$root" && pwd -P)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/input" "$root/output" "$root/state"

python3 - "$root" <<'PY'
import io, pathlib, tarfile, zipfile, sys

root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(root / "input" / "valid.zip", "w") as archive:
    archive.writestr("safe/marker.txt", "safe\n")
for filename, entry in (
    ("parent.zip", "../escape-parent.txt"),
    ("absolute.zip", str(root / "escape-absolute.txt")),
    ("drive.zip", r"C:\escape-drive.txt"),
    ("mixed.zip", r"safe\..\..\escape-mixed.txt"),
):
    with zipfile.ZipFile(root / "input" / filename, "w") as archive:
        archive.writestr(entry, "blocked\n")
with zipfile.ZipFile(root / "input" / "link.zip", "w") as archive:
    info = zipfile.ZipInfo("safe-link")
    info.create_system = 3
    info.external_attr = (0o120777 << 16)
    archive.writestr(info, "../escape-link.txt")
with tarfile.open(root / "input" / "traversal.tar", "w") as archive:
    payload = b"blocked\n"
    info = tarfile.TarInfo("../../escape-tar.txt")
    info.size = len(payload)
    archive.addfile(info, io.BytesIO(payload))
with tarfile.open(root / "input" / "link.tar", "w") as archive:
    info = tarfile.TarInfo("safe-link")
    info.type = tarfile.SYMTYPE
    info.linkname = "../escape-link-tar.txt"
    archive.addfile(info)
with zipfile.ZipFile(root / "input" / "inner.zip", "w") as archive:
    archive.writestr("../../escape-inner.txt", "blocked\n")
with zipfile.ZipFile(root / "input" / "outer.zip", "w") as archive:
    archive.write(root / "input" / "inner.zip", "nested/inner.zip")
PY

PATH="/opt/homebrew/bin:$PATH" UNPACK_FLOW_STATE_ROOT="$root/state-valid" \
  "$engine" run -o "$root/output-valid" "$root/input/valid.zip"
test -f "$root/output-valid/safe/marker.txt"

for archive in parent.zip absolute.zip drive.zip mixed.zip link.zip traversal.tar link.tar; do
  set +e
  PATH="/opt/homebrew/bin:$PATH" UNPACK_FLOW_STATE_ROOT="$root/state-$archive" \
    "$engine" run -o "$root/output" "$root/input/$archive" >/dev/null 2>&1
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || { echo "Unsafe archive unexpectedly succeeded: $archive" >&2; exit 1; }
done

set +e
PATH="/opt/homebrew/bin:$PATH" UNPACK_FLOW_STATE_ROOT="$root/state-inner" \
  "$engine" run -o "$root/output-inner" "$root/input/outer.zip" >/dev/null 2>&1
inner_rc=$?
set -e
[[ $inner_rc -ne 0 ]]

for escaped in \
  "$root/escape-parent.txt" "$root/escape-absolute.txt" "$root/escape-drive.txt" \
  "$root/escape-mixed.txt" "$root/escape-link.txt" "$root/escape-tar.txt" \
  "$root/escape-link-tar.txt" "$root/escape-inner.txt"; do
  [[ ! -e "$escaped" ]] || { echo "Archive traversal wrote outside output: $escaped" >&2; exit 1; }
done
[[ -z "$(find "$root" -name 'escape-*' -print -quit)" ]] || {
  echo 'Archive traversal created an escaped file below the test root' >&2
  exit 1
}
[[ -z "$(find "$root" -type d \( -name '.unpack_flow_*' -o -name '.uf_*' -o -name '.ufi_*' \) -print -quit)" ]]
printf '%s\n' 'Bash archive path safety: PASS'
