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
#include "../../cJSON_Utils.h"

static const char *malformed_pointers[] =
{
    "/foo/1x",
    "/foo/01",
    "/foo/+1",
    "/foo/-1",
    "/foo/184467440737095516160000"
};

static void malformed_index_tokens_should_not_resolve_pointer_lookups(void)
{
    cJSON *root = NULL;
    size_t i = 0;

    root = cJSON_Parse("{\"foo\":[\"zero\",\"one\",\"two\"]}");
    TEST_ASSERT_NOT_NULL(root);

    for (i = 0; i < (sizeof(malformed_pointers) / sizeof(malformed_pointers[0])); i++)
    {
        TEST_ASSERT_NULL(cJSONUtils_GetPointer(root, malformed_pointers[i]));
        TEST_ASSERT_NULL(cJSONUtils_GetPointerCaseSensitive(root, malformed_pointers[i]));
    }

    cJSON_Delete(root);
}

static void malformed_index_tokens_should_fail_patch_application(void)
{
    size_t i = 0;

    for (i = 0; i < (sizeof(malformed_pointers) / sizeof(malformed_pointers[0])); i++)
    {
        cJSON *object = NULL;
        cJSON *patch = NULL;
        cJSON *operation = NULL;
        cJSON *foo = NULL;
        cJSON *middle = NULL;

        object = cJSON_Parse("{\"foo\":[\"zero\",\"one\",\"two\"]}");
        patch = cJSON_CreateArray();
        operation = cJSON_CreateObject();

        TEST_ASSERT_NOT_NULL(object);
        TEST_ASSERT_NOT_NULL(patch);
        TEST_ASSERT_NOT_NULL(operation);

        cJSON_AddItemToObject(operation, "op", cJSON_CreateString("remove"));
        cJSON_AddItemToObject(operation, "path", cJSON_CreateString(malformed_pointers[i]));
        cJSON_AddItemToArray(patch, operation);

        TEST_ASSERT_TRUE(cJSONUtils_ApplyPatchesCaseSensitive(object, patch) != 0);

        foo = cJSON_GetObjectItemCaseSensitive(object, "foo");
        middle = cJSON_GetArrayItem(foo, 1);
        TEST_ASSERT_NOT_NULL(foo);
        TEST_ASSERT_NOT_NULL(middle);
        TEST_ASSERT_TRUE(cJSON_IsString(middle));
        TEST_ASSERT_EQUAL_STRING("one", middle->valuestring);
        TEST_ASSERT_EQUAL_INT(3, cJSON_GetArraySize(foo));

        cJSON_Delete(patch);
        cJSON_Delete(object);
    }
}

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(malformed_index_tokens_should_not_resolve_pointer_lookups);
    RUN_TEST(malformed_index_tokens_should_fail_patch_application);

    return UNITY_END();
}
