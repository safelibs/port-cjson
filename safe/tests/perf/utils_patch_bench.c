/*
  Copyright (c) 2026
*/

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "cJSON_Utils.h"

typedef struct
{
    char *name;
    cJSON *doc;
    cJSON *patch;
    int expect_error;
} apply_case;

typedef struct
{
    char *name;
    cJSON *from;
    cJSON *to;
} diff_case;

typedef struct
{
    apply_case *apply_cases;
    size_t apply_count;
    diff_case *diff_cases;
    size_t diff_count;
    unsigned long apply_doc_nodes;
    unsigned long apply_patch_nodes;
    unsigned long diff_from_nodes;
    unsigned long diff_to_nodes;
} bench_state;

static void fail(const char *message, const char *detail)
{
    if (detail != NULL)
    {
        fprintf(stderr, "utils_patch_bench: %s: %s\n", message, detail);
    }
    else
    {
        fprintf(stderr, "utils_patch_bench: %s\n", message);
    }
    exit(EXIT_FAILURE);
}

static void *xmalloc(size_t size)
{
    void *memory = NULL;

    memory = malloc(size);
    if (memory == NULL)
    {
        fail("out of memory", NULL);
    }

    return memory;
}

static void *xrealloc(void *pointer, size_t size)
{
    void *memory = NULL;

    memory = realloc(pointer, size);
    if ((memory == NULL) && (size != 0))
    {
        fail("out of memory", NULL);
    }

    return memory;
}

static char *xstrdup(const char *string)
{
    size_t length = 0;
    char *copy = NULL;

    length = strlen(string);
    copy = (char*)xmalloc(length + 1);
    memcpy(copy, string, length + 1);

    return copy;
}

static char *read_file(const char *path, size_t *length_out)
{
    FILE *file = NULL;
    long length = 0;
    char *content = NULL;
    size_t read_chars = 0;

    file = fopen(path, "rb");
    if (file == NULL)
    {
        fail("failed to open file", path);
    }

    if (fseek(file, 0, SEEK_END) != 0)
    {
        fclose(file);
        fail("failed to seek file", path);
    }

    length = ftell(file);
    if (length < 0)
    {
        fclose(file);
        fail("failed to determine file length", path);
    }

    if (fseek(file, 0, SEEK_SET) != 0)
    {
        fclose(file);
        fail("failed to rewind file", path);
    }

    content = (char*)xmalloc((size_t)length + 1);
    read_chars = fread(content, sizeof(char), (size_t)length, file);
    if ((long)read_chars != length)
    {
        fclose(file);
        free(content);
        fail("failed to read file", path);
    }
    content[read_chars] = '\0';

    fclose(file);
    *length_out = (size_t)length;
    return content;
}

static cJSON *duplicate_or_fail(const cJSON *item, const char *context)
{
    cJSON *copy = NULL;

    copy = cJSON_Duplicate(item, 1);
    if (copy == NULL)
    {
        fail("cJSON_Duplicate failed", context);
    }

    return copy;
}

static char *make_case_name(const char *path, size_t index)
{
    const char *basename = NULL;
    char buffer[128];

    basename = strrchr(path, '/');
    if (basename == NULL)
    {
        basename = path;
    }
    else
    {
        basename++;
    }

    sprintf(buffer, "%s[%lu]", basename, (unsigned long)index);
    return xstrdup(buffer);
}

static unsigned long count_nodes(const cJSON *item)
{
    unsigned long total = 0;

    while (item != NULL)
    {
        total++;
        if (item->child != NULL)
        {
            total += count_nodes(item->child);
        }
        item = item->next;
    }

    return total;
}

static void append_apply_case(
    bench_state *state,
    const char *name,
    const cJSON *doc,
    const cJSON *patch,
    int expect_error
)
{
    apply_case *slot = NULL;

    state->apply_cases = (apply_case*)xrealloc(
        state->apply_cases,
        sizeof(apply_case) * (state->apply_count + 1)
    );

    slot = &state->apply_cases[state->apply_count];
    slot->name = xstrdup(name);
    slot->doc = duplicate_or_fail(doc, name);
    slot->patch = duplicate_or_fail(patch, name);
    slot->expect_error = expect_error;
    state->apply_count++;
    state->apply_doc_nodes += count_nodes(doc);
    state->apply_patch_nodes += count_nodes(patch);
}

