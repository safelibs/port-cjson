/*
  Copyright (c) 2026
*/

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"

typedef struct
{
    char *name;
    char *storage;
    const char *payload;
    size_t payload_length;
    cJSON *parsed;
    int print_prebuffer;
} bench_entry;

typedef struct
{
    bench_entry *entries;
    size_t count;
    size_t print_ready_count;
    size_t total_payload_bytes;
    size_t print_ready_payload_bytes;
} bench_corpus;

static void fail(const char *message, const char *detail)
{
    if (detail != NULL)
    {
        fprintf(stderr, "parse_print_bench: %s: %s\n", message, detail);
    }
    else
    {
        fprintf(stderr, "parse_print_bench: %s\n", message);
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

static char *join_path(const char *directory, const char *name)
{
    size_t directory_length = 0;
    size_t name_length = 0;
    char *path = NULL;

    directory_length = strlen(directory);
    name_length = strlen(name);
    path = (char*)xmalloc(directory_length + name_length + 2);
    memcpy(path, directory, directory_length);
    path[directory_length] = '/';
    memcpy(path + directory_length + 1, name, name_length + 1);

    return path;
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

static int compare_cstrings(const void *left, const void *right)
{
    const char * const *left_string = (const char * const *)left;
    const char * const *right_string = (const char * const *)right;

    return strcmp(*left_string, *right_string);
}

static char **list_files(const char *directory, size_t *count_out)
{
    DIR *dir = NULL;
    struct dirent *entry = NULL;
    char **names = NULL;
    size_t count = 0;

    dir = opendir(directory);
    if (dir == NULL)
    {
        fail("failed to open directory", directory);
    }

    for (entry = readdir(dir); entry != NULL; entry = readdir(dir))
    {
        if (entry->d_name[0] == '.')
        {
            continue;
        }

        names = (char**)xrealloc(names, sizeof(char*) * (count + 1));
        names[count] = xstrdup(entry->d_name);
        count++;
    }

    closedir(dir);

    qsort(names, count, sizeof(char*), compare_cstrings);
    *count_out = count;

    return names;
}

static size_t fuzz_prefix_length(const char *data, size_t length)
{
    if ((length > 2) &&
        ((data[0] == 'b') || (data[0] == 'u')) &&
        ((data[1] == 'f') || (data[1] == 'u')))
    {
        return 2;
    }

    if ((length > 4) &&
        ((data[0] == '0') || (data[0] == '1')) &&
        ((data[1] == '0') || (data[1] == '1')) &&
        ((data[2] == '0') || (data[2] == '1')) &&
        ((data[3] == '0') || (data[3] == '1')))
    {
        return 4;
    }

    return 0;
}

static char *append_unsigned(char *cursor, unsigned long value)
{
    char digits[32];
    size_t count = 0;

    do
    {
        digits[count] = (char)('0' + (value % 10));
        value /= 10;
        count++;
    }
    while (value != 0);

    while (count > 0)
    {
        count--;
        *cursor = digits[count];
        cursor++;
    }

    return cursor;
}

static char *append_padded_unsigned(char *cursor, unsigned long value, size_t width)
{
    char digits[32];
    size_t count = 0;

    do
    {
        digits[count] = (char)('0' + (value % 10));
        value /= 10;
        count++;
    }
    while (value != 0);

    while (count < width)
    {
        digits[count] = '0';
        count++;
    }

    while (count > 0)
    {
        count--;
        *cursor = digits[count];
        cursor++;
    }

    return cursor;
}

static char *build_large_object(void)
{
    const unsigned long member_count = 1024;
    const size_t estimated_size = (size_t)(member_count * 96UL) + 32;
    char *json = NULL;
    char *cursor = NULL;
    unsigned long index = 0;
    unsigned long value_index = 0;

    json = (char*)xmalloc(estimated_size);
    cursor = json;

    *cursor = '{';
    cursor++;
    *cursor = '\n';
    cursor++;

    for (index = 0; index < member_count; index++)
    {
        if (index != 0)
        {
            *cursor = ',';
            cursor++;
            *cursor = '\n';
            cursor++;
        }

        memcpy(cursor, "  \"item", 7);
        cursor += 7;
        cursor = append_padded_unsigned(cursor, index, 4);
        memcpy(cursor, "\": [", 4);
        cursor += 4;

        for (value_index = 0; value_index < 5; value_index++)
        {
            if (value_index != 0)
            {
                memcpy(cursor, ", ", 2);
                cursor += 2;
            }
            cursor = append_unsigned(cursor, (index * 7UL) + value_index);
        }

        *cursor = ']';
        cursor++;
    }

    *cursor = '\n';
    cursor++;
    *cursor = '}';
    cursor++;
    *cursor = '\0';

    return json;
}

static void append_entry(bench_corpus *corpus, const char *name, char *storage, size_t storage_length, size_t prefix_length)
{
    bench_entry *entry = NULL;

    corpus->entries = (bench_entry*)xrealloc(corpus->entries, sizeof(bench_entry) * (corpus->count + 1));
    entry = &corpus->entries[corpus->count];
    entry->name = xstrdup(name);
    entry->storage = storage;
    entry->payload = storage + prefix_length;
    entry->payload_length = storage_length - prefix_length;
    entry->parsed = NULL;
    if (entry->payload_length > (size_t)(INT_MAX - 32))
    {
        fail("input too large for print buffer sizing", name);
    }
    entry->print_prebuffer = (int)entry->payload_length + 32;
    corpus->count++;
    corpus->total_payload_bytes += entry->payload_length;
}

static void load_directory(bench_corpus *corpus, const char *directory, int strip_fuzz_prefix)
{
    char **names = NULL;
    size_t count = 0;
    size_t index = 0;

    names = list_files(directory, &count);

    for (index = 0; index < count; index++)
    {
        char *path = NULL;
        char *storage = NULL;
        size_t storage_length = 0;
        size_t prefix_length = 0;

        path = join_path(directory, names[index]);
        storage = read_file(path, &storage_length);
        if (strip_fuzz_prefix)
        {
            prefix_length = fuzz_prefix_length(storage, storage_length);
        }
        append_entry(corpus, names[index], storage, storage_length, prefix_length);
        free(path);
        free(names[index]);
    }

    free(names);
}

static void prepare_print_inputs(bench_corpus *corpus)
{
    size_t index = 0;

    for (index = 0; index < corpus->count; index++)
    {
        const char *parse_end = NULL;
        cJSON *parsed = NULL;

        parsed = cJSON_ParseWithLengthOpts(
            corpus->entries[index].payload,
            corpus->entries[index].payload_length,
            &parse_end,
            0
        );

        (void)parse_end;

        if (parsed != NULL)
        {
            corpus->entries[index].parsed = parsed;
            corpus->print_ready_count++;
            corpus->print_ready_payload_bytes += corpus->entries[index].payload_length;
        }
    }

    if (corpus->print_ready_count == 0)
    {
        fail("no parseable inputs available for print workloads", NULL);
    }
}

static unsigned long run_parse(const bench_corpus *corpus, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < corpus->count; index++)
        {
            const char *parse_end = NULL;
            cJSON *parsed = NULL;

            parsed = cJSON_ParseWithLengthOpts(
                corpus->entries[index].payload,
                corpus->entries[index].payload_length,
                &parse_end,
                0
            );

            if ((parse_end != NULL) &&
                (parse_end >= corpus->entries[index].payload) &&
                ((size_t)(parse_end - corpus->entries[index].payload) <= corpus->entries[index].payload_length))
            {
                checksum += (unsigned long)(parse_end - corpus->entries[index].payload);
            }

            if (parsed != NULL)
            {
                checksum += (unsigned long)(parsed->type & 0xFF);
                cJSON_Delete(parsed);
            }
            else
            {
                checksum += 1UL;
            }
        }
    }

    return checksum;
}

static unsigned long run_print_unformatted(const bench_corpus *corpus, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < corpus->count; index++)
        {
            char *printed = NULL;

            if (corpus->entries[index].parsed == NULL)
            {
                continue;
            }

            printed = cJSON_PrintUnformatted(corpus->entries[index].parsed);
            if (printed == NULL)
            {
                fail("cJSON_PrintUnformatted failed", corpus->entries[index].name);
            }

            checksum += (unsigned long)strlen(printed);
            cJSON_free(printed);
        }
    }

    return checksum;
}

