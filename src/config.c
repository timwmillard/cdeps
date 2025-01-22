#include <stdlib.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <string.h>

char *parse_filename(const char *url);

// Structure to hold dependency info
typedef struct {
    char *name;
    char *url;
    char *version;
    char *build;
    char *opts;
    char **includes;
    int num_includes;
    char **libs;
    int num_libs;
} Dependency;

// Main struct for the Lua table
typedef struct {
    char *include_path;
    char *lib_path;
    char *location;
    char *build;
    Dependency *deps; // Assuming an array of strings for dependencies
    int num_deps;
} Config;

// Function to read string field from a Lua table
char *get_string_field(lua_State *L, const char *key) {
    lua_getfield(L, -1, key);
    const char *value = lua_isstring(L, -1) ? lua_tostring(L, -1) : NULL;
    char *result = value ? strdup(value) : NULL;
    lua_pop(L, 1);
    return result;
}

// Function to read array of strings from a Lua table field
void get_string_array(lua_State *L, const char *key, char ***array, int *count) {
    lua_getfield(L, -1, key);
    if (lua_istable(L, -1)) {
        *count = luaL_len(L, -1);
        *array = malloc(*count * sizeof(char*));
        
        for (int i = 1; i <= *count; i++) {
            lua_rawgeti(L, -1, i);
            (*array)[i-1] = strdup(lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
}

Config *read_config(const char *filename) {


    Config *config = malloc(sizeof(Config));
    config->include_path = "build/include";
    config->lib_path = "build/lib";
    config->build = "make";
    config->location = "deps";

    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    
    if (luaL_dofile(L, filename) != LUA_OK) {
        fprintf(stderr, "Error loading config file: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return config;
    }
    
    // Config file should return a table
    if (!lua_istable(L, -1)) {
        fprintf(stderr, "Config file must return a table\n");
        lua_close(L);
        return config;
    }
    
    // Get number of dependencies
    int num_deps = luaL_len(L, -1);
    Dependency *deps = malloc(sizeof(Dependency) * (num_deps + 1));
    memset(deps, 0, sizeof(Dependency) * (num_deps + 1));
    
    // Iterate through each dependency
    for (int i = 1; i <= num_deps; i++) {
        lua_rawgeti(L, -1, i);  // Get the dependency table
        
        if (lua_istable(L, -1)) {
            // Get the name (stored at index 1)
            lua_rawgeti(L, -1, 1);
            char *url = strdup(lua_tostring(L, -1));
            deps[i-1].url = url;
            lua_pop(L, 1);
            
            // Get other fields
            deps[i-1].name = get_string_field(L, "name");
            deps[i-1].version = get_string_field(L, "version");
            deps[i-1].opts = get_string_field(L, "opts");
            deps[i-1].build = get_string_field(L, "build");
            
            if (deps[i-1].name == NULL) {
                deps[i-1].name = parse_filename(url);
            }
            if (deps[i-1].version == NULL) {
                deps[i-1].version = strdup("latest");
            }
            if (deps[i-1].build == NULL) {
                deps[i-1].build = strdup(config->build);
            }

            // Get includes array
            get_string_array(L, "include", &deps[i-1].includes, &deps[i-1].num_includes);
            
            // Get libs array
            get_string_array(L, "lib", &deps[i-1].libs, &deps[i-1].num_libs);
        }
        
        lua_pop(L, 1);  // Pop the dependency table
    }
    lua_close(L);
    
    config->deps = deps;
    config->num_deps = num_deps;
    return config;
}

void free_config(Config *config) {
    if (!config) return;
    
    for (int i = 0; i < config->num_deps; i++) {
        free(config->deps[i].name);
        free(config->deps[i].version);
        free(config->deps[i].opts);
        free(config->deps[i].build);
        
        for (int j = 0; j < config->deps[i].num_includes; j++) {
            free(config->deps[i].includes[j]);
        }
        free(config->deps[i].includes);
        
        for (int j = 0; j < config->deps[i].num_libs; j++) {
            free(config->deps[i].libs[j]);
        }
        free(config->deps[i].libs);
    }
    free(config->deps);
    free(config);
}

