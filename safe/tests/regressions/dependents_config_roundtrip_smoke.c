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

static void calibration_and_project_payloads_should_roundtrip_nested_arrays_and_flags(void)
{
    const char json[] =
        "{"
        "\"tracking\":{"
        "\"camera_name\":\"StereoCam\","
        "\"camera_mode\":7,"
        "\"camera_type\":1,"
        "\"calibration_path\":\"/tmp/monado-calibration.json\""
        "},"
        "\"gui\":{"
        "\"use_fisheye\":true,"
        "\"mirror_rgb_image\":true,"
        "\"pattern\":\"asymmetric_circles\","
        "\"load\":{\"enabled\":true,\"num_images\":11},"
        "\"asymmetric_circles\":{"
        "\"cols\":4,"
        "\"rows\":11,"
        "\"diagonal_distance_meters\":0.031"
        "}"
        "},"
        "\"translation\":[0.1,0.2,0.3],"
        "\"rotation\":[[1,0,0],[0,1,0],[0,0,1]],"
        "\"project\":{"
        "\"file_version\":4,"
        "\"patterns\":[{\"rows\":[0,1,2,3]}],"
        "\"nodes\":[{\"kind\":\"osc\",\"x\":0.5,\"y\":0.25}]"
        "}"
        "}";
    cJSON *root = cJSON_Parse(json);
    char *rendered = NULL;
    cJSON *parsed = NULL;
    cJSON *translation = NULL;
    cJSON *rotation = NULL;
    cJSON *project = NULL;

    TEST_ASSERT_NOT_NULL(root);
    rendered = cJSON_PrintUnformatted(root);
    TEST_ASSERT_NOT_NULL(rendered);
    parsed = cJSON_Parse(rendered);
    TEST_ASSERT_NOT_NULL(parsed);

    TEST_ASSERT_EQUAL_STRING(
        "StereoCam",
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(parsed, "tracking"),
            "camera_name"
        )->valuestring
    );
    TEST_ASSERT_TRUE(cJSON_IsTrue(
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(parsed, "gui"),
            "use_fisheye"
        )
    ));
    TEST_ASSERT_TRUE(cJSON_IsTrue(
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(parsed, "gui"),
                "load"
            ),
            "enabled"
        )
    ));
    TEST_ASSERT_EQUAL_INT(
        11,
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(parsed, "gui"),
                "load"
            ),
            "num_images"
        )->valueint
    );
    TEST_ASSERT_DOUBLE_WITHIN(
        1e-9,
        0.031,
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(
                cJSON_GetObjectItemCaseSensitive(parsed, "gui"),
                "asymmetric_circles"
            ),
            "diagonal_distance_meters"
        )->valuedouble
    );

    translation = cJSON_GetObjectItemCaseSensitive(parsed, "translation");
    TEST_ASSERT_TRUE(cJSON_IsArray(translation));
    TEST_ASSERT_EQUAL_INT(3, cJSON_GetArraySize(translation));
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.1, cJSON_GetArrayItem(translation, 0)->valuedouble);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.3, cJSON_GetArrayItem(translation, 2)->valuedouble);

    rotation = cJSON_GetObjectItemCaseSensitive(parsed, "rotation");
    TEST_ASSERT_TRUE(cJSON_IsArray(rotation));
    TEST_ASSERT_EQUAL_INT(3, cJSON_GetArraySize(rotation));
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 1.0, cJSON_GetArrayItem(cJSON_GetArrayItem(rotation, 1), 1)->valuedouble);

    project = cJSON_GetObjectItemCaseSensitive(parsed, "project");
    TEST_ASSERT_TRUE(cJSON_IsObject(project));
    TEST_ASSERT_EQUAL_INT(4, cJSON_GetObjectItemCaseSensitive(project, "file_version")->valueint);
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(cJSON_GetObjectItemCaseSensitive(project, "patterns")));
    TEST_ASSERT_EQUAL_STRING(
        "osc",
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetArrayItem(cJSON_GetObjectItemCaseSensitive(project, "nodes"), 0),
            "kind"
        )->valuestring
    );

    cJSON_free(rendered);
    cJSON_Delete(parsed);
    cJSON_Delete(root);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(calibration_and_project_payloads_should_roundtrip_nested_arrays_and_flags);
    return UNITY_END();
}