static unsigned long run_print_buffered(const bench_corpus *corpus, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < corpus->count; index++)
        {
            char *printed = NULL;

            if (corpus->entries[index].parsed == NULL)
            {
                continue;
            }

            printed = cJSON_PrintBuffered(corpus->entries[index].parsed, corpus->entries[index].print_prebuffer, 0);
            if (printed == NULL)
            {
                fail("cJSON_PrintBuffered failed", corpus->entries[index].name);
            }

            checksum += (unsigned long)strlen(printed);
            cJSON_free(printed);
        }
    }

    return checksum;
}

static unsigned long run_minify(const bench_corpus *corpus, unsigned long iterations)
{
    unsigned long checksum = 0;
    unsigned long iteration = 0;
    size_t index = 0;

    for (iteration = 0; iteration < iterations; iteration++)
    {
        for (index = 0; index < corpus->count; index++)
        {
            char *copy = NULL;

            copy = (char*)xmalloc(corpus->entries[index].payload_length + 1);
            memcpy(copy, corpus->entries[index].payload, corpus->entries[index].payload_length);
            copy[corpus->entries[index].payload_length] = '\0';

            cJSON_Minify(copy);
            checksum += (unsigned long)strlen(copy);

            free(copy);
        }
    }

    return checksum;
}