static void append_diff_case(bench_state *state, const char *name, const cJSON *from, const cJSON *to)
{
    diff_case *slot = NULL;

    state->diff_cases = (diff_case*)xrealloc(
        state->diff_cases,
        sizeof(diff_case) * (state->diff_count + 1)
    );

    slot = &state->diff_cases[state->diff_count];
    slot->name = xstrdup(name);
    slot->from = duplicate_or_fail(from, name);
    slot->to = duplicate_or_fail(to, name);
    state->diff_count++;
    state->diff_from_nodes += count_nodes(from);
    state->diff_to_nodes += count_nodes(to);
}

static void load_fixture_file(bench_state *state, const char *path)
{
    char *content = NULL;
    size_t content_length = 0;
    cJSON *tests = NULL;
    cJSON *test = NULL;
    size_t index = 0;

    content = read_file(path, &content_length);
    tests = cJSON_ParseWithLengthOpts(content, content_length, NULL, 0);
    if ((tests == NULL) || !cJSON_IsArray(tests))
    {
        free(content);
        if (tests != NULL)
        {
            cJSON_Delete(tests);
        }
        fail("failed to parse fixture file", path);
    }

    cJSON_ArrayForEach(test, tests)
    {
        cJSON *disabled = NULL;
        cJSON *doc = NULL;
        cJSON *patch = NULL;
        cJSON *expected = NULL;
        cJSON *error_element = NULL;
        char *name = NULL;

        disabled = cJSON_GetObjectItemCaseSensitive(test, "disabled");
        if (cJSON_IsTrue(disabled))
        {
            index++;
            continue;
        }

        name = make_case_name(path, index);
        doc = cJSON_GetObjectItemCaseSensitive(test, "doc");
        patch = cJSON_GetObjectItemCaseSensitive(test, "patch");
        expected = cJSON_GetObjectItemCaseSensitive(test, "expected");
        error_element = cJSON_GetObjectItemCaseSensitive(test, "error");

        if ((doc != NULL) && (patch != NULL))
        {
            append_apply_case(state, name, doc, patch, error_element != NULL);
        }

        if ((doc != NULL) && (expected != NULL))
        {
            append_diff_case(state, name, doc, expected);
        }

        free(name);
        index++;
    }

    cJSON_Delete(tests);
    free(content);
}

static void add_number_item_to_array(cJSON *array, double value, const char *context)
{
    cJSON *item = NULL;

    item = cJSON_CreateNumber(value);
    if (item == NULL)
    {
        fail("cJSON_CreateNumber failed", context);
    }

    if (!cJSON_AddItemToArray(array, item))
    {
        cJSON_Delete(item);
        fail("cJSON_AddItemToArray failed", context);
    }
}

static void add_item_to_object(cJSON *object, const char *name, cJSON *item, const char *context)
{
    if (item == NULL)
    {
        fail("cJSON item creation failed", context);
    }

    if (!cJSON_AddItemToObject(object, name, item))
    {
        cJSON_Delete(item);
        fail("cJSON_AddItemToObject failed", context);
    }
}

