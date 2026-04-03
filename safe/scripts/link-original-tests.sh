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
SAFE_TESTS_DIR="$SAFE_DIR/tests"
BUILD_DIR=$(cd "$1" && pwd)
WORK_DIR=$(mktemp -d)
OBJECT_DIR="$WORK_DIR/objects"
INCLUDE_COMPAT_DIR="$WORK_DIR/include"
RUN_ROOT="$WORK_DIR/run"
RUN_TESTS_DIR="$RUN_ROOT/tests"
LOG_DIR="$WORK_DIR/logs"
CC_BIN=${CC:-cc}

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    printf 'link-original-tests: %s\n' "$*" >&2
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

cache_value() {
    local key=$1

    sed -n "s/^${key}:[^=]*=//p" "$2/CMakeCache.txt" | tail -n1
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

require_build_option() {
    local option_name=$1
    local expected_value=$2
    local actual_value

    actual_value=$(cache_value "$option_name" "$BUILD_DIR")
    [[ -n "$actual_value" ]] || fail "missing cache entry: $option_name"
    [[ "$actual_value" == "$expected_value" ]] || fail "build dir $BUILD_DIR has ${option_name}=${actual_value}, expected ${expected_value}"
}

has_required_libraries() {
    local profile_dir=$1
    local require_utils=$2

    [[ -f "$profile_dir/libcjson.so" ]] || return 1
    if [[ "$require_utils" -eq 1 ]]; then
        [[ -f "$profile_dir/libcjson_utils.so" ]] || return 1
    fi

    return 0
}

build_library_dir() {
    local build_dir=$1
    local require_utils=$2
    local profile_dir
    local -a candidates=()
    local candidate_dir

    profile_dir="$build_dir/cargo-target/$(cargo_profile_name "$build_dir")"
    if has_required_libraries "$profile_dir" "$require_utils"; then
        printf '%s\n' "$profile_dir"
        return
    fi

    expect_dir "$build_dir/cargo-target"
    while IFS= read -r -d '' candidate_dir; do
        if has_required_libraries "$candidate_dir" "$require_utils"; then
            candidates+=("$candidate_dir")
        fi
    done < <(find "$build_dir/cargo-target" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    case "${#candidates[@]}" in
        1)
            printf '%s\n' "${candidates[0]}"
            ;;
        0)
            fail "no cargo library directory under $build_dir/cargo-target contains the relink targets"
            ;;
        *)
            fail "multiple cargo library directories under $build_dir/cargo-target contain relink targets: ${candidates[*]}"
            ;;
    esac
}

prepare_include_compat() {
    mkdir -p "$INCLUDE_COMPAT_DIR/cjson"
    ln -s "$ORIGINAL_DIR/cJSON.h" "$INCLUDE_COMPAT_DIR/cjson/cJSON.h"
    ln -s "$ORIGINAL_DIR/cJSON_Utils.h" "$INCLUDE_COMPAT_DIR/cjson/cJSON_Utils.h"
}

compile_object() {
    local source=$1
    local output=$2
    shift 2

    "$CC_BIN" -std=c89 -pedantic -Wall -Wextra -Werror \
        -I"$ORIGINAL_DIR" \
        -I"$ORIGINAL_DIR/tests" \
        -I"$ORIGINAL_DIR/tests/unity/src" \
        -I"$INCLUDE_COMPAT_DIR" \
        "$@" \
        -c "$source" \
        -o "$output"
}

compile_unity() {
    "$CC_BIN" -std=c89 -pedantic -Wall -Wextra -Wno-error -Wno-switch-enum \
        -I"$ORIGINAL_DIR/tests/unity/src" \
        -c "$ORIGINAL_DIR/tests/unity/src/unity.c" \
        -o "$OBJECT_DIR/unity.o"
}

link_core_binary() {
    local output=$1
    shift

    "$CC_BIN" "$@" \
        -L"$LIB_DIR" \
        -Wl,-rpath,"$LIB_DIR" \
        -lcjson \
        -lm \
        -o "$output"
}

