set(CMAKE_LEGACY_CYGWIN_WIN32 0)
cmake_minimum_required(VERSION 3.16)

project(cJSON
    VERSION 1.7.17
    LANGUAGES C)

cmake_policy(SET CMP0054 NEW)

include(CheckCCompilerFlag)
include(GNUInstallDirs)

set(CJSON_VERSION_SO 1)
set(CJSON_UTILS_VERSION_SO 1)
set(CJSON_LIB cjson)
set(CJSON_UTILS_LIB cjson_utils)

set(custom_compiler_flags)

option(ENABLE_CUSTOM_COMPILER_FLAGS "Enables custom compiler flags" ON)
if(ENABLE_CUSTOM_COMPILER_FLAGS)
    if(("${CMAKE_C_COMPILER_ID}" STREQUAL "Clang") OR ("${CMAKE_C_COMPILER_ID}" STREQUAL "GNU"))
        list(APPEND custom_compiler_flags
            -std=c89
            -pedantic
            -Wall
            -Wextra
            -Werror
            -Wstrict-prototypes
            -Wwrite-strings
            -Wshadow
            -Winit-self
            -Wcast-align
            -Wformat=2
            -Wmissing-prototypes
            -Wstrict-overflow=2
            -Wcast-qual
            -Wundef
            -Wswitch-default
            -Wconversion
            -Wc++-compat
            -fstack-protector-strong
            -Wcomma
            -Wdouble-promotion
            -Wparentheses
            -Wformat-overflow
            -Wunused-macros
            -Wmissing-variable-declarations
            -Wused-but-marked-unused
            -Wswitch-enum
        )
    elseif("${CMAKE_C_COMPILER_ID}" STREQUAL "MSVC")
        list(APPEND custom_compiler_flags
            /GS
            /Za
            /sdl
            /W4
            /wd4001
            /D_CRT_SECURE_NO_WARNINGS
        )
    endif()
endif()

option(ENABLE_SANITIZERS "Enables AddressSanitizer and UndefinedBehaviorSanitizer." OFF)
if(ENABLE_SANITIZERS)
    list(APPEND custom_compiler_flags
        -fno-omit-frame-pointer
        -fsanitize=address
        -fsanitize=undefined
        -fsanitize=float-cast-overflow
        -fsanitize-address-use-after-scope
        -fsanitize=integer
        -fno-sanitize-recover
    )
endif()

option(ENABLE_SAFE_STACK "Enables the SafeStack instrumentation pass by the Code Pointer Integrity Project" OFF)
if(ENABLE_SAFE_STACK)
    if(ENABLE_SANITIZERS)
        message(FATAL_ERROR "ENABLE_SAFE_STACK cannot be used in combination with ENABLE_SANITIZERS")
    endif()
    list(APPEND custom_compiler_flags -fsanitize=safe-stack)
endif()

option(ENABLE_PUBLIC_SYMBOLS "Export library symbols." ON)
option(ENABLE_HIDDEN_SYMBOLS "Hide library symbols." OFF)
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(ENABLE_TARGET_EXPORT "Enable exporting of CMake targets. Disable when it causes problems!" ON)
option(BUILD_SHARED_AND_STATIC_LIBS "Build both shared and static libraries" OFF)
option(CJSON_OVERRIDE_BUILD_SHARED_LIBS "Override BUILD_SHARED_LIBS with CJSON_BUILD_SHARED_LIBS" OFF)
option(CJSON_BUILD_SHARED_LIBS "Overrides BUILD_SHARED_LIBS if CJSON_OVERRIDE_BUILD_SHARED_LIBS is enabled" ON)
option(ENABLE_CJSON_VERSION_SO "Enables cJSON so version" ON)
option(ENABLE_CJSON_UTILS "Enable building the cJSON_Utils library." OFF)
option(ENABLE_CJSON_TEST "Enable building cJSON test" ON)
option(ENABLE_VALGRIND "Enable the valgrind memory checker for the tests." OFF)
option(ENABLE_CJSON_UNINSTALL "Enable creating uninstall target" ON)
option(ENABLE_LOCALES "Enable the use of locales" ON)

foreach(compiler_flag ${custom_compiler_flags})
    string(REGEX REPLACE "[^a-zA-Z0-9]" "" current_variable "${compiler_flag}")
    check_c_compiler_flag("${compiler_flag}" "FLAG_SUPPORTED_${current_variable}")
    if(FLAG_SUPPORTED_${current_variable})
        add_compile_options("${compiler_flag}")
    endif()
endforeach()

if(ENABLE_LOCALES)
    add_compile_definitions(ENABLE_LOCALES)
endif()

