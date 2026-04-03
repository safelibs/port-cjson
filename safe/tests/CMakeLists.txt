if(NOT ENABLE_CJSON_TEST)
    return()
endif()

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/inputs")
file(GLOB SAFE_INPUT_FIXTURES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/inputs/*")
if(SAFE_INPUT_FIXTURES)
    file(COPY ${SAFE_INPUT_FIXTURES} DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/inputs/")
endif()

if(ENABLE_CJSON_UTILS)
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/json-patch-tests")
    file(GLOB SAFE_PATCH_FIXTURES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/json-patch-tests/*")
    if(SAFE_PATCH_FIXTURES)
        file(COPY ${SAFE_PATCH_FIXTURES} DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/json-patch-tests/")
    endif()
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

option(ENABLE_VALGRIND OFF "Enable the valgrind memory checker for the tests.")
if(ENABLE_VALGRIND)
    find_program(MEMORYCHECK_COMMAND valgrind)
    if("${MEMORYCHECK_COMMAND}" MATCHES "MEMORYCHECK_COMMAND-NOTFOUND")
        message(WARNING "Valgrind couldn't be found.")
        unset(MEMORYCHECK_COMMAND)
    else()
        set(MEMORYCHECK_COMMAND_OPTIONS --trace-children=yes --leak-check=full --error-exitcode=1)
    endif()
endif()

function(add_safe_test test_name)
    add_executable("${test_name}" "${ARGN}")
    target_include_directories("${test_name}" PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries("${test_name}" PRIVATE "${CJSON_CORE_SHARED_OUTPUT}")
    if(NOT WIN32)
        target_link_libraries("${test_name}" PRIVATE m)
    endif()
    add_dependencies("${test_name}" cjson-core-artifacts)
    set_target_properties("${test_name}" PROPERTIES BUILD_RPATH "${CJSON_CARGO_PROFILE_DIR}")

    if(MEMORYCHECK_COMMAND)
        add_test(NAME "${test_name}"
            COMMAND "${MEMORYCHECK_COMMAND}" ${MEMORYCHECK_COMMAND_OPTIONS} "$<TARGET_FILE:${test_name}>")
    else()
        add_test(NAME "${test_name}"
            COMMAND "$<TARGET_FILE:${test_name}>")
    endif()
    set_tests_properties("${test_name}" PROPERTIES WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
endfunction()

function(add_safe_unity_test test_name source_file)
    add_safe_test("${test_name}" "${source_file}")
    target_link_libraries("${test_name}" PRIVATE unity)
    if("${CMAKE_C_COMPILER_ID}" STREQUAL "MSVC")
        target_sources("${test_name}" PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/unity_setup.c")
    endif()
endfunction()

function(add_safe_utils_test test_name source_file)
    add_safe_test("${test_name}" "${source_file}")
    target_link_libraries("${test_name}" PRIVATE "${CJSON_UTILS_SHARED_OUTPUT}")
    add_dependencies("${test_name}" cjson-utils-artifacts)
endfunction()

function(add_safe_unity_utils_test test_name source_file)
    add_safe_utils_test("${test_name}" "${source_file}")
    target_link_libraries("${test_name}" PRIVATE unity)
    if("${CMAKE_C_COMPILER_ID}" STREQUAL "MSVC")
        target_sources("${test_name}" PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/unity_setup.c")
    endif()
endfunction()

set(upstream_non_utils_tests
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

set(regression_tests
    core_layout_smoke
    core_hooks_smoke
    number_cve_2023_26819
    dependents_parse_payloads_smoke
    dependents_roundtrip_shapes_smoke
    dependents_config_roundtrip_smoke
)

set(utils_unity_tests
    json_patch_tests
    old_utils_tests
    misc_utils_tests
)

set(utils_regression_tests
    json_pointer_cve_2025_57052
)

foreach(unity_test ${upstream_non_utils_tests})
    add_safe_unity_test("${unity_test}" "${CMAKE_CURRENT_SOURCE_DIR}/${unity_test}.c")
endforeach()

add_safe_unity_test(core_layout_smoke "${CMAKE_CURRENT_SOURCE_DIR}/regressions/core_layout_smoke.c")
add_safe_unity_test(core_hooks_smoke "${CMAKE_CURRENT_SOURCE_DIR}/regressions/core_hooks_smoke.c")
add_safe_unity_test(number_cve_2023_26819 "${CMAKE_CURRENT_SOURCE_DIR}/regressions/number_cve_2023_26819.c")
add_safe_unity_test(
    dependents_parse_payloads_smoke
    "${CMAKE_CURRENT_SOURCE_DIR}/regressions/dependents_parse_payloads_smoke.c"
)
add_safe_unity_test(
    dependents_roundtrip_shapes_smoke
    "${CMAKE_CURRENT_SOURCE_DIR}/regressions/dependents_roundtrip_shapes_smoke.c"
)
add_safe_unity_test(
    dependents_config_roundtrip_smoke
    "${CMAKE_CURRENT_SOURCE_DIR}/regressions/dependents_config_roundtrip_smoke.c"
)

if(ENABLE_CJSON_UTILS)
    foreach(unity_test ${utils_unity_tests})
        add_safe_unity_utils_test("${unity_test}" "${CMAKE_CURRENT_SOURCE_DIR}/${unity_test}.c")
    endforeach()

    add_safe_unity_utils_test(
        json_pointer_cve_2025_57052
        "${CMAKE_CURRENT_SOURCE_DIR}/regressions/json_pointer_cve_2025_57052.c"
    )
endif()

add_safe_test(cJSON_test "${CMAKE_CURRENT_SOURCE_DIR}/../test.c")
if(FLAG_SUPPORTED_fsanitizefloatdividebyzero)
    target_compile_options(cJSON_test PRIVATE "-fno-sanitize=float-divide-by-zero")
endif()

set(all_safe_tests
    ${upstream_non_utils_tests}
    ${regression_tests}
    cJSON_test
)

if(ENABLE_CJSON_UTILS)
    list(APPEND all_safe_tests
        ${utils_unity_tests}
        ${utils_regression_tests}
    )
endif()

add_custom_target(check
    COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure)
add_dependencies(check ${all_safe_tests})

if(UNIX)
    if(ENABLE_CJSON_UTILS)
        add_test(NAME link_original_tests
            COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/link-original-tests.sh" "${CMAKE_BINARY_DIR}")
        set_tests_properties(link_original_tests PROPERTIES LABELS "compat;relink")
    endif()

    add_test(NAME replay_fuzz_corpus
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/replay-fuzz-corpus.sh" "${CMAKE_BINARY_DIR}")
    set_tests_properties(replay_fuzz_corpus PROPERTIES LABELS "compat;fuzz")
endif()
