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

static cJSON *add_stream(cJSON *streams, double sender_bytes, double receiver_bytes)
{
    cJSON *stream = cJSON_CreateObject();
    cJSON *sender = NULL;
    cJSON *receiver = NULL;

    TEST_ASSERT_NOT_NULL(stream);
    TEST_ASSERT_TRUE(cJSON_AddItemToArray(streams, stream));

    sender = cJSON_AddObjectToObject(stream, "sender");
    receiver = cJSON_AddObjectToObject(stream, "receiver");
    TEST_ASSERT_NOT_NULL(sender);
    TEST_ASSERT_NOT_NULL(receiver);
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(sender, "bytes", sender_bytes));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(sender, "bits_per_second", sender_bytes * 8.0));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(receiver, "bytes", receiver_bytes));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(receiver, "bits_per_second", receiver_bytes * 8.0));

    return stream;
}

static cJSON *build_iperf3_like_result(void)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *start = NULL;
    cJSON *intervals = NULL;
    cJSON *interval = NULL;
    cJSON *end = NULL;
    cJSON *streams = NULL;

    TEST_ASSERT_NOT_NULL(root);

    start = cJSON_AddObjectToObject(root, "start");
    intervals = cJSON_AddArrayToObject(root, "intervals");
    end = cJSON_AddObjectToObject(root, "end");
    TEST_ASSERT_NOT_NULL(start);
    TEST_ASSERT_NOT_NULL(intervals);
    TEST_ASSERT_NOT_NULL(end);

    TEST_ASSERT_NOT_NULL(cJSON_AddStringToObject(start, "version", "iperf 3.16"));
    TEST_ASSERT_NOT_NULL(cJSON_AddStringToObject(start, "cookie", "validator-cookie"));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(start, "num_streams", 2.0));

    interval = cJSON_CreateObject();
    TEST_ASSERT_NOT_NULL(interval);
    TEST_ASSERT_TRUE(cJSON_AddItemToArray(intervals, interval));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(interval, "seconds", 1.0));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(interval, "bytes", 131072.0));

    streams = cJSON_AddArrayToObject(end, "streams");
    TEST_ASSERT_NOT_NULL(streams);
    add_stream(streams, 131072.0, 131072.0);
    add_stream(streams, 0.0, 0.0);
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(end, "sum_sent_bytes", 131072.0));
    TEST_ASSERT_NOT_NULL(cJSON_AddNumberToObject(end, "sum_received_bytes", 131072.0));

    return root;
}

static cJSON *roundtrip(cJSON *item, char **rendered_out)
{
    char *rendered = cJSON_PrintUnformatted(item);
    cJSON *parsed = NULL;

    TEST_ASSERT_NOT_NULL(rendered);
    parsed = cJSON_Parse(rendered);
    TEST_ASSERT_NOT_NULL(parsed);
    *rendered_out = rendered;

    return parsed;
}

static void assert_iperf3_top_level_shape(cJSON *root)
{
    TEST_ASSERT_TRUE(cJSON_IsObject(root));
    TEST_ASSERT_NOT_NULL(cJSON_GetObjectItemCaseSensitive(root, "start"));
    TEST_ASSERT_NOT_NULL(cJSON_GetObjectItemCaseSensitive(root, "intervals"));
    TEST_ASSERT_NOT_NULL(cJSON_GetObjectItemCaseSensitive(root, "end"));
    TEST_ASSERT_NULL(cJSON_GetObjectItemCaseSensitive(root, "error"));
    TEST_ASSERT_EQUAL_INT(3, cJSON_GetArraySize(root));
}

static void iperf3_parallel_stream_byte_shape_should_roundtrip(void)
{
    cJSON *root = build_iperf3_like_result();
    char *rendered = NULL;
    cJSON *parsed = roundtrip(root, &rendered);
    cJSON *end = cJSON_GetObjectItemCaseSensitive(parsed, "end");
    cJSON *streams = cJSON_GetObjectItemCaseSensitive(end, "streams");
    cJSON *first = NULL;
    cJSON *second = NULL;
    cJSON *first_sender_bytes = NULL;
    cJSON *first_receiver_bytes = NULL;
    cJSON *second_sender_bytes = NULL;
    cJSON *second_receiver_bytes = NULL;

    assert_iperf3_top_level_shape(parsed);
    TEST_ASSERT_TRUE(cJSON_IsArray(streams));
    TEST_ASSERT_EQUAL_INT(2, cJSON_GetArraySize(streams));

    first = cJSON_GetArrayItem(streams, 0);
    second = cJSON_GetArrayItem(streams, 1);
    first_sender_bytes = cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(first, "sender"),
        "bytes"
    );
    first_receiver_bytes = cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(first, "receiver"),
        "bytes"
    );
    second_sender_bytes = cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(second, "sender"),
        "bytes"
    );
    second_receiver_bytes = cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(second, "receiver"),
        "bytes"
    );

    TEST_ASSERT_TRUE(cJSON_IsNumber(first_sender_bytes));
    TEST_ASSERT_TRUE(cJSON_IsNumber(first_receiver_bytes));
    TEST_ASSERT_TRUE(cJSON_IsNumber(second_sender_bytes));
    TEST_ASSERT_TRUE(cJSON_IsNumber(second_receiver_bytes));
    TEST_ASSERT_EQUAL_INT(131072, first_sender_bytes->valueint);
    TEST_ASSERT_EQUAL_INT(131072, first_receiver_bytes->valueint);
    TEST_ASSERT_EQUAL_INT(0, second_sender_bytes->valueint);
    TEST_ASSERT_EQUAL_INT(0, second_receiver_bytes->valueint);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 131072.0, first_sender_bytes->valuedouble);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 131072.0, first_receiver_bytes->valuedouble);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.0, second_sender_bytes->valuedouble);
    TEST_ASSERT_DOUBLE_WITHIN(1e-9, 0.0, second_receiver_bytes->valuedouble);

    cJSON_free(rendered);
    cJSON_Delete(parsed);
    cJSON_Delete(root);
}

static void iperf3_stdout_and_logfile_shapes_should_match_when_built_with_cjson(void)
{
    cJSON *stdout_root = build_iperf3_like_result();
    cJSON *logfile_root = build_iperf3_like_result();
    char *stdout_rendered = NULL;
    char *logfile_rendered = NULL;
    cJSON *stdout_parsed = roundtrip(stdout_root, &stdout_rendered);
    cJSON *logfile_parsed = roundtrip(logfile_root, &logfile_rendered);

    assert_iperf3_top_level_shape(stdout_parsed);
    assert_iperf3_top_level_shape(logfile_parsed);
    TEST_ASSERT_NULL(strstr(stdout_rendered, "\"error\""));
    TEST_ASSERT_NULL(strstr(logfile_rendered, "\"error\""));

    cJSON_free(logfile_rendered);
    cJSON_free(stdout_rendered);
    cJSON_Delete(logfile_parsed);
    cJSON_Delete(stdout_parsed);
    cJSON_Delete(logfile_root);
    cJSON_Delete(stdout_root);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(iperf3_parallel_stream_byte_shape_should_roundtrip);
    RUN_TEST(iperf3_stdout_and_logfile_shapes_should_match_when_built_with_cjson);
    return UNITY_END();
}
