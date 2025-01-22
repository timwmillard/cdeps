#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <string.h>
#include <errno.h>


bool is_dir(const char *path)
{
    struct stat path_stat;
    stat(path, &path_stat);
    return S_ISDIR(path_stat.st_mode);
}

bool is_installed(char *program) {
    char buf[1024];
    snprintf(buf, sizeof(buf), "which %s", program);
    FILE *fp = popen(buf, "r");
    if (fp == NULL) {
        return false;
    }

    bool found = (fgets(buf, sizeof(buf), fp) != NULL);
    pclose(fp);
    
    return found;
}

typedef struct {
    char *name;
    char *ext;
} File;

File file_from_url(const char *url) {
    // Get the filename first (everything after last '/')
    const char *filename = strrchr(url, '/');
    if (filename) {
        filename++; // Skip the '/'
    } else {
        filename = url;
    }

    File parts = {0};

   // Check for .tar.gz specifically
    const char *tar_gz = strstr(filename, ".tar.gz");
    if (tar_gz) {
        // Get length of name (excluding .tar.gz)
        size_t name_len = tar_gz - filename;
        parts.name = malloc(name_len + 1);
        if (parts.name) {
            strncpy(parts.name, filename, name_len);
        }
        parts.ext = strdup("tar.gz");
        return parts;
    }

    // Find last occurrence of '.'
    const char *ext = strrchr(filename, '.');
    if (!ext) {
        return parts; // No extension found
    }

    parts.ext = strdup(ext + 1);  // Skip the '.'
                                  // Calculate length of name part
    size_t name_len = ext - filename;
    parts.name = malloc(name_len + 1);
    if (parts.name) {
        strncpy(parts.name, filename, name_len);
    }

    return parts;
}

void free_file(File parts) {
    free(parts.name);
    free(parts.ext);
}

int mkdirp(const char *path, mode_t mode) {
    char tmp[256];
    char *p = NULL;
    size_t len;
    
    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (tmp[len - 1] == '/')
        tmp[len - 1] = 0;
        
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, mode) != 0) {
                if (errno != EEXIST)
                    return -1;
            }
            *p = '/';
        }
    }
    
    if (mkdir(tmp, mode) != 0) {
        if (errno != EEXIST)
            return -1;
    }
    
    return 0;
}

char *parse_filename(const char *url) {
    // Find last occurrence of '/'
    const char *last_slash = strrchr(url, '/');
    if (!last_slash) {
        return NULL;
    }
    
    // Move past the slash to get the filename
    last_slash++;
    
    // Create a new string with the filename
    char *filename = strdup(last_slash);
    if (!filename) {
        return NULL;
    }
    
    return filename;
}

