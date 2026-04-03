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

#include <stddef.h>

#include "../unity/examples/unity_config.h"
#include "../unity/src/unity.h"
#include "../common.h"

static void cjson_layout_should_match_public_abi(void)
{
    TEST_ASSERT_EQUAL_UINT(sizeof(int), sizeof(((cJSON*)0)->type));
    TEST_ASSERT_EQUAL_UINT(sizeof(int), sizeof(((cJSON*)0)->valueint));
    TEST_ASSERT_EQUAL_UINT(sizeof(double), sizeof(((cJSON*)0)->valuedouble));

    if (sizeof(void*) == 8u)
    {
        TEST_ASSERT_EQUAL_UINT(64u, sizeof(cJSON));
        TEST_ASSERT_EQUAL_UINT(0u, offsetof(cJSON, next));
        TEST_ASSERT_EQUAL_UINT(8u, offsetof(cJSON, prev));
        TEST_ASSERT_EQUAL_UINT(16u, offsetof(cJSON, child));
        TEST_ASSERT_EQUAL_UINT(24u, offsetof(cJSON, type));
        TEST_ASSERT_EQUAL_UINT(32u, offsetof(cJSON, valuestring));
        TEST_ASSERT_EQUAL_UINT(40u, offsetof(cJSON, valueint));
        TEST_ASSERT_EQUAL_UINT(48u, offsetof(cJSON, valuedouble));
        TEST_ASSERT_EQUAL_UINT(56u, offsetof(cJSON, string));
        return;
    }

    if (sizeof(void*) == 4u)
    {
        TEST_ASSERT_EQUAL_UINT(36u, sizeof(cJSON));
        TEST_ASSERT_EQUAL_UINT(0u, offsetof(cJSON, next));
        TEST_ASSERT_EQUAL_UINT(4u, offsetof(cJSON, prev));
        TEST_ASSERT_EQUAL_UINT(8u, offsetof(cJSON, child));
        TEST_ASSERT_EQUAL_UINT(12u, offsetof(cJSON, type));
        TEST_ASSERT_EQUAL_UINT(16u, offsetof(cJSON, valuestring));
        TEST_ASSERT_EQUAL_UINT(20u, offsetof(cJSON, valueint));
        TEST_ASSERT_EQUAL_UINT(24u, offsetof(cJSON, valuedouble));
        TEST_ASSERT_EQUAL_UINT(32u, offsetof(cJSON, string));
        return;
    }

    TEST_FAIL_MESSAGE("Unsupported pointer size for cJSON ABI layout smoke test.");
}

static void cjson_hooks_layout_should_match_public_abi(void)
{
    TEST_ASSERT_EQUAL_UINT(sizeof(int), sizeof(cJSON_bool));
    TEST_ASSERT_EQUAL_UINT(sizeof(void *), sizeof(((cJSON_Hooks*)0)->malloc_fn));
    TEST_ASSERT_EQUAL_UINT(sizeof(void *), sizeof(((cJSON_Hooks*)0)->free_fn));
    TEST_ASSERT_EQUAL_UINT(0u, offsetof(cJSON_Hooks, malloc_fn));
    TEST_ASSERT_EQUAL_UINT(sizeof(void *), offsetof(cJSON_Hooks, free_fn));
    TEST_ASSERT_EQUAL_UINT(sizeof(void *) * 2u, sizeof(cJSON_Hooks));
}

static void cjson_flag_constants_should_match_upstream_header(void)
{
    TEST_ASSERT_EQUAL_INT(0, cJSON_Invalid);
    TEST_ASSERT_EQUAL_INT(1, cJSON_False);
    TEST_ASSERT_EQUAL_INT(2, cJSON_True);
    TEST_ASSERT_EQUAL_INT(4, cJSON_NULL);
    TEST_ASSERT_EQUAL_INT(8, cJSON_Number);
    TEST_ASSERT_EQUAL_INT(16, cJSON_String);
    TEST_ASSERT_EQUAL_INT(32, cJSON_Array);
    TEST_ASSERT_EQUAL_INT(64, cJSON_Object);
    TEST_ASSERT_EQUAL_INT(128, cJSON_Raw);
    TEST_ASSERT_EQUAL_INT(256, cJSON_IsReference);
    TEST_ASSERT_EQUAL_INT(512, cJSON_StringIsConst);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();

    RUN_TEST(cjson_layout_should_match_public_abi);
    RUN_TEST(cjson_hooks_layout_should_match_public_abi);
    RUN_TEST(cjson_flag_constants_should_match_upstream_header);

    return UNITY_END();
}
