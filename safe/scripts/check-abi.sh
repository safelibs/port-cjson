#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=$(mktemp -d)
INSTALL_DIR=$(mktemp -d)
CONSUMER_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$BUILD_DIR" "$INSTALL_DIR" "$CONSUMER_DIR"
}
trap cleanup EXIT

fail() {
    printf 'check-abi: %s\n' "$*" >&2
    exit 1
}

expect_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

expect_contains() {
    local needle=$1
    local file=$2
    grep -F "$needle" "$file" >/dev/null || fail "expected '$needle' in $file"
}

expected_symbols() {
    local section=$1
    awk -v wanted="$section" '
        /^libcjson\.so\.1 / { current="core"; next }
        /^libcjson_utils\.so\.1 / { current="utils"; next }
        /^[[:space:]][^[:space:]]/ && current == wanted {
            split($1, parts, "@");
            print parts[1];
        }
    ' "$ROOT_DIR/debian/libcjson1.symbols" | sort
}

actual_symbols() {
    nm -D --defined-only "$1" | awk '{print $3}' | sort
}

cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -DENABLE_CJSON_UTILS=ON \
    -DENABLE_CJSON_TEST=OFF \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" >/dev/null
cmake --build "$BUILD_DIR" >/dev/null
cmake --install "$BUILD_DIR" >/dev/null

CORE_LIB="$INSTALL_DIR/lib/libcjson.so.1.7.17"
UTILS_LIB="$INSTALL_DIR/lib/libcjson_utils.so.1.7.17"
CORE_PC="$INSTALL_DIR/lib/pkgconfig/libcjson.pc"
UTILS_PC="$INSTALL_DIR/lib/pkgconfig/libcjson_utils.pc"

expect_file "$CORE_LIB"
expect_file "$UTILS_LIB"
expect_file "$INSTALL_DIR/lib/libcjson.so"
expect_file "$INSTALL_DIR/lib/libcjson.so.1"
expect_file "$INSTALL_DIR/lib/libcjson_utils.so"
expect_file "$INSTALL_DIR/lib/libcjson_utils.so.1"
expect_file "$INSTALL_DIR/include/cjson/cJSON.h"
expect_file "$INSTALL_DIR/include/cjson/cJSON_Utils.h"
expect_file "$INSTALL_DIR/lib/cmake/cJSON/cJSONConfig.cmake"
expect_file "$INSTALL_DIR/lib/cmake/cJSON/cJSONConfigVersion.cmake"
expect_file "$INSTALL_DIR/lib/cmake/cJSON/cjson.cmake"
expect_file "$INSTALL_DIR/lib/cmake/cJSON/cjson_utils.cmake"
expect_file "$CORE_PC"
expect_file "$UTILS_PC"

CORE_SONAME=$(readelf -d "$CORE_LIB" | awk '/SONAME/ { gsub(/\[|\]/, "", $NF); print $NF; exit }')
UTILS_SONAME=$(readelf -d "$UTILS_LIB" | awk '/SONAME/ { gsub(/\[|\]/, "", $NF); print $NF; exit }')
[[ "$CORE_SONAME" == "libcjson.so.1" ]] || fail "unexpected core SONAME: $CORE_SONAME"
[[ "$UTILS_SONAME" == "libcjson_utils.so.1" ]] || fail "unexpected utils SONAME: $UTILS_SONAME"

readelf -d "$UTILS_LIB" | grep -F 'Shared library: [libcjson.so.1]' >/dev/null \
    || fail "libcjson_utils.so.1.7.17 does not depend on libcjson.so.1"

diff -u <(expected_symbols core) <(actual_symbols "$CORE_LIB") \
    || fail "core export set does not match debian/libcjson1.symbols"
diff -u <(expected_symbols utils) <(actual_symbols "$UTILS_LIB") \
    || fail "utils export set does not match debian/libcjson1.symbols"

expect_contains "includedir=${INSTALL_DIR}/include" "$CORE_PC"
expect_contains 'Cflags: -I${includedir} -I${includedir}/cjson' "$CORE_PC"
expect_contains 'Libs: -L${libdir} -lcjson' "$CORE_PC"
expect_contains "includedir=${INSTALL_DIR}/include" "$UTILS_PC"
expect_contains 'Cflags: -I${includedir} -I${includedir}/cjson' "$UTILS_PC"
expect_contains "Requires: libcjson" "$UTILS_PC"

cat >"$CONSUMER_DIR/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(cjson_abi_check LANGUAGES C)
list(APPEND CMAKE_PREFIX_PATH "${INSTALL_DIR}")
find_package(cJSON CONFIG REQUIRED)
EOF

cmake -S "$CONSUMER_DIR" -B "$CONSUMER_DIR/build" >/dev/null

printf 'check-abi: ok\n'
