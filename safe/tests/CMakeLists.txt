if(NOT ENABLE_CJSON_TEST)
    return()
endif()

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/inputs")
file(GLOB SAFE_INPUT_FIXTURES "${CMAKE_CURRENT_SOURCE_DIR}/inputs/*")
file(COPY ${SAFE_INPUT_FIXTURES} DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/inputs/")

if(ENABLE_CJSON_UTILS)
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/json-patch-tests")
    file(GLOB SAFE_PATCH_FIXTURES "${CMAKE_CURRENT_SOURCE_DIR}/json-patch-tests/*")
    file(COPY ${SAFE_PATCH_FIXTURES} DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/json-patch-tests/")
endif()

add_library(unity STATIC unity/src/unity.c)
target_include_directories(unity PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/unity/src")

if(FLAG_SUPPORTED_Werror)
    target_compile_options(unity PRIVATE "-Wno-error")
endif()
if(FLAG_SUPPORTED_fvisibilityhidden)
    target_compile_options(unity PRIVATE "-fvisibility=default")
endif()
if(FLAG_SUPPORTED_fsanitizefloatdividebyzero AND (CMAKE_C_COMPILER_ID STREQUAL "GNU"))
    target_compile_options(unity PRIVATE "-fno-sanitize=float-divide-by-zero")
endif()
if(FLAG_SUPPORTED_Wswitchenum)
    target_compile_options(unity PRIVATE "-Wno-switch-enum")
endif()

add_custom_target(check
    COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure)
