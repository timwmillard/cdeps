#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>

#define VERSION "0.0.1"

#include "util.c"
#include "config.c"

static void version(void)
{
    printf("deps version " VERSION "\n");
}

void usage()
{
    printf("deps is a dependency manager for C.\n\n");
    printf("Usage:\n");
    printf("  deps [OPTIONS] [COMMAND]\n");

    printf("\nOptions:\n");
    printf("  -h, --help                        show this help, then exit\n");
    printf("  -v, --version                     output version information\n");
    printf("\nCommands:\n");
    printf("  get                               download dependecies\n");
    printf("  build                             get, build dependecies\n");
    printf("  install                           get, build & install dependecies\n");
    printf("  new [PROJECT_NAME]                create a black project setup\n");
    printf("  config                            print config\n");
    printf("\n");
}


struct options {
    char *command;
    int argc;
    char** argv;
};

static void parse_options(int argc, char *argv[], struct options *opts) 
{
    int ch;

    /* options descriptor */
    static struct option longopts[] = {
        { "help",        no_argument,       NULL, 'h' },
        { "version",     no_argument,       NULL, 'v' },
        { NULL,          0,                 NULL,  0  }
    };

    while ((ch = getopt_long(argc, argv, "hv", longopts, NULL)) != -1) {
        switch (ch) {
            case 'v':
                version();
                exit(0);
            case 'h':
                usage();
                exit(0);
            default:
                fprintf(stderr, "Try: deps --help\n");
                exit(1);
        }
    }
    argc -= optind;
    argv += optind;

    if (argc > 0) {
        opts->command = argv[0];
        argc -= 1;
        argv += 1;
    }
    opts->argc = argc;
    opts->argv = argv;
}

void cmd_get(Config *config) {
    if (config->num_deps < 1) {
        return;
    }

    printf("mkdir %s\n", config->location);
    mkdir(config->location, 0755);

    printf("Downloading dependencies ...\n");
    char cmd[2048];
    for (int i = 0; i < config->num_deps; i++) {
        Dependency dep = config->deps[i];
        printf("   downloading %s ...\n", dep.name);

        char *url = dep.url;
        char *name = dep.name;
        char *version = dep.version;
        File file = file_from_url(url);

        char filename[256];
        snprintf(filename, sizeof(filename), "%s.%s", file.name, file.ext);

        chdir(config->location);
        snprintf(cmd, sizeof(cmd), "wget -nc %s", url);
        printf("      %s\n", cmd);
        system(cmd);

        if (strcmp(file.ext, "tar.gz") == 0) {
            snprintf(cmd, sizeof(cmd), "tar -xf %s", filename);
            system(cmd);

            // remove the tarball
            snprintf(cmd, sizeof(cmd), "rm %s", filename);
            system(cmd);
        } else if (strcmp(file.ext, "zip") == 0) {
            snprintf(cmd, sizeof(cmd), "unzip %s-%s", name, version);
            system(cmd);

            // remove the tarball
            snprintf(cmd, sizeof(cmd), "rm %s-%s", name, version);
            system(cmd);
        }
    }
}

void cmd_build(Config *config) {
    if (config->num_deps < 1) {
        return;
    }

    chdir(config->location);
    int deps_dir = save_cwd();

    printf("Building dependencies ...\n");
    char cmd[2048];
    for (int i = 0; i < config->num_deps; i++) {
        restore_cwd(deps_dir);
        Dependency dep = config->deps[i];
        File file = file_from_url(dep.url);

        if (!is_dir(file.name)) {
            printf("  %s not a directory, skipping ...\n", file.name);
            continue;
        }

        printf("  building %s ...\n", dep.name);
        printf("    - %s\n", dep.name);
        chdir(file.name);

        snprintf(cmd, 1024, "%s", dep.build);
        system(cmd);
    }
    close_cwd(deps_dir);
}

