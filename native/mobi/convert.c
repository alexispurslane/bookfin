#define main bookfin_unused_tool_main
#include "mobitool.c"
#undef main

int bookfin_convert(const char *path) {
    if (path == NULL) return -1;
    FILE *file = fopen(path, "rb");
    if (file == NULL) return -2;
    MOBIData *document = mobi_init();
    if (document == NULL) {
        fclose(file);
        return -3;
    }
    MOBI_RET result = mobi_load_file(document, file);
    fclose(file);
    if (result == MOBI_SUCCESS && mobi_is_encrypted(document)) result = MOBI_FILE_ENCRYPTED;
    MOBIRawml *raw = NULL;
    if (result == MOBI_SUCCESS) {
        raw = mobi_init_rawml(document);
        result = raw == NULL ? MOBI_INIT_FAILED : mobi_parse_rawml(raw, document);
    }
    if (result == MOBI_SUCCESS && create_epub(raw, path) != SUCCESS) result = MOBI_WRITE_FAILED;
    if (raw != NULL) mobi_free_rawml(raw);
    mobi_free(document);
    return (int) result;
}
