#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <safe-build-dir>" >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SAFE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SAFE_DIR/.." && pwd)
ORIGINAL_DIR="$REPO_ROOT/original"
BUILD_DIR=$(cd "$1" && pwd)
WORK_DIR=$(mktemp -d)
INCLUDE_COMPAT_DIR="$WORK_DIR/include"
LOG_DIR="$WORK_DIR/logs"
FUZZ_BINARY="$WORK_DIR/fuzz_main"
CC_BIN=${CC:-cc}

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    printf 'replay-fuzz-corpus: %s\n' "$*" >&2
    exit 1
}

expect_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

expect_dir() {
    [[ -d "$1" ]] || fail "missing directory: $1"
}

build_source_dir() {
    sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$1/CMakeCache.txt" | tail -n1
}

cargo_profile_name() {
    local build_type

    build_type=$(sed -n 's/^CMAKE_BUILD_TYPE:STRING=//p' "$1/CMakeCache.txt" | tail -n1)
    case "$build_type" in
        Release|RelWithDebInfo|MinSizeRel)
            printf 'release'
            ;;
        *)
            printf 'debug'
            ;;
    esac
}

has_required_libraries() {
    local profile_dir=$1

    [[ -f "$profile_dir/libcjson.so" ]]
}

build_library_dir() {
    local build_dir=$1
    local profile_dir
    local -a candidates=()
    local candidate_dir

    profile_dir="$build_dir/cargo-target/$(cargo_profile_name "$build_dir")"
    if has_required_libraries "$profile_dir"; then
        printf '%s\n' "$profile_dir"
        return
    fi

    expect_dir "$build_dir/cargo-target"
    while IFS= read -r -d '' candidate_dir; do
        if has_required_libraries "$candidate_dir"; then
            candidates+=("$candidate_dir")
        fi
    done < <(find "$build_dir/cargo-target" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    case "${#candidates[@]}" in
        1)
            printf '%s\n' "${candidates[0]}"
            ;;
        0)
            fail "no cargo library directory under $build_dir/cargo-target contains the fuzz replay target"
            ;;
        *)
            fail "multiple cargo library directories under $build_dir/cargo-target contain fuzz replay targets: ${candidates[*]}"
            ;;
    esac
}

prepare_include_compat() {
    mkdir -p "$INCLUDE_COMPAT_DIR/cjson"
    ln -s "$ORIGINAL_DIR/cJSON.h" "$INCLUDE_COMPAT_DIR/cjson/cJSON.h"
    ln -s "$ORIGINAL_DIR/cJSON_Utils.h" "$INCLUDE_COMPAT_DIR/cjson/cJSON_Utils.h"
}

expect_file "$BUILD_DIR/CMakeCache.txt"
BUILD_SOURCE_DIR=$(build_source_dir "$BUILD_DIR")
BUILD_SOURCE_DIR=$(cd "$BUILD_SOURCE_DIR" && pwd)
[[ "$BUILD_SOURCE_DIR" == "$SAFE_DIR" ]] || fail "build dir $BUILD_DIR was configured for $BUILD_SOURCE_DIR, expected $SAFE_DIR"

CORPUS_DIR="$ORIGINAL_DIR/fuzzing/inputs"
DICT_FILE="$ORIGINAL_DIR/fuzzing/json.dict"
expect_dir "$CORPUS_DIR"
expect_file "$DICT_FILE"

mkdir -p "$LOG_DIR"
prepare_include_compat

LIB_DIR=$(build_library_dir "$BUILD_DIR")

"$CC_BIN" -std=c89 -pedantic -Wall -Wextra -Werror \
    -I"$ORIGINAL_DIR" \
    -I"$INCLUDE_COMPAT_DIR" \
    "$ORIGINAL_DIR/fuzzing/fuzz_main.c" \
    "$ORIGINAL_DIR/fuzzing/cjson_read_fuzzer.c" \
    -L"$LIB_DIR" \
    -Wl,-rpath,"$LIB_DIR" \
    -lcjson \
    -lm \
    -o "$FUZZ_BINARY"

if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(timeout --preserve-status 10s)
else
    TIMEOUT_CMD=()
fi

printf 'replay-fuzz-corpus: corpus=%s dict=%s\n' "$CORPUS_DIR" "$DICT_FILE"

FOUND_INPUT=0
while IFS= read -r -d '' input_file; do
    input_name=$(basename "$input_file")
    log_file="$LOG_DIR/${input_name}.log"
    FOUND_INPUT=1

    if ! env LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "${TIMEOUT_CMD[@]}" "$FUZZ_BINARY" "$input_file" >"$log_file" 2>&1; then
        printf 'replay-fuzz-corpus: seed %s failed\n' "$input_name" >&2
        cat "$log_file" >&2
        exit 1
    fi

    printf 'replay-fuzz-corpus: ok %s\n' "$input_name"
done < <(find "$CORPUS_DIR" -maxdepth 1 -type f -print0 | sort -z)

[[ "$FOUND_INPUT" -eq 1 ]] || fail "no corpus inputs found in $CORPUS_DIR"

printf 'replay-fuzz-corpus: ok\n'
