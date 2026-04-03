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

static void assert_is_object(cJSON *object_item)
{
    TEST_ASSERT_NOT_NULL_MESSAGE(object_item, "Item is NULL.");

    assert_not_in_list(object_item);
    assert_has_type(object_item, cJSON_Object);
    assert_has_no_reference(object_item);
    assert_has_no_const_string(object_item);
    assert_has_no_valuestring(object_item);
    assert_has_no_string(object_item);
}

static void assert_is_child(cJSON *child_item, const char *name, int type)
{
    TEST_ASSERT_NOT_NULL_MESSAGE(child_item, "Child item is NULL.");
    TEST_ASSERT_NOT_NULL_MESSAGE(child_item->string, "Child item doesn't have a name.");
    TEST_ASSERT_EQUAL_STRING_MESSAGE(name, child_item->string, "Child item has the wrong name.");
    TEST_ASSERT_BITS(0xFF, type, child_item->type);
}

static void assert_not_object(const char *json)
{
    cJSON *item = cJSON_Parse(json);

    if (item == NULL)
    {
        TEST_ASSERT_NULL_MESSAGE(item, "Malformed JSON should not parse.");
        return;
    }

    TEST_ASSERT_FALSE_MESSAGE(cJSON_IsObject(item), "JSON value should not parse as an object.");
    cJSON_Delete(item);
}

static cJSON *assert_parse_object(const char *json)
{
    const char *parse_end = NULL;
    cJSON *item = cJSON_ParseWithOpts(json, &parse_end, false);

    TEST_ASSERT_NOT_NULL_MESSAGE(item, "Failed to parse object.");
    TEST_ASSERT_EQUAL_PTR_MESSAGE(json + strlen(json), parse_end, "Did not parse the whole object.");
    assert_is_object(item);

    return item;
}

static void parse_object_should_parse_empty_objects(void)
{
    cJSON *item = assert_parse_object("{}");
    TEST_ASSERT_EQUAL_INT(0, cJSON_GetArraySize(item));
    cJSON_Delete(item);

    item = assert_parse_object("{\n\t}");
    TEST_ASSERT_EQUAL_INT(0, cJSON_GetArraySize(item));
    cJSON_Delete(item);
}

static void parse_object_should_parse_objects_with_one_element(void)
{
    cJSON *item = NULL;

    item = assert_parse_object("{\"one\":1}");
    assert_is_child(cJSON_GetObjectItemCaseSensitive(item, "one"), "one", cJSON_Number);
    cJSON_Delete(item);

    item = assert_parse_object("{\"hello\":\"world!\"}");
    assert_is_child(cJSON_GetObjectItemCaseSensitive(item, "hello"), "hello", cJSON_String);
    cJSON_Delete(item);

    item = assert_parse_object("{\"array\":[]}");
    assert_is_child(cJSON_GetObjectItemCaseSensitive(item, "array"), "array", cJSON_Array);
    cJSON_Delete(item);

    item = assert_parse_object("{\"null\":null}");
    assert_is_child(cJSON_GetObjectItemCaseSensitive(item, "null"), "null", cJSON_NULL);
    cJSON_Delete(item);
}

static void parse_object_should_parse_objects_with_multiple_elements(void)
{
    cJSON *item = assert_parse_object("{\"one\":1\t,\t\"two\"\n:2, \"three\":3}");
    cJSON *node = NULL;
    static const char *const first_expected_names[] = {"one", "two", "three"};
    int index = 0;

    cJSON_ArrayForEach(node, item)
    {
        TEST_ASSERT_TRUE(index < 3);
        assert_is_child(node, first_expected_names[index], cJSON_Number);
        index++;
    }
    TEST_ASSERT_EQUAL_INT(3, index);
    cJSON_Delete(item);

    {
        size_t mixed_index = 0;
        cJSON *mixed = NULL;
        cJSON *mixed_node = NULL;
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
        const char *mixed_expected_names[7] =
        {
            "one",
            "NULL",
            "TRUE",
            "FALSE",
            "array",
            "world",
            "object"
        };
        mixed = assert_parse_object("{\"one\":1, \"NULL\":null, \"TRUE\":true, \"FALSE\":false, \"array\":[], \"world\":\"hello\", \"object\":{}}");

        cJSON_ArrayForEach(mixed_node, mixed)
        {
            assert_is_child(mixed_node, mixed_expected_names[mixed_index], expected_types[mixed_index]);
            mixed_index++;
        }
        TEST_ASSERT_EQUAL_INT(mixed_index, 7);
        cJSON_Delete(mixed);
    }
}

static void parse_object_should_not_parse_non_objects(void)
{
    assert_not_object("");
    assert_not_object("{");
    assert_not_object("}");
    assert_not_object("[\"hello\",{}]");
    assert_not_object("42");
    assert_not_object("3.14");
    assert_not_object("\"{}hello world!\n\"");
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(parse_object_should_parse_empty_objects);
    RUN_TEST(parse_object_should_not_parse_non_objects);
    RUN_TEST(parse_object_should_parse_objects_with_multiple_elements);
    RUN_TEST(parse_object_should_parse_objects_with_one_element);
    return UNITY_END();
}
