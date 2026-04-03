#include <locale.h>
#include <stdio.h>
#include <stddef.h>

#include "cJSON.h"

static ptrdiff_t pointer_offset(const char *base, const char *pointer)
{
    if (pointer == NULL)
    {
        return -1;
    }

    return pointer - base;
}

int main(void)
{
    const char json[] = "[1.5]";
    const char *parse_end = NULL;
    cJSON *parsed = NULL;
    cJSON *number = NULL;
    char *printed = NULL;
    long parse_end_offset = -1;
    long error_offset = -1;

    if (setlocale(LC_ALL, "") == NULL)
    {
        fprintf(stderr, "setlocale failed\n");
        return 1;
    }

    parsed = cJSON_ParseWithOpts(json, &parse_end, 1);
    number = cJSON_CreateNumber(1.5);
    printed = cJSON_PrintUnformatted(number);
    parse_end_offset = (long)pointer_offset(json, parse_end);
    error_offset = (long)pointer_offset(json, cJSON_GetErrorPtr());

    printf("parse=%s\n", (parsed != NULL) ? "ok" : "fail");
    printf("parse_end=%ld\n", parse_end_offset);
    printf("error=%ld\n", error_offset);
    printf("printed=%s\n", (printed != NULL) ? printed : "(null)");

    cJSON_free(printed);
    cJSON_Delete(number);
    cJSON_Delete(parsed);

    return 0;
}
