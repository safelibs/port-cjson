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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "unity/examples/unity_config.h"
#include "unity/src/unity.h"
#include "common.h"

static void assert_print_value(const char *input)
{
    const char *parse_end = NULL;
    cJSON *item = cJSON_ParseWithOpts(input, &parse_end, false);
    char *printed = NULL;

    TEST_ASSERT_NOT_NULL_MESSAGE(item, "Failed to parse value.");
    TEST_ASSERT_EQUAL_PTR_MESSAGE(input + strlen(input), parse_end, "Did not parse the whole value.");

    printed = cJSON_PrintUnformatted(item);
    TEST_ASSERT_NOT_NULL_MESSAGE(printed, "Failed to print value.");
    TEST_ASSERT_EQUAL_STRING_MESSAGE(input, printed, "Printed value is not as expected.");

    cJSON_free(printed);
    cJSON_Delete(item);
}

static void print_value_should_print_null(void)
{
    assert_print_value("null");
}

static void print_value_should_print_true(void)
{
    assert_print_value("true");
}

static void print_value_should_print_false(void)
{
    assert_print_value("false");
}

static void print_value_should_print_number(void)
{
    assert_print_value("1.5");
}

static void print_value_should_print_string(void)
{
    assert_print_value("\"\"");
    assert_print_value("\"hello\"");
}

static void print_value_should_print_array(void)
{
    assert_print_value("[]");
}

static void print_value_should_print_object(void)
{
    assert_print_value("{}");
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();

    RUN_TEST(print_value_should_print_null);
    RUN_TEST(print_value_should_print_true);
    RUN_TEST(print_value_should_print_false);
    RUN_TEST(print_value_should_print_number);
    RUN_TEST(print_value_should_print_string);
    RUN_TEST(print_value_should_print_array);
    RUN_TEST(print_value_should_print_object);

    return UNITY_END();
}
