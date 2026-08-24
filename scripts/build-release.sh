#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash "$root/scripts/check-anonymization.sh"
version=$(sed -n "s/^VERSION='\([^']*\)'.*/\1/p" "$root/scripts/unpack-flow")
dist="$root/dist"
stage="$dist/.stage"
assets="$dist/release-assets"
rm -rf -- "$stage" "$assets"
mkdir -p "$stage/linux/scripts" "$stage/macos/scripts" "$stage/macos/tools" "$stage/windows/scripts" "$stage/windows/tools"

cp "$root/install-linux.sh" "$stage/linux/"
cp "$root/scripts/unpack-flow" "$root/scripts/preflight.sh" "$root/scripts/preflight-remote.sh" "$root/scripts/deploy.sh" "$root/scripts/install-cli-linux.sh" "$stage/linux/scripts/"
mkdir -p "$stage/linux/tools"
cp -R "$root/tools/linux-x64" "$stage/linux/tools/"
cp "$root/install-macos.sh" "$stage/macos/"
cp "$root/scripts/unpack-flow.ps1" "$root/scripts/unpack-flow-macos" "$root/scripts/preflight-macos.sh" "$root/scripts/install-cli-macos.sh" "$stage/macos/scripts/"
cp -R "$root/tools/macos-arm64" "$stage/macos/tools/"
cp "$root/scripts/unpack-flow.ps1" "$root/scripts/preflight-windows.ps1" "$root/scripts/install-cli-windows.ps1" "$stage/windows/scripts/"
cp "$root/install.bat" "$stage/windows/"
cp -R "$root/tools/windows-x64" "$root/tools/windows-arm64" "$stage/windows/tools/"
cp "$root/tools/7zip-License.txt" "$stage/windows/tools/"
public_docs=(LICENSE README.md PUBLISHER.md SECURITY.md SUPPORT.md)
for platform in linux macos windows; do
  for file in "${public_docs[@]}"; do
    cp "$root/$file" "$stage/$platform/"
  done
done

command -v python3 >/dev/null 2>&1 || { echo 'python3 is required to build reproducible release archives' >&2; exit 4; }
source_date_epoch=${SOURCE_DATE_EPOCH:-}
if [[ -z "$source_date_epoch" && -f "$root/RELEASE-METADATA.json" ]]; then
  source_date_epoch=$(python3 - "$root/RELEASE-METADATA.json" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text()).get("source_date_epoch")
if not isinstance(value, int):
    raise SystemExit("RELEASE-METADATA.json has no integer source_date_epoch")
print(value)
PY
  )
fi
source_date_epoch=${source_date_epoch:-$(git -C "$root" show -s --format=%ct HEAD)}
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || { echo 'SOURCE_DATE_EPOCH must be an integer Unix timestamp' >&2; exit 4; }

# Git checkout settings may rewrite text files to CRLF. Normalize staged text,
# including reviewed tools/*.txt license/readme files, while preserving native
# binaries and bundled archives byte-for-byte.
python3 "$root/scripts/normalize-release-tree.py" "$stage"
UNPACK_FLOW_VERSION="$version" python3 "$root/scripts/create-reproducible-archives.py" \
  "$source_date_epoch" "$stage/linux" "$stage/macos" "$stage/windows" "$assets"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$assets" && sha256sum "unpack-flow-$version-linux.tar.gz" "unpack-flow-$version-macos.tar.gz" "unpack-flow-$version-windows.zip" > SHA256SUMS)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$assets" && shasum -a 256 "unpack-flow-$version-linux.tar.gz" "unpack-flow-$version-macos.tar.gz" "unpack-flow-$version-windows.zip" > SHA256SUMS)
else
  echo 'sha256sum or shasum is required' >&2; exit 4
fi

verify_root="$dist/.verify"
mkdir -p "$verify_root"
for artifact in "$assets/unpack-flow-$version-linux.tar.gz" "$assets/unpack-flow-$version-macos.tar.gz" "$assets/unpack-flow-$version-windows.zip"; do
  artifact_name=$(basename -- "$artifact")
  extracted="$verify_root/$artifact_name"
  mkdir -p "$extracted"
  case "$artifact" in
    *.tar.gz) tar -xzf "$artifact" -C "$extracted" ;;
    *.zip) unzip -q "$artifact" -d "$extracted" ;;
    *) echo "Unsupported release artifact: $artifact" >&2; exit 5 ;;
  esac
  while IFS= read -r forbidden_path; do
    echo "Private control-plane content leaked into $artifact_name: ${forbidden_path#$extracted/}" >&2
    exit 5
  done < <(find "$extracted" \( -name '.gitlab-ci.yml' -o -name '.internal' -o -path '*/.internal/*' -o -name 'release-evidence' -o -path '*/release-evidence/*' -o -path '*/scripts/export-public-source.sh' \) -print)
done
rm -rf -- "$verify_root"
rm -rf -- "$stage"
printf 'Built reproducible release %s in %s (SOURCE_DATE_EPOCH=%s)\n' "$version" "$assets" "$source_date_epoch"
