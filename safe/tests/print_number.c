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

static void normalize_exponent(char *buffer)
{
    unsigned int i = 0;

    /* In MinGW or visual studio(before 2015),the exponten is represented using three digits,like:"1e-009","1e+017"
     * remove extra "0" to output "1e-09" or "1e+17",which makes testcase PASS */
    for (i = 0; buffer[i] != '\0'; i++)
    {
        if (i > 3 && buffer[i] == '0')
        {
            if (((buffer[i - 3] == 'e') && (buffer[i - 2] == '-') && (buffer[i] == '0'))
                || ((buffer[i - 2] == 'e') && (buffer[i - 1] == '+')))
            {
                while (buffer[i] != '\0')
                {
                    buffer[i] = buffer[i + 1];
                    i++;
                }
            }        
        }  
    }
}

static void assert_print_number(const char *expected, double input)
{
    cJSON *item = cJSON_CreateNumber(input);
    char *printed = NULL;

    TEST_ASSERT_NOT_NULL_MESSAGE(item, "Failed to create number item.");
    printed = cJSON_PrintUnformatted(item);
    TEST_ASSERT_NOT_NULL_MESSAGE(printed, "Failed to print number.");
    normalize_exponent(printed);
    TEST_ASSERT_EQUAL_STRING_MESSAGE(expected, printed, "Printed number is not as expected.");

    cJSON_free(printed);
    cJSON_Delete(item);
}

static void print_number_should_print_zero(void)
{
    assert_print_number("0", 0);
}

static void print_number_should_print_negative_integers(void)
{
    assert_print_number("-1", -1.0);
    assert_print_number("-32768", -32768.0);
    assert_print_number("-2147483648", -2147483648.0);
}

static void print_number_should_print_positive_integers(void)
{
    assert_print_number("1", 1.0);
    assert_print_number("32767", 32767.0);
    assert_print_number("2147483647", 2147483647.0);
}

static void print_number_should_print_positive_reals(void)
{
    assert_print_number("0.123", 0.123);
    assert_print_number("1e-09", 10e-10);
    assert_print_number("1000000000000", 10e11);
    assert_print_number("1.23e+129", 123e+127);
    assert_print_number("1.23e-126", 123e-128);
    assert_print_number("3.1415926535897931", 3.1415926535897931);
}

static void print_number_should_print_negative_reals(void)
{
    assert_print_number("-0.0123", -0.0123);
    assert_print_number("-1e-09", -10e-10);
    assert_print_number("-1e+21", -10e20);
    assert_print_number("-1.23e+129", -123e+127);
    assert_print_number("-1.23e-126", -123e-128);
}

static void print_number_should_print_non_number(void)
{
    TEST_IGNORE();
    /* FIXME: Cannot test this easily in C89! */
    /* assert_print_number("null", NaN); */
    /* assert_print_number("null", INFTY); */
    /* assert_print_number("null", -INFTY); */
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();

    RUN_TEST(print_number_should_print_zero);
    RUN_TEST(print_number_should_print_negative_integers);
    RUN_TEST(print_number_should_print_positive_integers);
    RUN_TEST(print_number_should_print_positive_reals);
    RUN_TEST(print_number_should_print_negative_reals);
    RUN_TEST(print_number_should_print_non_number);

    return UNITY_END();
}