if((CJSON_OVERRIDE_BUILD_SHARED_LIBS AND CJSON_BUILD_SHARED_LIBS) OR ((NOT CJSON_OVERRIDE_BUILD_SHARED_LIBS) AND BUILD_SHARED_LIBS))
    set(CJSON_PRIMARY_LIBRARY_TYPE SHARED)
else()
    set(CJSON_PRIMARY_LIBRARY_TYPE STATIC)
endif()

if(BUILD_SHARED_AND_STATIC_LIBS)
    set(CJSON_INSTALL_SHARED ON)
    set(CJSON_INSTALL_STATIC ON)
elseif(CJSON_PRIMARY_LIBRARY_TYPE STREQUAL "SHARED")
    set(CJSON_INSTALL_SHARED ON)
    set(CJSON_INSTALL_STATIC OFF)
else()
    set(CJSON_INSTALL_SHARED OFF)
    set(CJSON_INSTALL_STATIC ON)
endif()

if(CMAKE_BUILD_TYPE MATCHES "^[Rr]elease$|RelWithDebInfo|MinSizeRel")
    set(CJSON_CARGO_PROFILE release)
    set(CJSON_CARGO_ARGS --release)
else()
    set(CJSON_CARGO_PROFILE debug)
    set(CJSON_CARGO_ARGS)
endif()

set(CJSON_CARGO_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo-target")
set(CJSON_CARGO_PROFILE_DIR "${CJSON_CARGO_TARGET_DIR}/${CJSON_CARGO_PROFILE}")

set(CJSON_CORE_SHARED_OUTPUT "${CJSON_CARGO_PROFILE_DIR}/libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(CJSON_CORE_STATIC_OUTPUT "${CJSON_CARGO_PROFILE_DIR}/libcjson${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(CJSON_UTILS_SHARED_OUTPUT "${CJSON_CARGO_PROFILE_DIR}/libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(CJSON_UTILS_STATIC_OUTPUT "${CJSON_CARGO_PROFILE_DIR}/libcjson_utils${CMAKE_STATIC_LIBRARY_SUFFIX}")

if(ENABLE_CJSON_VERSION_SO)
    set(CJSON_SHARED_SONAME "libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}.${CJSON_VERSION_SO}")
    set(CJSON_SHARED_VERSIONED_NAME "libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}.${PROJECT_VERSION}")
    set(CJSON_UTILS_SHARED_SONAME "libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}.${CJSON_UTILS_VERSION_SO}")
    set(CJSON_UTILS_SHARED_VERSIONED_NAME "libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}.${PROJECT_VERSION}")
else()
    set(CJSON_SHARED_SONAME "libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}")
    set(CJSON_SHARED_VERSIONED_NAME "libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}")
    set(CJSON_UTILS_SHARED_SONAME "libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}")
    set(CJSON_UTILS_SHARED_VERSIONED_NAME "libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}")
endif()

set(CJSON_CORE_EXPORT_MAP)
set(CJSON_UTILS_EXPORT_MAP)
if(CJSON_INSTALL_SHARED AND ENABLE_PUBLIC_SYMBOLS)
    set(CJSON_CORE_EXPORT_MAP "${CMAKE_CURRENT_SOURCE_DIR}/abi/libcjson.map")
endif()
if(CJSON_INSTALL_SHARED AND ENABLE_CJSON_UTILS AND ENABLE_PUBLIC_SYMBOLS)
    set(CJSON_UTILS_EXPORT_MAP "${CMAKE_CURRENT_SOURCE_DIR}/abi/libcjson_utils.map")
endif()

add_custom_command(
    OUTPUT "${CJSON_CORE_SHARED_OUTPUT}" "${CJSON_CORE_STATIC_OUTPUT}"
    COMMAND "${CMAKE_COMMAND}" -E env
        "CARGO_TARGET_DIR=${CJSON_CARGO_TARGET_DIR}"
        "CJSON_ENABLE_LOCALES=$<IF:$<BOOL:${ENABLE_LOCALES}>,ON,OFF>"
        "CJSON_CORE_EXPORT_MAP=${CJSON_CORE_EXPORT_MAP}"
        "CJSON_SONAME=${CJSON_SHARED_SONAME}"
        cargo build ${CJSON_CARGO_ARGS}
            --manifest-path "${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml"
            -p safe-libcjson
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml"
        "${CMAKE_CURRENT_SOURCE_DIR}/abi/libcjson.map"
        "${CMAKE_CURRENT_SOURCE_DIR}/crates/libcjson/Cargo.toml"
        "${CMAKE_CURRENT_SOURCE_DIR}/crates/libcjson/build.rs"
        "${CMAKE_CURRENT_SOURCE_DIR}/crates/libcjson/src/lib.rs"
    VERBATIM
)

add_custom_target(cjson-core-artifacts ALL
    DEPENDS "${CJSON_CORE_SHARED_OUTPUT}" "${CJSON_CORE_STATIC_OUTPUT}")

if(ENABLE_CJSON_UTILS)
    add_custom_command(
        OUTPUT "${CJSON_UTILS_SHARED_OUTPUT}" "${CJSON_UTILS_STATIC_OUTPUT}"
        COMMAND "${CMAKE_COMMAND}" -E env
            "CARGO_TARGET_DIR=${CJSON_CARGO_TARGET_DIR}"
            "CJSON_CORE_LIBRARY_DIR=${CJSON_CARGO_PROFILE_DIR}"
            "CJSON_UTILS_EXPORT_MAP=${CJSON_UTILS_EXPORT_MAP}"
            "CJSON_UTILS_SONAME=${CJSON_UTILS_SHARED_SONAME}"
            cargo build ${CJSON_CARGO_ARGS}
                --manifest-path "${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml"
                -p safe-libcjson-utils
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        DEPENDS
            "${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml"
            "${CMAKE_CURRENT_SOURCE_DIR}/abi/libcjson_utils.map"
            "${CMAKE_CURRENT_SOURCE_DIR}/crates/libcjson_utils/Cargo.toml"
            "${CMAKE_CURRENT_SOURCE_DIR}/crates/libcjson_utils/build.rs"
            "${CMAKE_CURRENT_SOURCE_DIR}/crates/libcjson_utils/src/lib.rs"
            "${CJSON_CORE_SHARED_OUTPUT}"
        VERBATIM
    )

    add_custom_target(cjson-utils-artifacts ALL
        DEPENDS "${CJSON_UTILS_SHARED_OUTPUT}" "${CJSON_UTILS_STATIC_OUTPUT}")
    add_dependencies(cjson-utils-artifacts cjson-core-artifacts)
endif()

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/library_config/libcjson.pc.in"
    "${CMAKE_CURRENT_BINARY_DIR}/libcjson.pc"
    @ONLY)

if(ENABLE_CJSON_UTILS)
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/library_config/libcjson_utils.pc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/libcjson_utils.pc"
        @ONLY)
endif()

set(CJSON_CORE_TARGET_EXPORT_CONTENT
"get_filename_component(_IMPORT_PREFIX \"\${CMAKE_CURRENT_LIST_DIR}/../../..\" ABSOLUTE)\n")
if(CJSON_INSTALL_SHARED)
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        "if(NOT TARGET cjson)\n"
        "  add_library(cjson SHARED IMPORTED)\n"
        "  set_target_properties(cjson PROPERTIES\n"
        "    IMPORTED_LOCATION \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_LIBDIR}/libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}\"\n"
        "    IMPORTED_SONAME \"${CJSON_SHARED_SONAME}\"\n"
        "    INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_INCLUDEDIR}\"\n")
    if(NOT WIN32)
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
            "    INTERFACE_LINK_LIBRARIES \"m\"\n")
    endif()
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        "  )\n"
        "endif()\n")
