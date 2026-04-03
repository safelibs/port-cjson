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

function(add_safe_unity_test test_name source_file)
    add_executable("${test_name}" "${source_file}")
    target_include_directories("${test_name}" PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries("${test_name}" PRIVATE "${CJSON_CORE_SHARED_OUTPUT}" unity)
    if(NOT WIN32)
        target_link_libraries("${test_name}" PRIVATE m)
    endif()
    add_dependencies("${test_name}" cjson-core-artifacts)
    set_target_properties("${test_name}" PROPERTIES BUILD_RPATH "${CJSON_CARGO_PROFILE_DIR}")

    if(MEMORYCHECK_COMMAND)
        add_test(NAME "${test_name}"
            COMMAND "${MEMORYCHECK_COMMAND}" ${MEMORYCHECK_COMMAND_OPTIONS} "${CMAKE_CURRENT_BINARY_DIR}/${test_name}")
    else()
        add_test(NAME "${test_name}"
            COMMAND "./${test_name}")
    endif()
endfunction()

set(core_tree_tests
    cjson_add
    core_layout_smoke
    core_hooks_smoke
)

add_safe_unity_test(cjson_add "${CMAKE_CURRENT_SOURCE_DIR}/cjson_add.c")
add_safe_unity_test(core_layout_smoke "${CMAKE_CURRENT_SOURCE_DIR}/regressions/core_layout_smoke.c")
add_safe_unity_test(core_hooks_smoke "${CMAKE_CURRENT_SOURCE_DIR}/regressions/core_hooks_smoke.c")

add_custom_target(check
    COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure)
add_dependencies(check ${core_tree_tests})
