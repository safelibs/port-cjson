#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <original-on-build> <original-off-build> <safe-on-build> <safe-off-build>" >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SMOKE_SOURCE="$REPO_ROOT/safe/tests/regressions/locale_parse_print_smoke.c"
TMPDIR=$(mktemp -d)
LOCPATH_VALUE=""
TARGET_LOCALE=""

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

build_source_dir() {
    local build_dir=$1
    sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$build_dir/CMakeCache.txt" | tail -n1
}

cargo_profile_name() {
    local build_dir=$1
    local build_type

    build_type=$(sed -n 's/^CMAKE_BUILD_TYPE:STRING=//p' "$build_dir/CMakeCache.txt" | tail -n1)
    case "$build_type" in
        Release|RelWithDebInfo|MinSizeRel)
            printf 'release'
            ;;
        *)
            printf 'debug'
            ;;
    esac
}

build_library_dir() {
    local build_dir=$1
    local profile_dir
    local library

    profile_dir="$build_dir/cargo-target/$(cargo_profile_name "$build_dir")"
    if [ -e "$profile_dir/libcjson.so.1" ]; then
        dirname "$profile_dir/libcjson.so.1"
        return
    fi

    library=$(find "$build_dir" -maxdepth 4 \( -type f -o -type l \) \
        \( -name 'libcjson.so.*' -o -name 'libcjson.so' \) | sort | head -n1 || true)
    if [ -z "$library" ]; then
        echo "failed to locate libcjson shared library in $build_dir" >&2
        exit 1
    fi

    dirname "$library"
}

choose_locale() {
    local existing
    for existing in de_DE.UTF-8 de_DE.utf8 fr_FR.UTF-8 fr_FR.utf8; do
        if locale -a | grep -Fxq "$existing"; then
            TARGET_LOCALE=$existing
            return
        fi
    done

    if ! command -v localedef >/dev/null 2>&1; then
        echo "no comma-decimal locale available and localedef is missing" >&2
        exit 1
    fi

    mkdir -p "$TMPDIR/locales"
    if localedef --quiet -i de_DE -f UTF-8 "$TMPDIR/locales/de_DE.UTF-8" >/dev/null 2>&1; then
        LOCPATH_VALUE="$TMPDIR/locales"
        TARGET_LOCALE=de_DE.UTF-8
        return
    fi

    if localedef --quiet -i fr_FR -f UTF-8 "$TMPDIR/locales/fr_FR.UTF-8" >/dev/null 2>&1; then
        LOCPATH_VALUE="$TMPDIR/locales"
        TARGET_LOCALE=fr_FR.UTF-8
        return
    fi

    echo "failed to provision a comma-decimal locale" >&2
    exit 1
}

compile_smoke() {
    local build_dir=$1
    local output=$2
    local source_dir
    local library_dir

    source_dir=$(build_source_dir "$build_dir")
    library_dir=$(build_library_dir "$build_dir")

    ${CC:-cc} -std=c89 -pedantic -Wall -Wextra -Werror \
        -I"$source_dir" \
        "$SMOKE_SOURCE" \
        -L"$library_dir" \
        -Wl,-rpath,"$library_dir" \
        -lcjson \
        -o "$output"
}

run_smoke() {
    local executable=$1
    local library_dir=$2

    if [ -n "$LOCPATH_VALUE" ]; then
        env LOCPATH="$LOCPATH_VALUE" LC_ALL="$TARGET_LOCALE" LD_LIBRARY_PATH="$library_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$executable"
    else
        env LC_ALL="$TARGET_LOCALE" LD_LIBRARY_PATH="$library_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$executable"
    fi
}

compare_output() {
    local label=$1
    local expected=$2
    local actual=$3

    if [ "$expected" != "$actual" ]; then
        echo "$label mismatch" >&2
        diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
        exit 1
    fi
}

choose_locale

compile_smoke "$1" "$TMPDIR/original-on"
compile_smoke "$2" "$TMPDIR/original-off"
compile_smoke "$3" "$TMPDIR/safe-on"
compile_smoke "$4" "$TMPDIR/safe-off"

ORIGINAL_ON_LIBRARY_DIR=$(build_library_dir "$1")
ORIGINAL_OFF_LIBRARY_DIR=$(build_library_dir "$2")
SAFE_ON_LIBRARY_DIR=$(build_library_dir "$3")
SAFE_OFF_LIBRARY_DIR=$(build_library_dir "$4")

ORIGINAL_ON_OUTPUT=$(run_smoke "$TMPDIR/original-on" "$ORIGINAL_ON_LIBRARY_DIR")
ORIGINAL_OFF_OUTPUT=$(run_smoke "$TMPDIR/original-off" "$ORIGINAL_OFF_LIBRARY_DIR")
SAFE_ON_OUTPUT=$(run_smoke "$TMPDIR/safe-on" "$SAFE_ON_LIBRARY_DIR")
SAFE_OFF_OUTPUT=$(run_smoke "$TMPDIR/safe-off" "$SAFE_OFF_LIBRARY_DIR")

if [ "$ORIGINAL_ON_OUTPUT" = "$ORIGINAL_OFF_OUTPUT" ]; then
    echo "original locale-on and locale-off outputs are identical; the locale smoke did not exercise the build toggle" >&2
    exit 1
fi

compare_output "locale-on" "$ORIGINAL_ON_OUTPUT" "$SAFE_ON_OUTPUT"
compare_output "locale-off" "$ORIGINAL_OFF_OUTPUT" "$SAFE_OFF_OUTPUT"
