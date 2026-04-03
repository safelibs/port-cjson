/*
  Copyright (c) 2009-2017 Dave Gamble and cJSON contributors

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
*/

#include "unity/examples/unity_config.h"
#include "unity/src/unity.h"
#include "common.h"

#define CJSON_TEST_STRINGIFY_HELPER(value) #value
#define CJSON_TEST_STRINGIFY(value) CJSON_TEST_STRINGIFY_HELPER(value)

#if defined(__clang__)
#define CJSON_TEST_DISABLE_FLOAT_CONVERSION_WARNING \
    _Pragma("clang diagnostic push") \
    _Pragma("clang diagnostic ignored \"-Wfloat-conversion\"")
#define CJSON_TEST_RESTORE_FLOAT_CONVERSION_WARNING \
    _Pragma("clang diagnostic pop")
#elif defined(__GNUC__)
#define CJSON_TEST_DISABLE_FLOAT_CONVERSION_WARNING \
    _Pragma("GCC diagnostic push") \
    _Pragma("GCC diagnostic ignored \"-Wfloat-conversion\"")
#define CJSON_TEST_RESTORE_FLOAT_CONVERSION_WARNING \
    _Pragma("GCC diagnostic pop")
#else
#define CJSON_TEST_DISABLE_FLOAT_CONVERSION_WARNING
#define CJSON_TEST_RESTORE_FLOAT_CONVERSION_WARNING
#endif

static void cjson_version_should_match_header_version_macros(void)
{
    const char *version = cJSON_Version();
    const char expected[] =
        CJSON_TEST_STRINGIFY(CJSON_VERSION_MAJOR) "."
        CJSON_TEST_STRINGIFY(CJSON_VERSION_MINOR) "."
        CJSON_TEST_STRINGIFY(CJSON_VERSION_PATCH);

    TEST_ASSERT_NOT_NULL(version);
    TEST_ASSERT_EQUAL_STRING(expected, version);
}

static void cjson_create_true_should_create_a_true_boolean(void)
{
    cJSON *item = cJSON_CreateTrue();
    char *printed = NULL;

    TEST_ASSERT_NOT_NULL(item);
    TEST_ASSERT_TRUE(cJSON_IsTrue(item));
    TEST_ASSERT_TRUE(cJSON_IsBool(item));

    printed = cJSON_PrintUnformatted(item);
    TEST_ASSERT_NOT_NULL(printed);
    TEST_ASSERT_EQUAL_STRING("true", printed);

    cJSON_free(printed);
    cJSON_Delete(item);
}

static void cjson_create_bool_should_create_requested_boolean_value(void)
{
    cJSON *true_item = cJSON_CreateBool(true);
    cJSON *false_item = cJSON_CreateBool(false);
    char *printed_true = NULL;
    char *printed_false = NULL;

    TEST_ASSERT_NOT_NULL(true_item);
    TEST_ASSERT_NOT_NULL(false_item);
    TEST_ASSERT_TRUE(cJSON_IsTrue(true_item));
    TEST_ASSERT_TRUE(cJSON_IsFalse(false_item));
    TEST_ASSERT_TRUE(cJSON_IsBool(true_item));
    TEST_ASSERT_TRUE(cJSON_IsBool(false_item));

    printed_true = cJSON_PrintUnformatted(true_item);
    printed_false = cJSON_PrintUnformatted(false_item);
    TEST_ASSERT_NOT_NULL(printed_true);
    TEST_ASSERT_NOT_NULL(printed_false);
    TEST_ASSERT_EQUAL_STRING("true", printed_true);
    TEST_ASSERT_EQUAL_STRING("false", printed_false);

    cJSON_free(printed_false);
    cJSON_free(printed_true);
    cJSON_Delete(false_item);
    cJSON_Delete(true_item);
}

static void cjson_parse_with_length_opts_should_parse_a_bounded_buffer(void)
{
    const char input[] = "{}ignored";
    const char *parse_end = NULL;
    cJSON *item = cJSON_ParseWithLengthOpts(input, 2, &parse_end, false);

    TEST_ASSERT_NOT_NULL(item);
    TEST_ASSERT_TRUE(cJSON_IsObject(item));
    TEST_ASSERT_EQUAL_INT(0, cJSON_GetArraySize(item));
    TEST_ASSERT_EQUAL_PTR(input + 2, parse_end);

    cJSON_Delete(item);
}

static void cjson_parse_with_length_opts_should_report_zero_length_failure_at_start(void)
{
    const char input[] = "{}";
    const char *parse_end = input + 1;

    TEST_ASSERT_NULL(cJSON_ParseWithLengthOpts(input, 0, &parse_end, false));
    TEST_ASSERT_EQUAL_PTR(input, parse_end);
    TEST_ASSERT_EQUAL_PTR(input, cJSON_GetErrorPtr());
}