link_utils_binary() {
    local output=$1
    shift

    "$CC_BIN" "$@" \
        -L"$LIB_DIR" \
        -Wl,-rpath,"$LIB_DIR" \
        -lcjson_utils \
        -lcjson \
        -lm \
        -o "$output"
}

run_binary() {
    local workdir=$1
    local binary_name=$2
    local log_file="$LOG_DIR/${binary_name}.log"

    if ! (
        cd "$workdir"
        env LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "./$binary_name"
    ) >"$log_file" 2>&1; then
        printf 'link-original-tests: %s failed\n' "$binary_name" >&2
        cat "$log_file" >&2
        exit 1
    fi

    printf 'link-original-tests: ok %s\n' "$binary_name"
}

CORE_TESTS=(
    parse_examples
    parse_number
    parse_hex4
    parse_string
    parse_array
    parse_object
    parse_value
    print_string
    print_number
    print_array
    print_object
    print_value
    misc_tests
    parse_with_opts
    compare_tests
    cjson_add
    readme_examples
    minify_tests
    public_api_coverage
)

UTILS_TESTS=(
    json_patch_tests
    old_utils_tests
    misc_utils_tests
)

expect_file "$BUILD_DIR/CMakeCache.txt"
BUILD_SOURCE_DIR=$(build_source_dir "$BUILD_DIR")
BUILD_SOURCE_DIR=$(cd "$BUILD_SOURCE_DIR" && pwd)
[[ "$BUILD_SOURCE_DIR" == "$SAFE_DIR" ]] || fail "build dir $BUILD_DIR was configured for $BUILD_SOURCE_DIR, expected $SAFE_DIR"
require_build_option ENABLE_CJSON_TEST ON
require_build_option ENABLE_CJSON_UTILS ON

expect_dir "$ORIGINAL_DIR/tests"
expect_dir "$SAFE_TESTS_DIR/inputs"
expect_dir "$SAFE_TESTS_DIR/json-patch-tests"
mkdir -p "$OBJECT_DIR" "$RUN_TESTS_DIR" "$LOG_DIR"
prepare_include_compat

LIB_DIR=$(build_library_dir "$BUILD_DIR" 1)

compile_object "$ORIGINAL_DIR/test.c" "$OBJECT_DIR/cJSON_test.o"
compile_unity

for test_name in "${CORE_TESTS[@]}"; do
    compile_object "$ORIGINAL_DIR/tests/${test_name}.c" "$OBJECT_DIR/${test_name}.o"
done

for test_name in "${UTILS_TESTS[@]}"; do
    compile_object "$ORIGINAL_DIR/tests/${test_name}.c" "$OBJECT_DIR/${test_name}.o"
done

mkdir -p "$RUN_TESTS_DIR/inputs" "$RUN_TESTS_DIR/json-patch-tests"
cp -a "$SAFE_TESTS_DIR/inputs/." "$RUN_TESTS_DIR/inputs/"
cp -a "$SAFE_TESTS_DIR/json-patch-tests/." "$RUN_TESTS_DIR/json-patch-tests/"

link_core_binary "$RUN_ROOT/cJSON_test" "$OBJECT_DIR/cJSON_test.o"

for test_name in "${CORE_TESTS[@]}"; do
    link_core_binary "$RUN_TESTS_DIR/$test_name" "$OBJECT_DIR/${test_name}.o" "$OBJECT_DIR/unity.o"
done

for test_name in "${UTILS_TESTS[@]}"; do
    link_utils_binary "$RUN_TESTS_DIR/$test_name" "$OBJECT_DIR/${test_name}.o" "$OBJECT_DIR/unity.o"
done

run_binary "$RUN_ROOT" cJSON_test

for test_name in "${CORE_TESTS[@]}"; do
    run_binary "$RUN_TESTS_DIR" "$test_name"
done

for test_name in "${UTILS_TESTS[@]}"; do
    run_binary "$RUN_TESTS_DIR" "$test_name"
done

printf 'link-original-tests: ok\n'