endif()
if(CJSON_INSTALL_STATIC)
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        "if(NOT TARGET cjson")
    if(BUILD_SHARED_AND_STATIC_LIBS)
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT "-static")
    endif()
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        ")\n"
        "  add_library(")
    if(BUILD_SHARED_AND_STATIC_LIBS)
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT "cjson-static")
    else()
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT "cjson")
    endif()
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        " STATIC IMPORTED)\n"
        "  set_target_properties(")
    if(BUILD_SHARED_AND_STATIC_LIBS)
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT "cjson-static")
    else()
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT "cjson")
    endif()
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        " PROPERTIES\n"
        "    IMPORTED_LOCATION \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_LIBDIR}/libcjson${CMAKE_STATIC_LIBRARY_SUFFIX}\"\n"
        "    INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_INCLUDEDIR}\"\n")
    if(NOT WIN32)
        string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
            "    INTERFACE_LINK_LIBRARIES \"m\"\n")
    endif()
    string(APPEND CJSON_CORE_TARGET_EXPORT_CONTENT
        "  )\n"
        "endif()\n")
endif()

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/cjson.cmake" "${CJSON_CORE_TARGET_EXPORT_CONTENT}")

if(ENABLE_CJSON_UTILS)
    set(CJSON_UTILS_TARGET_EXPORT_CONTENT
"get_filename_component(_IMPORT_PREFIX \"\${CMAKE_CURRENT_LIST_DIR}/../../..\" ABSOLUTE)\n")
    if(CJSON_INSTALL_SHARED)
        string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT
            "if(NOT TARGET cjson_utils)\n"
            "  add_library(cjson_utils SHARED IMPORTED)\n"
            "  set_target_properties(cjson_utils PROPERTIES\n"
            "    IMPORTED_LOCATION \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_LIBDIR}/libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}\"\n"
            "    IMPORTED_SONAME \"${CJSON_UTILS_SHARED_SONAME}\"\n"
            "    INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_INCLUDEDIR}\"\n"
            "    INTERFACE_LINK_LIBRARIES \"cjson\"\n"
            "  )\n"
            "endif()\n")
    endif()
    if(CJSON_INSTALL_STATIC)
        string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT
            "if(NOT TARGET ")
        if(BUILD_SHARED_AND_STATIC_LIBS)
            string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT "cjson_utils-static")
        else()
            string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT "cjson_utils")
        endif()
        string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT
            ")\n"
            "  add_library(")
        if(BUILD_SHARED_AND_STATIC_LIBS)
            string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT "cjson_utils-static")
        else()
            string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT "cjson_utils")
        endif()
        string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT
            " STATIC IMPORTED)\n"
            "  set_target_properties(")
        if(BUILD_SHARED_AND_STATIC_LIBS)
            string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT "cjson_utils-static")
        else()
            string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT "cjson_utils")
        endif()
        string(APPEND CJSON_UTILS_TARGET_EXPORT_CONTENT
            " PROPERTIES\n"
            "    IMPORTED_LOCATION \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_LIBDIR}/libcjson_utils${CMAKE_STATIC_LIBRARY_SUFFIX}\"\n"
            "    INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/${CMAKE_INSTALL_INCLUDEDIR}\"\n"
            "    INTERFACE_LINK_LIBRARIES \"cjson\"\n"
            "  )\n"
            "endif()\n")
    endif()
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/cjson_utils.cmake" "${CJSON_UTILS_TARGET_EXPORT_CONTENT}")
endif()

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/library_config/cJSONConfig.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cJSONConfig.cmake"
    @ONLY)
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/library_config/cJSONConfigVersion.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cJSONConfigVersion.cmake"
    @ONLY)