static void destroy_corpus(bench_corpus *corpus)
{
    size_t index = 0;

    for (index = 0; index < corpus->count; index++)
    {
        free(corpus->entries[index].name);
        free(corpus->entries[index].storage);
        if (corpus->entries[index].parsed != NULL)
        {
            cJSON_Delete(corpus->entries[index].parsed);
        }
    }

    free(corpus->entries);
    corpus->entries = NULL;
    corpus->count = 0;
    corpus->print_ready_count = 0;
    corpus->total_payload_bytes = 0;
    corpus->print_ready_payload_bytes = 0;
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
    return "usage: parse_print_bench <parse|print-unformatted|print-buffered|minify> <tests-input-dir> <fuzz-input-dir> <iterations>";
}

int main(int argc, char **argv)
{
    const char *mode = NULL;
    const char *tests_input_dir = NULL;
    const char *fuzz_input_dir = NULL;
    unsigned long iterations = 0;
    bench_corpus corpus;
    char *large_object = NULL;
    unsigned long checksum = 0;

    memset(&corpus, 0, sizeof(corpus));

    if (argc != 5)
    {
        fprintf(stderr, "%s\n", usage());
        return EXIT_FAILURE;
    }

    mode = argv[1];
    tests_input_dir = argv[2];
    fuzz_input_dir = argv[3];
    iterations = parse_iterations(argv[4]);

    load_directory(&corpus, tests_input_dir, 0);
    load_directory(&corpus, fuzz_input_dir, 1);
    large_object = build_large_object();
    append_entry(&corpus, "generated-large-object", large_object, strlen(large_object), 0);
    prepare_print_inputs(&corpus);

    if (strcmp(mode, "parse") == 0)
    {
        checksum = run_parse(&corpus, iterations);
    }
    else if (strcmp(mode, "print-unformatted") == 0)
    {
        checksum = run_print_unformatted(&corpus, iterations);
    }
    else if (strcmp(mode, "print-buffered") == 0)
    {
        checksum = run_print_buffered(&corpus, iterations);
    }
    else if (strcmp(mode, "minify") == 0)
    {
        checksum = run_minify(&corpus, iterations);
    }
    else
    {
        destroy_corpus(&corpus);
        fprintf(stderr, "%s\n", usage());
        return EXIT_FAILURE;
    }

    printf(
        "mode=%s iterations=%lu corpus=%lu payload_bytes=%lu print_ready=%lu print_ready_bytes=%lu checksum=%lu\n",
        mode,
        iterations,
        (unsigned long)corpus.count,
        (unsigned long)corpus.total_payload_bytes,
        (unsigned long)corpus.print_ready_count,
        (unsigned long)corpus.print_ready_payload_bytes,
        checksum
    );

    destroy_corpus(&corpus);
    return EXIT_SUCCESS;
}
