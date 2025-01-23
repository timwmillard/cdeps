#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

#include "util.h"

int save_cwd() {
    int saved_dir_fd = open(".", O_RDONLY);
    if (saved_dir_fd == -1) {
        perror("open");
        return -1;
    }
    return saved_dir_fd;
}

// Return to saved directory
void restore_cwd(int saved_dir_fd) {
    if (fchdir(saved_dir_fd) == -1) {
        perror("fchdir");
    }
}

void close_cwd(int saved_dir_fd) {
    close(saved_dir_fd);
}

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
        parts.name = strdup(filename);
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