void cmd_install(Config *config) {
    if (config->num_deps < 1) {
        return;
    }

    printf("Installing dependencies ...\n");

    mkdirp(config->include_path, 0755);
    mkdirp(config->lib_path, 0755);

    char cmd[2048];
    for (int i=0; i < config->num_deps; i++) {
        Dependency *dep = &config->deps[i];
        File file = file_from_url(dep->url);

        char location[256];
        snprintf(location, sizeof(location), "%s/%s", config->location, file.name);

        if (is_dir(location)) {
            for (int i = 0; i < dep->num_includes; i++) {
                char include[256];
                snprintf(include, sizeof(include), "%s/%s", location, dep->includes[i]);
                snprintf(cmd, 1024, "cp -R %s %s", include, config->include_path);
                printf("      %s\n", cmd);
                system(cmd);
            }
            for (int i = 0; i < dep->num_libs; i++) {
                char lib[256];
                snprintf(lib, sizeof(lib), "%s/%s", location, dep->libs[i]);
                snprintf(cmd, 1024, "cp -R %s %s", lib, config->lib_path);
                printf("      %s\n", cmd);
                system(cmd);
            }
        } else {
            char src[256];
            snprintf(src, sizeof(src), "%s/%s.%s", config->location, file.name, file.ext);

            char *dest = config->include_path;
            if (strcmp(file.ext, "a") == 0 ||
                strcmp(file.ext, "so") == 0 || 
                strcmp(file.ext, "dylib") == 0) {
                dest = config->lib_path;
            }

            snprintf(cmd, 1024, "cp %s %s", src, dest);
            printf("      %s\n", cmd);
            system(cmd);
        }
        free_file(file);
    }
}

void cmd_new() {
    printf("Setting up project ...\n");

    printf("   mkdir build\n");
    mkdir("build", 0755);

    printf("   mkdir build/include\n");
    mkdir("build/include", 0755);

    printf("   mkdir build/lib\n");
    mkdir("build/lib", 0755);

    printf("   mkdir deps\n");
    mkdir("deps", 0755);

    printf("   mkdir src\n");
    mkdir("src", 0755);

    printf("Done\n");
}

void cmd_config(Config *config) {
    printf("config:\n");
    printf("  location: %s\n", config->location);
    printf("  include_path: %s\n", config->include_path);
    printf("  lib_path: %s\n", config->lib_path);
    printf("  build: %s\n", config->build);

    if (config) {
        printf("  deps:\n");
        for (int i=0; i < config->num_deps; i++) {
            Dependency *deps = &config->deps[i];
            printf("    name: %s\n", deps->name);
            printf("      url: %s\n", deps->url);
            printf("      version: %s\n", deps->version);
            printf("      build: %s\n", deps->build);
            printf("      include:\n");
            for (int i = 0; i < deps->num_includes; i++) {
                printf("        %s\n", deps->includes[i]);
            }
            printf("      lib:\n");
            for (int i = 0; i < deps->num_libs; i++) {
                printf("        %s\n", deps->libs[i]);
            }
        }

        free_config(config);
    }
}

void execute_command(Config *config, char *command,int argc, char *argv[]) {
    if (strcmp(command, "get") == 0) {
        cmd_get(config);
    } else if (strcmp(command, "build") == 0) {
        cmd_build(config);
    } else if (strcmp(command, "install") == 0) {
        cmd_install(config);
    } else if (strcmp(command, "new") == 0) {
        cmd_new();
    } else if (strcmp(command, "config") == 0) {
        cmd_config(config);
    } else {
        fprintf(stderr, "Unknown command: %s\n", command);
        exit(1);
    }
}

int main(int argc, char *argv[]) {
    struct options opts = {0};
    parse_options(argc, argv, &opts);

    Config *config = read_config("deps.lua");

    if (opts.command != NULL) {
        execute_command(config, opts.command, opts.argc, opts.argv);
    } else {
        usage();
    }

    return 0;
}