static void create_large_pair(cJSON **from_out, cJSON **to_out)
{
    const unsigned long member_count = 1024;
    unsigned long index = 0;
    cJSON *from = NULL;
    cJSON *to = NULL;
    cJSON *from_array = NULL;
    cJSON *to_array = NULL;
    char key[32];

    from = cJSON_CreateObject();
    to = cJSON_CreateObject();
    if ((from == NULL) || (to == NULL))
    {
        if (from != NULL)
        {
            cJSON_Delete(from);
        }
        if (to != NULL)
        {
            cJSON_Delete(to);
        }
        fail("failed to create large benchmark objects", NULL);
    }

    for (index = 0; index < member_count; index++)
    {
        sprintf(key, "item%04lu", index);

        if ((index % 11UL) != 0UL)
        {
            if (cJSON_AddNumberToObject(from, key, (double)index) == NULL)
            {
                cJSON_Delete(from);
                cJSON_Delete(to);
                fail("failed to populate generated source object", key);
            }
        }

        if ((index % 7UL) != 0UL)
        {
            double value = (double)index;

            if ((index % 5UL) == 0UL)
            {
                value = (double)(index + 1000UL);
            }

            if (cJSON_AddNumberToObject(to, key, value) == NULL)
            {
                cJSON_Delete(from);
                cJSON_Delete(to);
                fail("failed to populate generated destination object", key);
            }
        }
    }

    from_array = cJSON_CreateArray();
    to_array = cJSON_CreateArray();
    if ((from_array == NULL) || (to_array == NULL))
    {
        if (from_array != NULL)
        {
            cJSON_Delete(from_array);
        }
        if (to_array != NULL)
        {
            cJSON_Delete(to_array);
        }
        cJSON_Delete(from);
        cJSON_Delete(to);
        fail("failed to create generated sequence arrays", NULL);
    }

    for (index = 0; index < 256UL; index++)
    {
        add_number_item_to_array(from_array, (double)index, "generated-from-sequence");
        if ((index % 9UL) == 0UL)
        {
            add_number_item_to_array(to_array, (double)(index + 1UL), "generated-to-sequence");
        }
        else
        {
            add_number_item_to_array(to_array, (double)index, "generated-to-sequence");
        }
    }
    add_number_item_to_array(to_array, 4096.0, "generated-to-sequence-tail");

    add_item_to_object(from, "sequence", from_array, "generated-source");
    add_item_to_object(to, "sequence", to_array, "generated-destination");

    *from_out = from;
    *to_out = to;
}

static void append_large_generated_cases(bench_state *state)
{
    const char *name = "generated-large-object";
    cJSON *from = NULL;
    cJSON *to = NULL;
    cJSON *from_copy = NULL;
    cJSON *to_copy = NULL;
    cJSON *patch = NULL;

    create_large_pair(&from, &to);

    from_copy = duplicate_or_fail(from, name);
    to_copy = duplicate_or_fail(to, name);
    patch = cJSONUtils_GeneratePatchesCaseSensitive(from_copy, to_copy);
    if (patch == NULL)
    {
        cJSON_Delete(from);
        cJSON_Delete(to);
        cJSON_Delete(from_copy);
        cJSON_Delete(to_copy);
        fail("failed to generate large benchmark patch", name);
    }

    append_apply_case(state, name, from, patch, 0);
    append_diff_case(state, name, from, to);

    cJSON_Delete(from);
    cJSON_Delete(to);
    cJSON_Delete(from_copy);
    cJSON_Delete(to_copy);
    cJSON_Delete(patch);
}

static unsigned long run_apply(const bench_state *state, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < state->apply_count; index++)
        {
            cJSON *object = NULL;
            int result = 0;

            object = duplicate_or_fail(state->apply_cases[index].doc, state->apply_cases[index].name);
            result = cJSONUtils_ApplyPatchesCaseSensitive(object, state->apply_cases[index].patch);

            if (state->apply_cases[index].expect_error)
            {
                if (result == 0)
                {
                    cJSON_Delete(object);
                    fail("patch unexpectedly succeeded", state->apply_cases[index].name);
                }
                checksum += 1UL;
            }
            else
            {
                if (result != 0)
                {
                    cJSON_Delete(object);
                    fail("patch unexpectedly failed", state->apply_cases[index].name);
                }
                checksum += count_nodes(object);
            }

            cJSON_Delete(object);
        }
    }

    return checksum;
}

static unsigned long run_generate(const bench_state *state, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < state->diff_count; index++)
        {
            cJSON *from = NULL;
            cJSON *to = NULL;
            cJSON *patch = NULL;

            from = duplicate_or_fail(state->diff_cases[index].from, state->diff_cases[index].name);
            to = duplicate_or_fail(state->diff_cases[index].to, state->diff_cases[index].name);
            patch = cJSONUtils_GeneratePatchesCaseSensitive(from, to);
            if (patch == NULL)
            {
                cJSON_Delete(from);
                cJSON_Delete(to);
                fail("cJSONUtils_GeneratePatchesCaseSensitive failed", state->diff_cases[index].name);
            }

            checksum += count_nodes(patch);

            cJSON_Delete(patch);
            cJSON_Delete(from);
            cJSON_Delete(to);
        }
    }

    return checksum;
}

