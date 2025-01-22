
local deps = {
    {
        'https://lua.org/ftp/lua-5.4.7.tar.gz',
        include = {
            'src/lua.h',
            'src/luaconf.h',
            'src/lualib.h',
            'src/lauxlib.h',
            'src/lua.hpp',
        },
        lib = {
            'src/liblua.a'
        },
    },
    {
        'https://raw.githubusercontent.com/nothings/stb/refs/heads/master/stb_ds.h',
    },
}

return deps
