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
#include "../cJSON_Utils.h"

static cJSON *create_single_patch(
    const char *operation,
    const char *path,
    const char *from,
    cJSON *value
)
{
    cJSON *patches = cJSON_CreateArray();
    cJSON *patch = cJSON_CreateObject();

    TEST_ASSERT_NOT_NULL(patches);
    TEST_ASSERT_NOT_NULL(patch);

    cJSON_AddItemToObject(patch, "op", cJSON_CreateString(operation));
    if (path != NULL)
    {
        cJSON_AddItemToObject(patch, "path", cJSON_CreateString(path));
    }
    if (from != NULL)
    {
        cJSON_AddItemToObject(patch, "from", cJSON_CreateString(from));
    }
    if (value != NULL)
    {
        cJSON_AddItemToObject(patch, "value", value);
    }

    cJSON_AddItemToArray(patches, patch);

    return patches;
}

static void assert_case_sensitive_patch_status(
    const char *document,
    cJSON *patches,
    int expected_status
)
{
    cJSON *object = cJSON_Parse(document);
    TEST_ASSERT_NOT_NULL(object);

    TEST_ASSERT_EQUAL_INT(expected_status, cJSONUtils_ApplyPatchesCaseSensitive(object, patches));

    cJSON_Delete(object);
    cJSON_Delete(patches);
}

static void cjson_utils_functions_shouldnt_crash_with_null_pointers(void)
{
    cJSON *item = cJSON_CreateString("item");
    TEST_ASSERT_NOT_NULL(item);

    TEST_ASSERT_NULL(cJSONUtils_GetPointer(item, NULL));
    TEST_ASSERT_NULL(cJSONUtils_GetPointer(NULL, "pointer"));
    TEST_ASSERT_NULL(cJSONUtils_GetPointerCaseSensitive(NULL, "pointer"));
    TEST_ASSERT_NULL(cJSONUtils_GetPointerCaseSensitive(item, NULL));
    TEST_ASSERT_NULL(cJSONUtils_GeneratePatches(item, NULL));
    TEST_ASSERT_NULL(cJSONUtils_GeneratePatches(NULL, item));
    TEST_ASSERT_NULL(cJSONUtils_GeneratePatchesCaseSensitive(item, NULL));
    TEST_ASSERT_NULL(cJSONUtils_GeneratePatchesCaseSensitive(NULL, item));
    cJSONUtils_AddPatchToArray(item, "path", "add", NULL);
    cJSONUtils_AddPatchToArray(item, "path", NULL, item);
    cJSONUtils_AddPatchToArray(item, NULL, "add", item);
    cJSONUtils_AddPatchToArray(NULL, "path", "add", item);
    cJSONUtils_ApplyPatches(item, NULL);
    cJSONUtils_ApplyPatches(NULL, item);
    cJSONUtils_ApplyPatchesCaseSensitive(item, NULL);
    cJSONUtils_ApplyPatchesCaseSensitive(NULL, item);
    TEST_ASSERT_NULL(cJSONUtils_MergePatch(item, NULL));
    item = cJSON_CreateString("item");
    TEST_ASSERT_NULL(cJSONUtils_MergePatchCaseSensitive(item, NULL));
    item = cJSON_CreateString("item");
    /* these calls are actually valid */
    /* cJSONUtils_MergePatch(NULL, item); */
    /* cJSONUtils_MergePatchCaseSensitive(NULL, item);*/
    /* cJSONUtils_GenerateMergePatch(item, NULL); */
    /* cJSONUtils_GenerateMergePatch(NULL, item); */
    /* cJSONUtils_GenerateMergePatchCaseSensitive(item, NULL); */
    /* cJSONUtils_GenerateMergePatchCaseSensitive(NULL, item); */

    TEST_ASSERT_NULL(cJSONUtils_FindPointerFromObjectTo(item, NULL));
    TEST_ASSERT_NULL(cJSONUtils_FindPointerFromObjectTo(NULL, item));
    cJSONUtils_SortObject(NULL);
    cJSONUtils_SortObjectCaseSensitive(NULL);

    cJSON_Delete(item);
}

static void cjson_utils_apply_patches_should_report_status_codes(void)
{
    cJSON *item = cJSON_CreateString("item");
    cJSON *non_array_patch = cJSON_CreateObject();

    TEST_ASSERT_NOT_NULL(item);
    TEST_ASSERT_NOT_NULL(non_array_patch);

    TEST_ASSERT_EQUAL_INT(1, cJSONUtils_ApplyPatches(item, NULL));
    TEST_ASSERT_EQUAL_INT(1, cJSONUtils_ApplyPatchesCaseSensitive(item, NULL));
    TEST_ASSERT_EQUAL_INT(1, cJSONUtils_ApplyPatches(item, non_array_patch));
    TEST_ASSERT_EQUAL_INT(1, cJSONUtils_ApplyPatchesCaseSensitive(item, non_array_patch));

    cJSON_Delete(non_array_patch);
    cJSON_Delete(item);

    assert_case_sensitive_patch_status(
        "{\"foo\":1}",
        create_single_patch("add", NULL, NULL, cJSON_CreateNumber(1)),
        2
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":1}",
        create_single_patch("spam", "/foo", NULL, cJSON_CreateNumber(1)),
        3
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":1}",
        create_single_patch("move", "/bar", NULL, NULL),
        4
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":1}",
        create_single_patch("copy", "/bar", "/baz", NULL),
        5
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":1}",
        create_single_patch("add", "/bar", NULL, NULL),
        7
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":[\"zero\",\"one\"]}",
        create_single_patch("add", "/foo/3", NULL, cJSON_CreateString("two")),
        10
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":[\"zero\",\"one\"]}",
        create_single_patch("add", "/foo/01", NULL, cJSON_CreateString("two")),
        11
    );
    assert_case_sensitive_patch_status(
        "{\"foo\":[\"zero\",\"one\"]}",
        create_single_patch("remove", "/foo/3", NULL, NULL),
        13
    );
}

static void cjson_utils_pointer_should_reject_invalid_escape_sequences(void)
{
    cJSON *root = cJSON_Parse("{\"a/b\":1}");

    TEST_ASSERT_NOT_NULL(root);
    TEST_ASSERT_NULL(cJSONUtils_GetPointer(root, "/a~2b"));
    TEST_ASSERT_NULL(cJSONUtils_GetPointerCaseSensitive(root, "/a~2b"));

    assert_case_sensitive_patch_status(
        "{\"a/b\":1}",
        create_single_patch("add", "/a~2b", NULL, cJSON_CreateNumber(2)),
        9
    );

    cJSON_Delete(root);
}

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(cjson_utils_functions_shouldnt_crash_with_null_pointers);
    RUN_TEST(cjson_utils_apply_patches_should_report_status_codes);
    RUN_TEST(cjson_utils_pointer_should_reject_invalid_escape_sequences);

    return UNITY_END();
}
