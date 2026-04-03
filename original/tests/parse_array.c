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

static void assert_is_array(cJSON *array_item)
{
    TEST_ASSERT_NOT_NULL_MESSAGE(array_item, "Item is NULL.");

    assert_not_in_list(array_item);
    assert_has_type(array_item, cJSON_Array);
    assert_has_no_reference(array_item);
    assert_has_no_const_string(array_item);
    assert_has_no_valuestring(array_item);
    assert_has_no_string(array_item);
}

static void assert_not_array(const char *json)
{
    cJSON *item = cJSON_Parse(json);

    if (item == NULL)
    {
        TEST_ASSERT_NULL_MESSAGE(item, "Malformed JSON should not parse.");
        return;
    }

    TEST_ASSERT_FALSE_MESSAGE(cJSON_IsArray(item), "JSON value should not parse as an array.");
    cJSON_Delete(item);
}

static cJSON *assert_parse_array(const char *json)
{
    const char *parse_end = NULL;
    cJSON *item = cJSON_ParseWithOpts(json, &parse_end, false);

    TEST_ASSERT_NOT_NULL_MESSAGE(item, "Failed to parse array.");
    TEST_ASSERT_EQUAL_PTR_MESSAGE(json + strlen(json), parse_end, "Did not parse the whole array.");
    assert_is_array(item);

    return item;
}

static void parse_array_should_parse_empty_arrays(void)
{
    cJSON *item = assert_parse_array("[]");
    TEST_ASSERT_EQUAL_INT(0, cJSON_GetArraySize(item));
    cJSON_Delete(item);

    item = assert_parse_array("[\n\t]");
    TEST_ASSERT_EQUAL_INT(0, cJSON_GetArraySize(item));
    cJSON_Delete(item);
}


static void parse_array_should_parse_arrays_with_one_element(void)
{
    cJSON *item = NULL;
    cJSON *child = NULL;

    item = assert_parse_array("[1]");
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(item));
    child = cJSON_GetArrayItem(item, 0);
    TEST_ASSERT_NOT_NULL(child);
    assert_has_type(child, cJSON_Number);
    cJSON_Delete(item);

    item = assert_parse_array("[\"hello!\"]");
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(item));
    child = cJSON_GetArrayItem(item, 0);
    TEST_ASSERT_NOT_NULL(child);
    assert_has_type(child, cJSON_String);
    TEST_ASSERT_EQUAL_STRING("hello!", child->valuestring);
    cJSON_Delete(item);

    item = assert_parse_array("[[]]");
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(item));
    child = cJSON_GetArrayItem(item, 0);
    TEST_ASSERT_NOT_NULL(child);
    assert_has_type(child, cJSON_Array);
    TEST_ASSERT_EQUAL_INT(0, cJSON_GetArraySize(child));
    cJSON_Delete(item);

    item = assert_parse_array("[null]");
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(item));
    child = cJSON_GetArrayItem(item, 0);
    TEST_ASSERT_NOT_NULL(child);
    assert_has_type(child, cJSON_NULL);
    cJSON_Delete(item);
}

static void parse_array_should_parse_arrays_with_multiple_elements(void)
{
    cJSON *item = assert_parse_array("[1\t,\n2, 3]");
    TEST_ASSERT_EQUAL_INT(3, cJSON_GetArraySize(item));
    assert_has_type(cJSON_GetArrayItem(item, 0), cJSON_Number);
    assert_has_type(cJSON_GetArrayItem(item, 1), cJSON_Number);
    assert_has_type(cJSON_GetArrayItem(item, 2), cJSON_Number);
    TEST_ASSERT_NULL(cJSON_GetArrayItem(item, 3));
    cJSON_Delete(item);

    {
        size_t i = 0;
        cJSON *mixed = NULL;
        int expected_types[7] =
        {
            cJSON_Number,
            cJSON_NULL,
            cJSON_True,
            cJSON_False,
            cJSON_Array,
            cJSON_String,
            cJSON_Object
        };
        mixed = assert_parse_array("[1, null, true, false, [], \"hello\", {}]");
        TEST_ASSERT_EQUAL_INT(7, cJSON_GetArraySize(mixed));

        for (i = 0; i < (sizeof(expected_types) / sizeof(expected_types[0])); i++)
        {
            cJSON *node = cJSON_GetArrayItem(mixed, (int)i);
            TEST_ASSERT_NOT_NULL(node);
            TEST_ASSERT_BITS(0xFF, expected_types[i], node->type);
        }
        cJSON_Delete(mixed);
    }
}

static void parse_array_should_not_parse_non_arrays(void)
{
    assert_not_array("");
    assert_not_array("[");
    assert_not_array("]");
    assert_not_array("{\"hello\":[]}");
    assert_not_array("42");
    assert_not_array("3.14");
    assert_not_array("\"[]hello world!\n\"");
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(parse_array_should_parse_empty_arrays);
    RUN_TEST(parse_array_should_parse_arrays_with_one_element);
    RUN_TEST(parse_array_should_parse_arrays_with_multiple_elements);
    RUN_TEST(parse_array_should_not_parse_non_arrays);
    return UNITY_END();
}