static void cjson_parse_with_length_opts_should_require_null_termination_within_length(void)
{
    const char input[] = "{}";
    const char *parse_end = NULL;
    cJSON *item = cJSON_ParseWithLengthOpts(input, 2, &parse_end, true);

    TEST_ASSERT_NULL(item);
    TEST_ASSERT_EQUAL_PTR(input + 1, parse_end);
    TEST_ASSERT_EQUAL_PTR(input + 1, cJSON_GetErrorPtr());

    item = cJSON_ParseWithLengthOpts(input, sizeof(input), &parse_end, true);
    TEST_ASSERT_NOT_NULL(item);
    TEST_ASSERT_TRUE(cJSON_IsObject(item));
    TEST_ASSERT_EQUAL_PTR(input + 2, parse_end);

    cJSON_Delete(item);
}

static void cjson_set_int_value_should_update_number_value_and_printed_output(void)
{
    cJSON *item = cJSON_CreateNumber(1.5);
    char *printed = NULL;

    TEST_ASSERT_NOT_NULL(item);

    CJSON_TEST_DISABLE_FLOAT_CONVERSION_WARNING
    cJSON_SetIntValue(item, -42);
    CJSON_TEST_RESTORE_FLOAT_CONVERSION_WARNING
    TEST_ASSERT_EQUAL_DOUBLE(-42.0, cJSON_GetNumberValue(item));

    printed = cJSON_PrintUnformatted(item);
    TEST_ASSERT_NOT_NULL(printed);
    TEST_ASSERT_EQUAL_STRING("-42", printed);

    cJSON_free(printed);
    cJSON_Delete(item);
}

static void cjson_print_buffered_should_match_standard_print_functions(void)
{
    const char input[] = "{\"message\":\"ok\",\"values\":[1,true,false,null]}";
    cJSON *item = cJSON_Parse(input);
    char *formatted = NULL;
    char *formatted_buffered = NULL;
    char *unformatted = NULL;
    char *unformatted_buffered = NULL;

    TEST_ASSERT_NOT_NULL(item);

    formatted = cJSON_Print(item);
    formatted_buffered = cJSON_PrintBuffered(item, 1, true);
    unformatted = cJSON_PrintUnformatted(item);
    unformatted_buffered = cJSON_PrintBuffered(item, 1, false);

    TEST_ASSERT_NOT_NULL(formatted);
    TEST_ASSERT_NOT_NULL(formatted_buffered);
    TEST_ASSERT_NOT_NULL(unformatted);
    TEST_ASSERT_NOT_NULL(unformatted_buffered);
    TEST_ASSERT_EQUAL_STRING(formatted, formatted_buffered);
    TEST_ASSERT_EQUAL_STRING(unformatted, unformatted_buffered);

    cJSON_free(unformatted_buffered);
    cJSON_free(unformatted);
    cJSON_free(formatted_buffered);
    cJSON_free(formatted);
    cJSON_Delete(item);
}

static void cjson_print_preallocated_should_write_output_into_the_supplied_buffer(void)
{
    const char input[] = "{\"name\":\"cjson\",\"count\":2}";
    char formatted_buffer[256];
    char unformatted_buffer[256];
    char too_small_buffer[8];
    cJSON *item = cJSON_Parse(input);
    char *formatted = NULL;
    char *unformatted = NULL;

    TEST_ASSERT_NOT_NULL(item);

    TEST_ASSERT_TRUE(cJSON_PrintPreallocated(item, formatted_buffer, (int)sizeof(formatted_buffer), true));
    TEST_ASSERT_TRUE(cJSON_PrintPreallocated(item, unformatted_buffer, (int)sizeof(unformatted_buffer), false));
    TEST_ASSERT_FALSE(cJSON_PrintPreallocated(item, too_small_buffer, (int)sizeof(too_small_buffer), false));

    formatted = cJSON_Print(item);
    unformatted = cJSON_PrintUnformatted(item);
    TEST_ASSERT_NOT_NULL(formatted);
    TEST_ASSERT_NOT_NULL(unformatted);
    TEST_ASSERT_EQUAL_STRING(formatted, formatted_buffer);
    TEST_ASSERT_EQUAL_STRING(unformatted, unformatted_buffer);

    cJSON_free(unformatted);
    cJSON_free(formatted);
    cJSON_Delete(item);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();

    RUN_TEST(cjson_version_should_match_header_version_macros);
    RUN_TEST(cjson_create_true_should_create_a_true_boolean);
    RUN_TEST(cjson_create_bool_should_create_requested_boolean_value);
    RUN_TEST(cjson_parse_with_length_opts_should_parse_a_bounded_buffer);
    RUN_TEST(cjson_parse_with_length_opts_should_report_zero_length_failure_at_start);
    RUN_TEST(cjson_parse_with_length_opts_should_require_null_termination_within_length);
    RUN_TEST(cjson_set_int_value_should_update_number_value_and_printed_output);
    RUN_TEST(cjson_print_buffered_should_match_standard_print_functions);
    RUN_TEST(cjson_print_preallocated_should_write_output_into_the_supplied_buffer);

    return UNITY_END();
}