static unsigned long run_merge(const bench_state *state, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < state->diff_count; index++)
        {
            cJSON *from = NULL;
            cJSON *to = NULL;
            cJSON *patch = NULL;

            from = duplicate_or_fail(state->diff_cases[index].from, state->diff_cases[index].name);
            to = duplicate_or_fail(state->diff_cases[index].to, state->diff_cases[index].name);
            patch = cJSONUtils_GenerateMergePatchCaseSensitive(from, to);
            if (patch != NULL)
            {
                checksum += count_nodes(patch);
                cJSON_Delete(patch);
            }
            else
            {
                checksum += 1UL;
            }

            cJSON_Delete(from);
            cJSON_Delete(to);
        }
    }

    return checksum;
}

static void destroy_state(bench_state *state)
{
    size_t index = 0;

    for (index = 0; index < state->apply_count; index++)
    {
        free(state->apply_cases[index].name);
        cJSON_Delete(state->apply_cases[index].doc);
        cJSON_Delete(state->apply_cases[index].patch);
    }

    for (index = 0; index < state->diff_count; index++)
    {
        free(state->diff_cases[index].name);
        cJSON_Delete(state->diff_cases[index].from);
        cJSON_Delete(state->diff_cases[index].to);
    }

    free(state->apply_cases);
    free(state->diff_cases);
    state->apply_cases = NULL;
    state->diff_cases = NULL;
    state->apply_count = 0;
    state->diff_count = 0;
    state->apply_doc_nodes = 0;
    state->apply_patch_nodes = 0;
    state->diff_from_nodes = 0;
    state->diff_to_nodes = 0;
}

static unsigned long parse_iterations(const char *text)
{
    char *parse_end = NULL;
    unsigned long iterations = 0;

    errno = 0;
    iterations = strtoul(text, &parse_end, 10);
    if ((errno != 0) || (parse_end == text) || (*parse_end != '\0') || (iterations == 0))
    {
        fail("invalid iteration count", text);
    }

    return iterations;
}

static const char *usage(void)
{
    return "usage: utils_patch_bench <apply|generate|merge> <tests.json> <spec_tests.json> <cjson-utils-tests.json> <iterations>";
}

int main(int argc, char **argv)
{
    const char *mode = NULL;
    unsigned long iterations = 0;
    bench_state state;
    unsigned long checksum = 0;

    memset(&state, 0, sizeof(state));

    if (argc != 6)
    {
        fprintf(stderr, "%s\n", usage());
        return EXIT_FAILURE;
    }

    mode = argv[1];
    iterations = parse_iterations(argv[5]);

    load_fixture_file(&state, argv[2]);
    load_fixture_file(&state, argv[3]);
    load_fixture_file(&state, argv[4]);
    append_large_generated_cases(&state);

    if (state.apply_count == 0)
    {
        destroy_state(&state);
        fail("no apply cases available", NULL);
    }
    if (state.diff_count == 0)
    {
        destroy_state(&state);
        fail("no generate/merge cases available", NULL);
    }

    if (strcmp(mode, "apply") == 0)
    {
        checksum = run_apply(&state, iterations);
    }
    else if (strcmp(mode, "generate") == 0)
    {
        checksum = run_generate(&state, iterations);
    }
    else if (strcmp(mode, "merge") == 0)
    {
        checksum = run_merge(&state, iterations);
    }
    else
    {
        destroy_state(&state);
        fprintf(stderr, "%s\n", usage());
        return EXIT_FAILURE;
    }

    printf(
        "mode=%s iterations=%lu apply_cases=%lu apply_doc_nodes=%lu apply_patch_nodes=%lu diff_cases=%lu diff_from_nodes=%lu diff_to_nodes=%lu checksum=%lu\n",
        mode,
        iterations,
        (unsigned long)state.apply_count,
        state.apply_doc_nodes,
        state.apply_patch_nodes,
        (unsigned long)state.diff_count,
        state.diff_from_nodes,
        state.diff_to_nodes,
        checksum
    );

    destroy_state(&state);
    return EXIT_SUCCESS;
}
