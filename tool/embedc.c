/*
 * embedc — embed a file into C source.
 *
 * Copyright (c) 2026 Tim Millard
 * SPDX-License-Identifier: MIT
 *
 * Usage:
 *   embedc [-b|-t] <input> <output> [name]
 *   embedc [-b|-t] -o <output> <input> [input ...]
 *
 *   -b   binary mode (default): emit an `unsigned char <name>_data[]` array
 *        of raw bytes plus an `unsigned int <name>_len`.
 *   -t   text mode: emit a null-terminated `char <name>_data[]` C string
 *        (one source-line literal per input line) plus `<name>_len` (the
 *        string length, excluding the terminator).
 *
 * The -o form embeds multiple inputs in one output. Symbol names are derived
 * from each input filename: the basename with every non-identifier character
 * replaced by '_'.
 */

#include <ctype.h>
#include <stdio.h>
#include <string.h>

static void usage(const char *prog)
{
    fprintf(stderr,
            "usage: %s [-b|-t] <input> <output> [name]\n"
            "       %s [-b|-t] -o <output> <input> [input ...]\n",
            prog, prog);
}

/* Derive a C identifier from a path: basename, non-alnum -> '_'. */
static void derive_name(const char *path, char *out, size_t cap)
{
    const char *base = path;
    for (const char *p = path; *p; p++)
        if (*p == '/' || *p == '\\')
            base = p + 1;

    size_t i = 0;
    for (; base[i] && i + 1 < cap; i++) {
        unsigned char c = (unsigned char)base[i];
        out[i] = (isalnum(c) || c == '_') ? (char)c : '_';
    }
    out[i] = '\0';

    /* A C identifier may not start with a digit. */
    if (i > 0 && isdigit((unsigned char)out[0]) && i + 1 < cap) {
        memmove(out + 1, out, i + 1);
        out[0] = '_';
    }
}

static int emit_binary(FILE *in, FILE *out, const char *name)
{
    unsigned long len = 0;
    int c;

    fprintf(out, "const unsigned char %s_data[] = {", name);
    while ((c = fgetc(in)) != EOF) {
        if (len % 12 == 0)
            fputs("\n\t", out);
        fprintf(out, "0x%02x, ", (unsigned char)c);
        len++;
    }
    fputs("\n};\n", out);
    fprintf(out, "const unsigned int %s_len = %lu;\n", name, len);

    return ferror(in) ? -1 : 0;
}

static int emit_text(FILE *in, FILE *out, const char *name)
{
    unsigned long len = 0;
    int c;

    fprintf(out, "const char %s_data[] =\n\t\"", name);
    while ((c = fgetc(in)) != EOF) {
        unsigned char ch = (unsigned char)c;
        len++;
        switch (ch) {
        case '\\': fputs("\\\\", out); break;
        case '"':  fputs("\\\"", out); break;
        case '\t': fputs("\\t", out);  break;
        case '\r': fputs("\\r", out);  break;
        case '\n': fputs("\\n\"\n\t\"", out); break;
        default:
            if (ch >= 0x20 && ch < 0x7f)
                fputc(ch, out);
            else
                /* 3-digit octal: unambiguous regardless of the next char. */
                fprintf(out, "\\%03o", ch);
        }
    }
    fputs("\";\n", out);
    fprintf(out, "const unsigned int %s_len = %lu;\n", name, len);

    return ferror(in) ? -1 : 0;
}

int main(int argc, char **argv)
{
    int text = 0;
    int argi = 1;
    const char *multi_outpath = NULL;

    for (; argi < argc && argv[argi][0] == '-' && argv[argi][1]; argi++) {
        if (strcmp(argv[argi], "-b") == 0)
            text = 0;
        else if (strcmp(argv[argi], "-t") == 0)
            text = 1;
        else if (strcmp(argv[argi], "-o") == 0) {
            if (multi_outpath || ++argi >= argc) {
                usage(argv[0]);
                return 2;
            }
            multi_outpath = argv[argi];
        }
        else if (strcmp(argv[argi], "--") == 0) {
            argi++;
            break;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    int input_count;
    const char *outpath;
    const char *explicit_name = NULL;

    if (multi_outpath) {
        input_count = argc - argi;
        outpath = multi_outpath;
        if (input_count < 1) {
            usage(argv[0]);
            return 2;
        }

        /* Duplicate basenames would emit duplicate C definitions. */
        for (int i = 0; i < input_count; i++) {
            char left[256];
            derive_name(argv[argi + i], left, sizeof left);
            for (int j = i + 1; j < input_count; j++) {
                char right[256];
                derive_name(argv[argi + j], right, sizeof right);
                if (strcmp(left, right) == 0) {
                    fprintf(stderr,
                            "%s: inputs %s and %s both produce symbol %s\n",
                            argv[0], argv[argi + i], argv[argi + j], left);
                    return 2;
                }
            }
        }
    } else {
        if (argc - argi < 2 || argc - argi > 3) {
            usage(argv[0]);
            return 2;
        }
        input_count = 1;
        outpath = argv[argi + 1];
        if (argc - argi == 3)
            explicit_name = argv[argi + 2];
    }

    FILE *out = fopen(outpath, "w");
    if (!out) {
        perror(outpath);
        return 1;
    }

    int rc = 0;
    for (int i = 0; i < input_count; i++) {
        const char *inpath = argv[argi + i];
        char name[256];
        if (explicit_name)
            snprintf(name, sizeof name, "%s", explicit_name);
        else
            derive_name(inpath, name, sizeof name);

        FILE *in = fopen(inpath, text ? "r" : "rb");
        if (!in) {
            perror(inpath);
            rc = -1;
            break;
        }

        rc = text ? emit_text(in, out, name) : emit_binary(in, out, name);
        fclose(in);
        if (rc != 0) {
            fprintf(stderr, "%s: error processing %s\n", argv[0], inpath);
            break;
        }
    }

    if (fclose(out) != 0)
        rc = -1;

    if (rc != 0) {
        remove(outpath);
        return 1;
    }
    return 0;
}
