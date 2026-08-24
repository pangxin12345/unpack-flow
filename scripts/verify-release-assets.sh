#!/usr/bin/env bash
set -Eeuo pipefail
expected=${1:-}; actual=${2:-}
[[ -d "$expected" && -d "$actual" ]] || { echo 'usage: verify-release-assets.sh EXPECTED_DIR ACTUAL_DIR' >&2; exit 2; }
expected_names=$(cd "$expected" && find . -maxdepth 1 -type f -print | sed 's#^./##' | sort)
actual_names=$(cd "$actual" && find . -maxdepth 1 -type f -print | sed 's#^./##' | sort)
[[ "$expected_names" == "$actual_names" ]] || { echo 'Release attachment set differs from allowlist' >&2; exit 3; }
while IFS= read -r name; do cmp "$expected/$name" "$actual/$name" >/dev/null || { echo "Release attachment differs: $name" >&2; exit 3; }; done <<< "$expected_names"
(cd "$actual" && if command -v sha256sum >/dev/null; then sha256sum -c SHA256SUMS; else shasum -a 256 -c SHA256SUMS; fi)
echo 'Release attachment set: PASS'
