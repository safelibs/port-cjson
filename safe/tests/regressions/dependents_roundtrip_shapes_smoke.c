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

#include "../unity/examples/unity_config.h"
#include "../unity/src/unity.h"
#include "../common.h"

static cJSON *roundtrip(cJSON *item)
{
    char *rendered = cJSON_PrintUnformatted(item);
    cJSON *parsed = NULL;

    TEST_ASSERT_NOT_NULL(rendered);
    parsed = cJSON_Parse(rendered);
    cJSON_free(rendered);
    TEST_ASSERT_NOT_NULL(parsed);
    return parsed;
}

static void reporting_payloads_should_roundtrip_mixed_scalars_objects_and_arrays(void)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *command = cJSON_AddObjectToObject(root, "command");
    cJSON *output = cJSON_AddObjectToObject(command, "output");
    cJSON *connections = cJSON_AddObjectToObject(output, "connections");
    cJSON *files = cJSON_AddArrayToObject(output, "files");
    cJSON *parsed = NULL;

    TEST_ASSERT_NOT_NULL(root);
    TEST_ASSERT_NOT_NULL(command);
    TEST_ASSERT_NOT_NULL(output);
    TEST_ASSERT_NOT_NULL(connections);
    TEST_ASSERT_NOT_NULL(files);

    TEST_ASSERT_NOT_NULL(cJSON_AddStringToObject(command, "name", "status"));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(connections, "max", 10));
    TEST_ASSERT_NOT_NULL(cJSON_AddBoolToObject(output, "reverse", true));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(output, "rate", 12.5));
    TEST_ASSERT_NOT_NULL(cJSON_AddStringToObject(output, "message", "running"));
    TEST_ASSERT_TRUE(cJSON_AddItemToArray(files, cJSON_CreateString("pgagroal.conf")));
    TEST_ASSERT_TRUE(cJSON_AddItemToArray(files, cJSON_CreateString("pgagroal_hba.conf")));

    parsed = roundtrip(root);
    TEST_ASSERT_EQUAL_STRING(
        "status",
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(parsed, "command"),
            "name"
        )->valuestring
    );
    TEST_ASSERT_EQUAL_INT(
        10,
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(parsed, "command"),
                "output"
            ),
            "connections"
        )->child->valueint
    );
    TEST_ASSERT_TRUE(cJSON_IsTrue(
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(parsed, "command"),
                "output"
            ),
            "reverse"
        )
    ));
    TEST_ASSERT_DOUBLE_WITHIN(
        1e-9,
        12.5,
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(parsed, "command"),
                "output"
            ),
            "rate"
        )->valuedouble
    );
    TEST_ASSERT_EQUAL_INT(
        2,
        cJSON_GetArraySize(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(
                    cJSON_GetObjectItemCaseSensitive(parsed, "command"),
                    "output"
                ),
                "files"
            )
        )
    );

    cJSON_Delete(parsed);
    cJSON_Delete(root);
}

static void subscriber_payloads_should_roundtrip_topic_payload_and_length(void)
{
    const char json[] =
        "{"
        "\"topic\":\"smoke/json\","
        "\"payload\":\"hello\","
        "\"payloadlen\":5"
        "}";
    cJSON *root = cJSON_Parse(json);
    cJSON *parsed = NULL;

    TEST_ASSERT_NOT_NULL(root);
    parsed = roundtrip(root);
    TEST_ASSERT_EQUAL_STRING("smoke/json", cJSON_GetObjectItemCaseSensitive(parsed, "topic")->valuestring);
    TEST_ASSERT_EQUAL_STRING("hello", cJSON_GetObjectItemCaseSensitive(parsed, "payload")->valuestring);
    TEST_ASSERT_EQUAL_INT(5, cJSON_GetObjectItemCaseSensitive(parsed, "payloadlen")->valueint);

    cJSON_Delete(parsed);
    cJSON_Delete(root);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(reporting_payloads_should_roundtrip_mixed_scalars_objects_and_arrays);
    RUN_TEST(subscriber_payloads_should_roundtrip_topic_payload_and_length);
    return UNITY_END();
}
