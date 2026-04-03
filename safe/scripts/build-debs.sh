#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SAFE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=""

usage() {
  cat <<'EOF'
usage: build-debs.sh <temp-work-dir>

Copies safe/ into the supplied writable work directory, runs
dpkg-buildpackage there, and leaves the resulting artifacts at:

  <temp-work-dir>

It also mirrors them under:

  <temp-work-dir>/artifacts
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

WORK_DIR="$1"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd -- "$WORK_DIR" && pwd)"

SOURCE_PARENT="$WORK_DIR/source"
SOURCE_DIR="$SOURCE_PARENT/cjson"
ARTIFACT_DIR="$WORK_DIR/artifacts"

rm -rf "$SOURCE_DIR" "$ARTIFACT_DIR"
mkdir -p "$SOURCE_PARENT" "$ARTIFACT_DIR"
rm -f "$SOURCE_PARENT"/*.deb "$SOURCE_PARENT"/*.buildinfo "$SOURCE_PARENT"/*.changes
rm -f "$WORK_DIR"/*.deb "$WORK_DIR"/*.buildinfo "$WORK_DIR"/*.changes

cp -a "$SAFE_ROOT/." "$SOURCE_DIR/"

export PATH="/usr/bin:/bin${PATH:+:$PATH}"

(
  cd "$SOURCE_DIR"
  dpkg-buildpackage -us -uc -b
)

shopt -s nullglob
artifacts=(
  "$SOURCE_PARENT"/*.deb
  "$SOURCE_PARENT"/*.buildinfo
  "$SOURCE_PARENT"/*.changes
)
shopt -u nullglob

if [[ "${#artifacts[@]}" -eq 0 ]]; then
  printf 'build-debs: no package artifacts were produced in %s\n' "$SOURCE_PARENT" >&2
  exit 1
fi

cp -a "${artifacts[@]}" "$ARTIFACT_DIR/"
cp -a "${artifacts[@]}" "$WORK_DIR/"
printf '%s\n' "$ARTIFACT_DIR"
