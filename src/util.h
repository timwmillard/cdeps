#ifndef UTIL_H
#define UTIL_H

typedef struct File {
    char *name;
    char *ext;
} File;

File file_from_url(const char *url);
void free_file(File parts);

#endif
