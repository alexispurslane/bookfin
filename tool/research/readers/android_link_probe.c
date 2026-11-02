#include <stdio.h>
#include "mobi.h"
#include "fpdfview.h"
#include "fpdf_text.h"

int bookfin_probe_mobi(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) return -1;
    MOBIData *document = mobi_init();
    if (document == NULL) {
        fclose(file);
        return -2;
    }
    MOBI_RET result = mobi_load_file(document, file);
    fclose(file);
    if (result == MOBI_SUCCESS && mobi_is_encrypted(document)) result = MOBI_FILE_ENCRYPTED;
    MOBIRawml *raw = mobi_init_rawml(document);
    if (result == MOBI_SUCCESS && raw != NULL) result = mobi_parse_rawml(raw, document);
    if (raw == NULL) result = MOBI_INIT_FAILED;
    if (raw != NULL) mobi_free_rawml(raw);
    mobi_free(document);
    return (int) result;
}

int bookfin_probe_pdf(const char *path) {
    FPDF_InitLibrary();
    FPDF_DOCUMENT document = FPDF_LoadDocument(path, NULL);
    if (document == NULL) {
        FPDF_DestroyLibrary();
        return -1;
    }
    FPDF_PAGE page = FPDF_LoadPage(document, 0);
    FPDF_TEXTPAGE text = FPDFText_LoadPage(page);
    int count = FPDFText_CountChars(text);
    FPDFText_ClosePage(text);
    FPDF_ClosePage(page);
    FPDF_CloseDocument(document);
    FPDF_DestroyLibrary();
    return count;
}
