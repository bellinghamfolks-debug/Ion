#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tree_sitter/api.h>

extern const TSLanguage *tree_sitter_swift(void);

static int inspect(TSNode node, const char *path) {
    int failures = 0;
    if (ts_node_is_error(node) || ts_node_is_missing(node)) {
        TSPoint point = ts_node_start_point(node);
        fprintf(stderr, "%s:%u:%u: syntax node %s%s\n", path,
                point.row + 1, point.column + 1, ts_node_type(node),
                ts_node_is_missing(node) ? " (missing)" : "");
        failures++;
    }
    uint32_t count = ts_node_child_count(node);
    for (uint32_t index = 0; index < count; index++) {
        failures += inspect(ts_node_child(node, index), path);
    }
    return failures;
}

static char *read_file(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    rewind(file);
    if (size < 0) { fclose(file); return NULL; }
    char *bytes = malloc((size_t)size + 1);
    if (!bytes) { fclose(file); return NULL; }
    size_t read = fread(bytes, 1, (size_t)size, file);
    fclose(file);
    bytes[read] = '\0';
    *length = read;
    return bytes;
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    TSParser *parser = ts_parser_new();
    if (!ts_parser_set_language(parser, tree_sitter_swift())) return 3;
    int failures = 0;
    for (int index = 1; index < argc; index++) {
        size_t length = 0;
        char *source = read_file(argv[index], &length);
        if (!source) { fprintf(stderr, "Cannot read %s\n", argv[index]); failures++; continue; }
        TSTree *tree = ts_parser_parse_string(parser, NULL, source, (uint32_t)length);
        failures += inspect(ts_tree_root_node(tree), argv[index]);
        ts_tree_delete(tree);
        free(source);
    }
    ts_parser_delete(parser);
    if (!failures) printf("Swift syntax parse: OK (%d files)\n", argc - 1);
    return failures ? 1 : 0;
}

