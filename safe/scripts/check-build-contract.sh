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
