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

static void assert_print_array(const char * const expected, const char * const input)
{
    const char *parse_end = NULL;
    cJSON *item = cJSON_ParseWithOpts(input, &parse_end, false);
    char *printed_unformatted = NULL;
    char *printed_formatted = NULL;

    TEST_ASSERT_NOT_NULL_MESSAGE(item, "Failed to parse array.");
    TEST_ASSERT_EQUAL_PTR_MESSAGE(input + strlen(input), parse_end, "Did not parse the whole array.");
    TEST_ASSERT_TRUE_MESSAGE(cJSON_IsArray(item), "Input did not parse as an array.");

    printed_unformatted = cJSON_PrintUnformatted(item);
    TEST_ASSERT_NOT_NULL_MESSAGE(printed_unformatted, "Failed to print unformatted array.");
    TEST_ASSERT_EQUAL_STRING_MESSAGE(input, printed_unformatted, "Unformatted array is not correct.");

    printed_formatted = cJSON_Print(item);
    TEST_ASSERT_NOT_NULL_MESSAGE(printed_formatted, "Failed to print formatted array.");
    TEST_ASSERT_EQUAL_STRING_MESSAGE(expected, printed_formatted, "Formatted array is not correct.");

    cJSON_free(printed_formatted);
    cJSON_free(printed_unformatted);
    cJSON_Delete(item);
}

static void print_array_should_print_empty_arrays(void)
{
    assert_print_array("[]", "[]");
}

static void print_array_should_print_arrays_with_one_element(void)
{

    assert_print_array("[1]", "[1]");
    assert_print_array("[\"hello!\"]", "[\"hello!\"]");
    assert_print_array("[[]]", "[[]]");
    assert_print_array("[null]", "[null]");
}

static void print_array_should_print_arrays_with_multiple_elements(void)
{
    assert_print_array("[1, 2, 3]", "[1,2,3]");
    assert_print_array("[1, null, true, false, [], \"hello\", {\n\t}]", "[1,null,true,false,[],\"hello\",{}]");
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();

    RUN_TEST(print_array_should_print_empty_arrays);
    RUN_TEST(print_array_should_print_arrays_with_one_element);
    RUN_TEST(print_array_should_print_arrays_with_multiple_elements);

    return UNITY_END();
}
