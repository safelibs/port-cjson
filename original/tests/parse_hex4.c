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

static cJSON *parse_unicode_escape(const char *digits)
{
    char json[16];
    const char *parse_end = NULL;
    cJSON *item = NULL;

    TEST_ASSERT_EQUAL_INT_MESSAGE(8, sprintf(json, "\"\\u%s\"", digits), "sprintf failed.");

    item = cJSON_ParseWithOpts(json, &parse_end, false);
    if (item != NULL)
    {
        TEST_ASSERT_EQUAL_PTR_MESSAGE(json + strlen(json), parse_end, "Did not parse the whole unicode escape.");
        TEST_ASSERT_TRUE_MESSAGE(cJSON_IsString(item), "Unicode escape did not parse as a string.");
    }

    return item;
}

static void unicode_escape_parsing_should_accept_all_non_surrogate_combinations(void)
{
    unsigned int number = 0;
    char digits_lower[5];
    char digits_upper[5];

    for (number = 0; number <= 0xFFFF; number++)
    {
        cJSON *lower = NULL;
        cJSON *upper = NULL;
        const cJSON_bool is_surrogate = ((number >= 0xD800U) && (number <= 0xDFFFU));

        TEST_ASSERT_EQUAL_INT_MESSAGE(4, sprintf(digits_lower, "%.4x", number), "sprintf failed.");
        TEST_ASSERT_EQUAL_INT_MESSAGE(4, sprintf(digits_upper, "%.4X", number), "sprintf failed.");

        lower = parse_unicode_escape(digits_lower);
        upper = parse_unicode_escape(digits_upper);

        if (is_surrogate)
        {
            TEST_ASSERT_NULL_MESSAGE(lower, "Standalone lowercase surrogate escape should not parse.");
            TEST_ASSERT_NULL_MESSAGE(upper, "Standalone uppercase surrogate escape should not parse.");
        }
        else
        {
            TEST_ASSERT_NOT_NULL_MESSAGE(lower, "Lowercase unicode escape should parse.");
            TEST_ASSERT_NOT_NULL_MESSAGE(upper, "Uppercase unicode escape should parse.");
            TEST_ASSERT_EQUAL_STRING_MESSAGE(cJSON_GetStringValue(lower), cJSON_GetStringValue(upper), "Unicode escape parsing changed with hex digit casing.");
        }

        cJSON_Delete(lower);
        cJSON_Delete(upper);
    }
}

static void unicode_escape_parsing_should_accept_mixed_case_hex_digits(void)
{
    static const char *const variants[] =
    {
        "beef", "beeF", "beEf", "beEF",
        "bEef", "bEeF", "bEEf", "bEEF",
        "Beef", "BeeF", "BeEf", "BeEF",
        "BEef", "BEeF", "BEEf", "BEEF"
    };
    cJSON *reference = NULL;
    size_t i = 0;

    reference = parse_unicode_escape("BEEF");
    TEST_ASSERT_NOT_NULL(reference);

    for (i = 0; i < (sizeof(variants) / sizeof(variants[0])); i++)
    {
        cJSON *item = parse_unicode_escape(variants[i]);

        TEST_ASSERT_NOT_NULL(item);
        TEST_ASSERT_EQUAL_STRING_MESSAGE(cJSON_GetStringValue(reference), cJSON_GetStringValue(item), "Mixed-case unicode escape parsed differently.");

        cJSON_Delete(item);
    }

    cJSON_Delete(reference);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(unicode_escape_parsing_should_accept_all_non_surrogate_combinations);
    RUN_TEST(unicode_escape_parsing_should_accept_mixed_case_hex_digits);
    return UNITY_END();
}
