#!/bin/sh
set -eu

if [ "${1:-}" = l ]; then
  cat <<'EOF'
----------
Path = extracted.txt
Folder = -
Attributes =  -rw-r--r--
EOF
  exit 0
fi

destination=
for argument in "$@"; do
  case "$argument" in
    -o*) destination=${argument#-o} ;;
  esac
done
[ -n "$destination" ] || exit 2
sleep "${UNPACK_FLOW_TEST_DELAY:-3}"
mkdir -p "$destination"
printf 'monitored extraction completed\n' > "$destination/extracted.txt"
