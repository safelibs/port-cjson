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
#include "../common.h"

static void giant_numeric_literals_should_fail_closed_without_partial_consumption(void)
{
    const char json[] =
        "{\"a\":true,\"b\":[null,"
        "9999999999999999999999999999999999999999999999912345678901234567]}";
    const char *number_start = strstr(json, "9999999999999999999999999999999999999999999999912345678901234567");
    const char *parse_end = NULL;
    cJSON *item = NULL;

    TEST_ASSERT_NOT_NULL(number_start);

    item = cJSON_ParseWithOpts(json, &parse_end, false);
    TEST_ASSERT_NULL(item);
    TEST_ASSERT_EQUAL_PTR(number_start, parse_end);
    TEST_ASSERT_EQUAL_PTR(number_start, cJSON_GetErrorPtr());

    item = cJSON_ParseWithLengthOpts(json, strlen(json) + sizeof(""), &parse_end, true);
    TEST_ASSERT_NULL(item);
    TEST_ASSERT_EQUAL_PTR(number_start, parse_end);
    TEST_ASSERT_EQUAL_PTR(number_start, cJSON_GetErrorPtr());
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(giant_numeric_literals_should_fail_closed_without_partial_consumption);
    return UNITY_END();
}
