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

static void oidc_like_payloads_should_parse_urls_arrays_and_tokens(void)
{
    const char device_json[] =
        "{"
        "\"device_code\":\"dev-123\","
        "\"user_code\":\"ABCD-EFGH\","
        "\"verification_url\":\"https://verify.example/device\","
        "\"verification_url_complete\":\"https://verify.example/device?user_code=ABCD-EFGH\","
        "\"expires_in\":600,"
        "\"interval\":5"
        "}";
    const char account_json[] =
        "{"
        "\"name\":\"demo\","
        "\"issuer_url\":\"https://issuer.example\","
        "\"client_id\":\"cid\","
        "\"client_secret\":\"secret\","
        "\"username\":\"user\","
        "\"password\":\"pw\","
        "\"refresh_token\":\"old-refresh\","
        "\"scope\":\"openid profile\","
        "\"redirect_uris\":[\"http://localhost:4242/callback\"],"
        "\"device_authorization_endpoint\":\"https://issuer.example/device\","
        "\"client_name\":\"Demo Client\","
        "\"daeSetByUser\":1,"
        "\"audience\":\"api://default\""
        "}";
    cJSON *device_root = cJSON_Parse(device_json);
    cJSON *account_root = cJSON_Parse(account_json);
    cJSON *redirect_uris = NULL;
    cJSON *redirect_uri = NULL;

    TEST_ASSERT_NOT_NULL(device_root);
    TEST_ASSERT_NOT_NULL(account_root);
    TEST_ASSERT_EQUAL_STRING(
        "https://verify.example/device",
        cJSON_GetObjectItemCaseSensitive(device_root, "verification_url")->valuestring
    );
    TEST_ASSERT_EQUAL_STRING(
        "https://verify.example/device?user_code=ABCD-EFGH",
        cJSON_GetObjectItemCaseSensitive(device_root, "verification_url_complete")->valuestring
    );
    TEST_ASSERT_EQUAL_INT(
        600,
        cJSON_GetObjectItemCaseSensitive(device_root, "expires_in")->valueint
    );
    TEST_ASSERT_EQUAL_INT(
        5,
        cJSON_GetObjectItemCaseSensitive(device_root, "interval")->valueint
    );

    TEST_ASSERT_EQUAL_STRING(
        "old-refresh",
        cJSON_GetObjectItemCaseSensitive(account_root, "refresh_token")->valuestring
    );
    TEST_ASSERT_EQUAL_STRING(
        "https://issuer.example/device",
        cJSON_GetObjectItemCaseSensitive(account_root, "device_authorization_endpoint")->valuestring
    );
    redirect_uris = cJSON_GetObjectItemCaseSensitive(account_root, "redirect_uris");
    TEST_ASSERT_TRUE(cJSON_IsArray(redirect_uris));
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(redirect_uris));
    redirect_uri = cJSON_GetArrayItem(redirect_uris, 0);
    TEST_ASSERT_TRUE(cJSON_IsString(redirect_uri));
    TEST_ASSERT_EQUAL_STRING("http://localhost:4242/callback", redirect_uri->valuestring);

    cJSON_Delete(account_root);
    cJSON_Delete(device_root);
}

static void musicbrainz_like_payloads_should_parse_nested_releases_tracks_and_joinphrases(void)
{
    const char json[] =
        "{"
        "\"releases\":[{"
        "\"title\":\"Test Album\","
        "\"date\":\"2024-03-14\","
        "\"artist-credit\":[{\"name\":\"Test Artist\"}],"
        "\"media\":[{\"tracks\":[{"
        "\"number\":\"1\","
        "\"title\":\"First Track\","
        "\"recording\":{\"first-release-date\":\"2024-03-15\"},"
        "\"artist-credit\":["
        "{\"name\":\"Track Artist\"},"
        "{\"joinphrase\":\" feat. \"},"
        "{\"name\":\"Guest\"}"
        "]"
        "}]}]"
        "}]"
        "}";
    cJSON *root = cJSON_Parse(json);
    cJSON *releases = NULL;
    cJSON *release = NULL;
    cJSON *media = NULL;
    cJSON *tracks = NULL;
    cJSON *track = NULL;
    cJSON *artist_credit = NULL;

    TEST_ASSERT_NOT_NULL(root);
    releases = cJSON_GetObjectItemCaseSensitive(root, "releases");
    TEST_ASSERT_TRUE(cJSON_IsArray(releases));
    TEST_ASSERT_EQUAL_INT(1, cJSON_GetArraySize(releases));

    release = cJSON_GetArrayItem(releases, 0);
    TEST_ASSERT_TRUE(cJSON_IsObject(release));
    TEST_ASSERT_EQUAL_STRING("Test Album", cJSON_GetObjectItemCaseSensitive(release, "title")->valuestring);
    TEST_ASSERT_EQUAL_STRING("2024-03-14", cJSON_GetObjectItemCaseSensitive(release, "date")->valuestring);

    media = cJSON_GetObjectItemCaseSensitive(release, "media");
    TEST_ASSERT_TRUE(cJSON_IsArray(media));
    tracks = cJSON_GetObjectItemCaseSensitive(cJSON_GetArrayItem(media, 0), "tracks");
    TEST_ASSERT_TRUE(cJSON_IsArray(tracks));
    track = cJSON_GetArrayItem(tracks, 0);
    TEST_ASSERT_EQUAL_STRING("First Track", cJSON_GetObjectItemCaseSensitive(track, "title")->valuestring);
    TEST_ASSERT_EQUAL_STRING(
        "2024-03-15",
        cJSON_GetObjectItemCaseSensitive(
            cJSON_GetObjectItemCaseSensitive(track, "recording"),
            "first-release-date"
        )->valuestring
    );

    artist_credit = cJSON_GetObjectItemCaseSensitive(track, "artist-credit");
    TEST_ASSERT_TRUE(cJSON_IsArray(artist_credit));
    TEST_ASSERT_EQUAL_STRING("Track Artist", cJSON_GetObjectItemCaseSensitive(cJSON_GetArrayItem(artist_credit, 0), "name")->valuestring);
    TEST_ASSERT_EQUAL_STRING(" feat. ", cJSON_GetObjectItemCaseSensitive(cJSON_GetArrayItem(artist_credit, 1), "joinphrase")->valuestring);
    TEST_ASSERT_EQUAL_STRING("Guest", cJSON_GetObjectItemCaseSensitive(cJSON_GetArrayItem(artist_credit, 2), "name")->valuestring);

    cJSON_Delete(root);
}

int CJSON_CDECL main(void)
{
    UNITY_BEGIN();
    RUN_TEST(oidc_like_payloads_should_parse_urls_arrays_and_tokens);
    RUN_TEST(musicbrainz_like_payloads_should_parse_nested_releases_tracks_and_joinphrases);
    return UNITY_END();
}
