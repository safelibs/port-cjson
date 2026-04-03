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

static cJSON_bool decode_single_codepoint(const cJSON *item, unsigned int *codepoint)
{
    const unsigned char *string = (const unsigned char*)cJSON_GetStringValue(item);

    if ((string == NULL) || (codepoint == NULL))
    {
        return false;
    }

    if (string[0] == '\0')
    {
        *codepoint = 0;
        return true;
    }

    if ((string[0] & 0x80U) == 0)
    {
        *codepoint = string[0];
        return (string[1] == '\0');
    }

    if ((string[0] & 0xE0U) == 0xC0U)
    {
        if ((string[1] & 0xC0U) != 0x80U)
        {
            return false;
        }

        *codepoint = ((unsigned int)(string[0] & 0x1FU) << 6) | (unsigned int)(string[1] & 0x3FU);
        return (string[2] == '\0');
    }

    if ((string[0] & 0xF0U) == 0xE0U)
    {
        if (((string[1] & 0xC0U) != 0x80U) || ((string[2] & 0xC0U) != 0x80U))
        {
            return false;
        }

        *codepoint = ((unsigned int)(string[0] & 0x0FU) << 12)
                   | ((unsigned int)(string[1] & 0x3FU) << 6)
                   | (unsigned int)(string[2] & 0x3FU);
        return (string[3] == '\0');
    }

    if ((string[0] & 0xF8U) == 0xF0U)
    {
        if (((string[1] & 0xC0U) != 0x80U) || ((string[2] & 0xC0U) != 0x80U) || ((string[3] & 0xC0U) != 0x80U))
        {
            return false;
        }

        *codepoint = ((unsigned int)(string[0] & 0x07U) << 18)
                   | ((unsigned int)(string[1] & 0x3FU) << 12)
                   | ((unsigned int)(string[2] & 0x3FU) << 6)
                   | (unsigned int)(string[3] & 0x3FU);
        return (string[4] == '\0');
    }

    return false;
}

static void assert_escape_decodes_to(const cJSON *item, unsigned int expected)
{
    unsigned int actual = 0;

    TEST_ASSERT_TRUE_MESSAGE(decode_single_codepoint(item, &actual), "Failed to decode parsed UTF-8 back into a code point.");
    TEST_ASSERT_EQUAL_UINT_MESSAGE(expected, actual, "Unicode escape decoded to the wrong code point.");
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
            assert_escape_decodes_to(lower, number);
            assert_escape_decodes_to(upper, number);
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
        assert_escape_decodes_to(item, 0xBEEFU);

        cJSON_Delete(item);
    }

    assert_escape_decodes_to(reference, 0xBEEFU);
    cJSON_Delete(reference);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(unicode_escape_parsing_should_accept_all_non_surrogate_combinations);
    RUN_TEST(unicode_escape_parsing_should_accept_mixed_case_hex_digits);
    return UNITY_END();
}
