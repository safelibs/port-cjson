#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_DIR=$(mktemp -d)
CONSUMER_DIR=$(mktemp -d)
TEMP_BUILD_DIR=""

if [ "$#" -gt 1 ]; then
    echo "usage: $0 [safe-build-dir]" >&2
    exit 1
fi

if [ "$#" -eq 1 ]; then
    BUILD_DIR=$(cd "$1" && pwd)
else
    BUILD_DIR=$(mktemp -d)
    TEMP_BUILD_DIR="$BUILD_DIR"
fi

cleanup() {
    if [[ -n "$TEMP_BUILD_DIR" ]]; then
        rm -rf "$TEMP_BUILD_DIR"
    fi
    rm -rf "$INSTALL_DIR" "$CONSUMER_DIR"
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

compile_with_pkg_config() {
    local package=$1
    local source=$2
    local output=$3
    PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
        "${CC:-cc}" "$source" -o "$output" \
        $(PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" pkg-config --cflags --libs "$package")
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
    nm -D --defined-only "$1" | awk 'NF >= 3 { sub(/@.*/, "", $3); print $3 }' | sort -u
}

if [[ -n "$TEMP_BUILD_DIR" ]]; then
    cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
        -DENABLE_CJSON_UTILS=ON \
        -DENABLE_CJSON_TEST=OFF \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" >/dev/null
    cmake --build "$BUILD_DIR" >/dev/null
else
    expect_file "$BUILD_DIR/CMakeCache.txt"
    BUILD_SOURCE_DIR=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$BUILD_DIR/CMakeCache.txt" | tail -n1)
    BUILD_SOURCE_DIR=$(cd "$BUILD_SOURCE_DIR" && pwd)
    [[ "$BUILD_SOURCE_DIR" == "$ROOT_DIR" ]] || fail "build dir $BUILD_DIR was configured for $BUILD_SOURCE_DIR, expected $ROOT_DIR"
fi

cmake --install "$BUILD_DIR" --prefix "$INSTALL_DIR" >/dev/null
EXPECTED_INSTALL_PREFIX="$INSTALL_DIR"

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

expect_contains "includedir=${EXPECTED_INSTALL_PREFIX}/include" "$CORE_PC"
expect_contains 'includedir_cjson=${includedir}/cjson' "$CORE_PC"
expect_contains 'Cflags: -I${includedir} -I${includedir_cjson}' "$CORE_PC"
expect_contains 'Libs: -L${libdir} -lcjson' "$CORE_PC"
expect_contains "includedir=${EXPECTED_INSTALL_PREFIX}/include" "$UTILS_PC"
expect_contains 'includedir_cjson=${includedir}/cjson' "$UTILS_PC"
expect_contains 'Cflags: -I${includedir} -I${includedir_cjson}' "$UTILS_PC"
expect_contains "Requires: libcjson" "$UTILS_PC"

cat >"$CONSUMER_DIR/pkg_core_root.c" <<'EOF'
#include <cJSON.h>

int main(void) {
    return cJSON_Version() == 0;
}
EOF
cat >"$CONSUMER_DIR/pkg_core_nested.c" <<'EOF'
#include <cjson/cJSON.h>

int main(void) {
    return cJSON_Version() == 0;
}
EOF
cat >"$CONSUMER_DIR/pkg_utils_root.c" <<'EOF'
#include <cJSON_Utils.h>

int main(void) {
    cJSONUtils_SortObject(0);
    return 0;
}
EOF
cat >"$CONSUMER_DIR/pkg_utils_nested.c" <<'EOF'
#include <cjson/cJSON_Utils.h>

int main(void) {
    cJSONUtils_SortObject(0);
    return 0;
}
EOF

compile_with_pkg_config libcjson "$CONSUMER_DIR/pkg_core_root.c" "$CONSUMER_DIR/pkg_core_root"
compile_with_pkg_config libcjson "$CONSUMER_DIR/pkg_core_nested.c" "$CONSUMER_DIR/pkg_core_nested"
compile_with_pkg_config libcjson_utils "$CONSUMER_DIR/pkg_utils_root.c" "$CONSUMER_DIR/pkg_utils_root"
compile_with_pkg_config libcjson_utils "$CONSUMER_DIR/pkg_utils_nested.c" "$CONSUMER_DIR/pkg_utils_nested"

cat >"$CONSUMER_DIR/cmake_core_root.c" <<'EOF'
#include <cJSON.h>

int main(void) {
    return cJSON_Version() == 0;
}
EOF
cat >"$CONSUMER_DIR/cmake_core_nested.c" <<'EOF'
#include <cjson/cJSON.h>

int main(void) {
    return cJSON_Version() == 0;
}
EOF
cat >"$CONSUMER_DIR/cmake_utils_root.c" <<'EOF'
#include <cJSON_Utils.h>

int main(void) {
    cJSONUtils_SortObject(0);
    return 0;
}
EOF
cat >"$CONSUMER_DIR/cmake_utils_nested.c" <<'EOF'
#include <cjson/cJSON_Utils.h>

int main(void) {
    cJSONUtils_SortObject(0);
    return 0;
}
EOF

cat >"$CONSUMER_DIR/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(cjson_abi_check LANGUAGES C)
list(APPEND CMAKE_PREFIX_PATH "${INSTALL_DIR}")
find_package(cJSON CONFIG REQUIRED)
get_target_property(core_includes cjson INTERFACE_INCLUDE_DIRECTORIES)
list(FIND core_includes "${INSTALL_DIR}/include" core_include_idx)
if(core_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson should expose ${INSTALL_DIR}/include, got: \${core_includes}")
endif()
list(FIND core_includes "${INSTALL_DIR}/include/cjson" core_compat_include_idx)
if(core_compat_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson should expose ${INSTALL_DIR}/include/cjson, got: \${core_includes}")
endif()
get_target_property(utils_includes cjson_utils INTERFACE_INCLUDE_DIRECTORIES)
list(FIND utils_includes "${INSTALL_DIR}/include" utils_include_idx)
if(utils_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson_utils should expose ${INSTALL_DIR}/include, got: \${utils_includes}")
endif()
list(FIND utils_includes "${INSTALL_DIR}/include/cjson" utils_compat_include_idx)
if(utils_compat_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson_utils should expose ${INSTALL_DIR}/include/cjson, got: \${utils_includes}")
endif()
add_executable(cmake_core_root cmake_core_root.c)
target_link_libraries(cmake_core_root PRIVATE cjson)
add_executable(cmake_core_nested cmake_core_nested.c)
target_link_libraries(cmake_core_nested PRIVATE cjson)
add_executable(cmake_utils_root cmake_utils_root.c)
target_link_libraries(cmake_utils_root PRIVATE cjson_utils)
add_executable(cmake_utils_nested cmake_utils_nested.c)
target_link_libraries(cmake_utils_nested PRIVATE cjson_utils)
EOF

cmake -S "$CONSUMER_DIR" -B "$CONSUMER_DIR/build" >/dev/null
cmake --build "$CONSUMER_DIR/build" >/dev/null

printf 'check-abi: ok\n'
