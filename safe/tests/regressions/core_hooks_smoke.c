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

#include <stdlib.h>

#include "../unity/examples/unity_config.h"
#include "../unity/src/unity.h"
#include "../common.h"

static int tracking_malloc_calls = 0;
static int tracking_free_calls = 0;
static int allocations_remaining = 0;

static void * CJSON_CDECL tracking_malloc(size_t size)
{
    tracking_malloc_calls++;
    return malloc(size);
}

static void CJSON_CDECL tracking_free(void *pointer)
{
    if (pointer != NULL)
    {
        tracking_free_calls++;
    }
    free(pointer);
}

static void * CJSON_CDECL failing_malloc(size_t size)
{
    (void)size;
    return NULL;
}

static void CJSON_CDECL normal_free(void *pointer)
{
    free(pointer);
}

static void * CJSON_CDECL limited_malloc(size_t size)
{
    if (allocations_remaining <= 0)
    {
        return NULL;
    }

    allocations_remaining--;
    tracking_malloc_calls++;
    return malloc(size);
}

static void cjson_version_should_match_header_macros(void)
{
    TEST_ASSERT_EQUAL_STRING("1.7.17", cJSON_Version());
}

static void cjson_hooks_should_route_allocations_and_reset(void)
{
    cJSON_Hooks hooks = { tracking_malloc, tracking_free };
    cJSON *item = NULL;
    void *scratch = NULL;

    tracking_malloc_calls = 0;
    tracking_free_calls = 0;

    cJSON_InitHooks(&hooks);

    scratch = cJSON_malloc(16);
    TEST_ASSERT_NOT_NULL(scratch);
    TEST_ASSERT_EQUAL_INT(1, tracking_malloc_calls);
    cJSON_free(scratch);
    TEST_ASSERT_EQUAL_INT(1, tracking_free_calls);

    item = cJSON_CreateString("hooked");
    TEST_ASSERT_NOT_NULL(item);
    TEST_ASSERT_TRUE(tracking_malloc_calls >= 3);
    cJSON_Delete(item);
    TEST_ASSERT_TRUE(tracking_free_calls >= 3);

    tracking_malloc_calls = 0;
    tracking_free_calls = 0;
    cJSON_InitHooks(NULL);

    scratch = cJSON_malloc(8);
    TEST_ASSERT_NOT_NULL(scratch);
    TEST_ASSERT_EQUAL_INT(0, tracking_malloc_calls);
    cJSON_free(scratch);
    TEST_ASSERT_EQUAL_INT(0, tracking_free_calls);
}

static void cjson_hooks_should_surface_allocation_failures(void)
{
    cJSON_Hooks hooks = { failing_malloc, normal_free };
    cJSON *root = cJSON_CreateObject();

    TEST_ASSERT_NOT_NULL(root);

    cJSON_InitHooks(&hooks);

    TEST_ASSERT_NULL(cJSON_malloc(1));
    TEST_ASSERT_NULL(cJSON_CreateObject());
    TEST_ASSERT_NULL(cJSON_CreateString("fail"));
    TEST_ASSERT_NULL(cJSON_AddNullToObject(root, "null"));

    cJSON_InitHooks(NULL);
    cJSON_Delete(root);
}

static void cjson_custom_hooks_should_handle_print_growth_without_realloc(void)
{
    cJSON_Hooks hooks = { tracking_malloc, tracking_free };
    cJSON *item = cJSON_CreateString("0123456789012345678901234567890123456789");
    char *printed = NULL;

    TEST_ASSERT_NOT_NULL(item);

    tracking_malloc_calls = 0;
    tracking_free_calls = 0;
    cJSON_InitHooks(&hooks);

    printed = cJSON_PrintBuffered(item, 1, false);
    TEST_ASSERT_NOT_NULL(printed);
    TEST_ASSERT_TRUE(tracking_malloc_calls >= 2);
    cJSON_free(printed);
    TEST_ASSERT_TRUE(tracking_free_calls >= 1);

    cJSON_InitHooks(NULL);
    cJSON_Delete(item);
}

static void cjson_reference_add_helpers_should_validate_before_allocating(void)
{
    cJSON_Hooks hooks = { tracking_malloc, tracking_free };
    cJSON *object = cJSON_CreateObject();
    cJSON *item = cJSON_CreateNumber(42);

    TEST_ASSERT_NOT_NULL(object);
    TEST_ASSERT_NOT_NULL(item);

    tracking_malloc_calls = 0;
    tracking_free_calls = 0;
    cJSON_InitHooks(&hooks);

    TEST_ASSERT_FALSE(cJSON_AddItemReferenceToArray(NULL, item));
    TEST_ASSERT_FALSE(cJSON_AddItemReferenceToObject(NULL, "value", item));
    TEST_ASSERT_FALSE(cJSON_AddItemReferenceToObject(object, NULL, item));
    TEST_ASSERT_EQUAL_INT(0, tracking_malloc_calls);
    TEST_ASSERT_EQUAL_INT(0, tracking_free_calls);

    cJSON_InitHooks(NULL);
    cJSON_Delete(item);
    cJSON_Delete(object);
}

static void cjson_reference_add_failure_should_release_temporary_reference(void)
{
    cJSON_Hooks hooks = { limited_malloc, tracking_free };
    cJSON *object = cJSON_CreateObject();
    cJSON *item = cJSON_CreateNumber(42);

    TEST_ASSERT_NOT_NULL(object);
    TEST_ASSERT_NOT_NULL(item);

    tracking_malloc_calls = 0;
    tracking_free_calls = 0;
    allocations_remaining = 1;
    cJSON_InitHooks(&hooks);

    TEST_ASSERT_FALSE(cJSON_AddItemReferenceToObject(object, "value", item));
    TEST_ASSERT_EQUAL_INT(1, tracking_malloc_calls);
    TEST_ASSERT_EQUAL_INT(1, tracking_free_calls);
    TEST_ASSERT_NULL(cJSON_GetObjectItemCaseSensitive(object, "value"));

    cJSON_InitHooks(NULL);
    cJSON_Delete(item);
    cJSON_Delete(object);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();

    RUN_TEST(cjson_version_should_match_header_macros);
    RUN_TEST(cjson_hooks_should_route_allocations_and_reset);
    RUN_TEST(cjson_hooks_should_surface_allocation_failures);
    RUN_TEST(cjson_custom_hooks_should_handle_print_growth_without_realloc);
    RUN_TEST(cjson_reference_add_helpers_should_validate_before_allocating);
    RUN_TEST(cjson_reference_add_failure_should_release_temporary_reference);

    return UNITY_END();
}