install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/include/cjson/cJSON.h"
    DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/cjson")
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/libcjson.pc"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")

if(CJSON_INSTALL_SHARED)
    install(FILES
        "${CJSON_CORE_SHARED_OUTPUT}"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        RENAME "${CJSON_SHARED_VERSIONED_NAME}")
    if(ENABLE_CJSON_VERSION_SO)
        install(FILES
            "${CJSON_CORE_SHARED_OUTPUT}"
            DESTINATION "${CMAKE_INSTALL_LIBDIR}"
            RENAME "${CJSON_SHARED_SONAME}")
    endif()
    install(FILES
        "${CJSON_CORE_SHARED_OUTPUT}"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        RENAME "libcjson${CMAKE_SHARED_LIBRARY_SUFFIX}")
endif()

if(CJSON_INSTALL_STATIC)
    install(FILES
        "${CJSON_CORE_STATIC_OUTPUT}"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}")
endif()

if(ENABLE_CJSON_UTILS)
    install(FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/include/cjson/cJSON_Utils.h"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/cjson")
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/libcjson_utils.pc"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")

    if(CJSON_INSTALL_SHARED)
        install(FILES
            "${CJSON_UTILS_SHARED_OUTPUT}"
            DESTINATION "${CMAKE_INSTALL_LIBDIR}"
            RENAME "${CJSON_UTILS_SHARED_VERSIONED_NAME}")
        if(ENABLE_CJSON_VERSION_SO)
            install(FILES
                "${CJSON_UTILS_SHARED_OUTPUT}"
                DESTINATION "${CMAKE_INSTALL_LIBDIR}"
                RENAME "${CJSON_UTILS_SHARED_SONAME}")
        endif()
        install(FILES
            "${CJSON_UTILS_SHARED_OUTPUT}"
            DESTINATION "${CMAKE_INSTALL_LIBDIR}"
            RENAME "libcjson_utils${CMAKE_SHARED_LIBRARY_SUFFIX}")
    endif()

    if(CJSON_INSTALL_STATIC)
        install(FILES
            "${CJSON_UTILS_STATIC_OUTPUT}"
            DESTINATION "${CMAKE_INSTALL_LIBDIR}")
    endif()
endif()

if(ENABLE_TARGET_EXPORT)
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/cJSONConfig.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/cJSONConfigVersion.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/cjson.cmake"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/cJSON")
    if(ENABLE_CJSON_UTILS)
        install(FILES
            "${CMAKE_CURRENT_BINARY_DIR}/cjson_utils.cmake"
            DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/cJSON")
    endif()
endif()

if(ENABLE_CJSON_UNINSTALL)
    add_custom_target(uninstall
        COMMAND "${CMAKE_COMMAND}" -P "${PROJECT_SOURCE_DIR}/library_config/uninstall.cmake")
endif()

if(ENABLE_CJSON_TEST)
    enable_testing()
endif()

add_subdirectory(tests)
