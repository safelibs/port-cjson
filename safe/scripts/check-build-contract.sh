#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    printf 'check-build-contract: %s\n' "$*" >&2
    exit 1
}

expect_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

expect_absent() {
    [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

run_case() {
    local name=$1
    local shared=$2
    local static=$3
    shift 3

    local build_dir="$WORK_DIR/$name-build"
    local install_dir="$WORK_DIR/$name-install"

    cmake -S "$ROOT_DIR" -B "$build_dir" \
        -DENABLE_CJSON_UTILS=ON \
        -DENABLE_CJSON_TEST=OFF \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        "$@" >/dev/null
    cmake --build "$build_dir" >/dev/null
    cmake --install "$build_dir" >/dev/null

    if [[ "$shared" == "yes" ]]; then
        expect_file "$install_dir/lib/libcjson.so"
        expect_file "$install_dir/lib/libcjson.so.1"
        expect_file "$install_dir/lib/libcjson.so.1.7.17"
        expect_file "$install_dir/lib/libcjson_utils.so"
        expect_file "$install_dir/lib/libcjson_utils.so.1"
        expect_file "$install_dir/lib/libcjson_utils.so.1.7.17"
    else
        expect_absent "$install_dir/lib/libcjson.so"
        expect_absent "$install_dir/lib/libcjson.so.1"
        expect_absent "$install_dir/lib/libcjson.so.1.7.17"
        expect_absent "$install_dir/lib/libcjson_utils.so"
        expect_absent "$install_dir/lib/libcjson_utils.so.1"
        expect_absent "$install_dir/lib/libcjson_utils.so.1.7.17"
    fi

    if [[ "$static" == "yes" ]]; then
        expect_file "$install_dir/lib/libcjson.a"
        expect_file "$install_dir/lib/libcjson_utils.a"
    else
        expect_absent "$install_dir/lib/libcjson.a"
        expect_absent "$install_dir/lib/libcjson_utils.a"
    fi
}

run_case default yes no
run_case plain-static no yes \
    -DBUILD_SHARED_LIBS=OFF \
    -DCJSON_OVERRIDE_BUILD_SHARED_LIBS=OFF
run_case override-static no yes \
    -DCJSON_OVERRIDE_BUILD_SHARED_LIBS=ON \
    -DCJSON_BUILD_SHARED_LIBS=OFF
run_case shared-and-static yes yes \
    -DBUILD_SHARED_AND_STATIC_LIBS=ON

HIDDEN_BUILD="$WORK_DIR/hidden-build"
cmake -S "$ROOT_DIR" -B "$HIDDEN_BUILD" \
    -DENABLE_CJSON_UTILS=ON \
    -DENABLE_CJSON_TEST=OFF \
    -DENABLE_HIDDEN_SYMBOLS=ON >/dev/null
cmake --build "$HIDDEN_BUILD" >/dev/null
if nm -D --defined-only "$HIDDEN_BUILD/cargo-target/debug/libcjson.so" | awk '{print $3}' | grep -q '^cJSON_'; then
    fail "ENABLE_HIDDEN_SYMBOLS should hide cJSON shared-library exports"
fi
if nm -D --defined-only "$HIDDEN_BUILD/cargo-target/debug/libcjson_utils.so" | awk '{print $3}' | grep -q '^cJSONUtils_'; then
    fail "ENABLE_HIDDEN_SYMBOLS should hide cJSON utils shared-library exports"
fi

SHARED_STATIC_INSTALL="$WORK_DIR/shared-and-static-install"
SHARED_STATIC_CONSUMER="$WORK_DIR/shared-and-static-consumer"
mkdir -p "$SHARED_STATIC_CONSUMER"
cat >"$SHARED_STATIC_CONSUMER/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(cjson_shared_static_contract LANGUAGES C)
list(APPEND CMAKE_PREFIX_PATH "${SHARED_STATIC_INSTALL}")
find_package(cJSON CONFIG REQUIRED)
get_target_property(utils_static_links cjson_utils-static INTERFACE_LINK_LIBRARIES)
if(NOT utils_static_links STREQUAL "cjson-static")
    message(FATAL_ERROR "cjson_utils-static should link to cjson-static, got: \${utils_static_links}")
endif()
get_target_property(core_static_path cjson-static IMPORTED_LOCATION)
if(NOT core_static_path MATCHES "libcjson\\\\.a$")
    message(FATAL_ERROR "cjson-static should resolve to libcjson.a, got: \${core_static_path}")
endif()
EOF
cmake -S "$SHARED_STATIC_CONSUMER" -B "$SHARED_STATIC_CONSUMER/build" >/dev/null

MULTIARCH_BUILD="$WORK_DIR/multiarch-build"
MULTIARCH_INSTALL="$WORK_DIR/multiarch-install"
MULTIARCH_CONSUMER="$WORK_DIR/multiarch-consumer"

cmake -S "$ROOT_DIR" -B "$MULTIARCH_BUILD" \
    -DENABLE_CJSON_UTILS=ON \
    -DENABLE_CJSON_TEST=OFF \
    -DCMAKE_INSTALL_PREFIX="$MULTIARCH_INSTALL" \
    -DCMAKE_INSTALL_LIBDIR=lib/x86_64-linux-gnu >/dev/null
cmake --build "$MULTIARCH_BUILD" >/dev/null
cmake --install "$MULTIARCH_BUILD" >/dev/null

mkdir -p "$MULTIARCH_CONSUMER"
cat >"$MULTIARCH_CONSUMER/core_root.c" <<'EOF'
#include <cJSON.h>

int main(void) {
    return cJSON_Version() == 0;
}
EOF
cat >"$MULTIARCH_CONSUMER/core_nested.c" <<'EOF'
#include <cjson/cJSON.h>

int main(void) {
    return cJSON_Version() == 0;
}
EOF
cat >"$MULTIARCH_CONSUMER/utils_root.c" <<'EOF'
#include <cJSON_Utils.h>

int main(void) {
    cJSONUtils_SortObject(0);
    return 0;
}
EOF
cat >"$MULTIARCH_CONSUMER/utils_nested.c" <<'EOF'
#include <cjson/cJSON_Utils.h>

int main(void) {
    cJSONUtils_SortObject(0);
    return 0;
}
EOF
cat >"$MULTIARCH_CONSUMER/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.16)
project(cjson_multiarch_contract LANGUAGES C)
list(APPEND CMAKE_PREFIX_PATH "${MULTIARCH_INSTALL}")
find_package(cJSON CONFIG REQUIRED)
get_target_property(core_includes cjson INTERFACE_INCLUDE_DIRECTORIES)
list(FIND core_includes "${MULTIARCH_INSTALL}/include" core_include_idx)
if(core_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson should expose ${MULTIARCH_INSTALL}/include, got: \${core_includes}")
endif()
list(FIND core_includes "${MULTIARCH_INSTALL}/include/cjson" core_compat_include_idx)
if(core_compat_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson should expose ${MULTIARCH_INSTALL}/include/cjson, got: \${core_includes}")
endif()
get_target_property(utils_includes cjson_utils INTERFACE_INCLUDE_DIRECTORIES)
list(FIND utils_includes "${MULTIARCH_INSTALL}/include" utils_include_idx)
if(utils_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson_utils should expose ${MULTIARCH_INSTALL}/include, got: \${utils_includes}")
endif()
list(FIND utils_includes "${MULTIARCH_INSTALL}/include/cjson" utils_compat_include_idx)
if(utils_compat_include_idx EQUAL -1)
    message(FATAL_ERROR "cjson_utils should expose ${MULTIARCH_INSTALL}/include/cjson, got: \${utils_includes}")
endif()
add_executable(core_root core_root.c)
target_link_libraries(core_root PRIVATE cjson)
add_executable(core_nested core_nested.c)
target_link_libraries(core_nested PRIVATE cjson)
add_executable(utils_root utils_root.c)
target_link_libraries(utils_root PRIVATE cjson_utils)
add_executable(utils_nested utils_nested.c)
target_link_libraries(utils_nested PRIVATE cjson_utils)
EOF
cmake -S "$MULTIARCH_CONSUMER" -B "$MULTIARCH_CONSUMER/build" >/dev/null
cmake --build "$MULTIARCH_CONSUMER/build" >/dev/null

UNINSTALL_BUILD="$WORK_DIR/uninstall-build"
UNINSTALL_INSTALL="$WORK_DIR/uninstall-install"

cmake -S "$ROOT_DIR" -B "$UNINSTALL_BUILD" \
    -DENABLE_CJSON_UTILS=ON \
    -DENABLE_CJSON_TEST=OFF \
    -DENABLE_CJSON_UNINSTALL=ON \
    -DCMAKE_INSTALL_PREFIX="$UNINSTALL_INSTALL" >/dev/null
cmake --build "$UNINSTALL_BUILD" >/dev/null
cmake --install "$UNINSTALL_BUILD" >/dev/null
expect_file "$UNINSTALL_INSTALL/lib/libcjson.so"
cmake --build "$UNINSTALL_BUILD" --target uninstall >/dev/null
expect_absent "$UNINSTALL_INSTALL/lib/libcjson.so"
expect_absent "$UNINSTALL_INSTALL/lib/libcjson.so.1"
expect_absent "$UNINSTALL_INSTALL/lib/libcjson.so.1.7.17"
expect_absent "$UNINSTALL_INSTALL/lib/libcjson_utils.so"
expect_absent "$UNINSTALL_INSTALL/lib/libcjson_utils.so.1"
expect_absent "$UNINSTALL_INSTALL/lib/libcjson_utils.so.1.7.17"
expect_absent "$UNINSTALL_INSTALL/include/cjson/cJSON.h"
expect_absent "$UNINSTALL_INSTALL/include/cjson/cJSON_Utils.h"

printf 'check-build-contract: ok\n'
