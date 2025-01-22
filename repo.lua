
local deps = {
    {
        name = 'lua',
        get = 'wget https://lua.org/ftp/lua-5.4.7.tar.gz',
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
        name = 'stb_ds',
        get = 'wget https://raw.githubusercontent.com/nothings/stb/refs/heads/master/stb_ds.h',
        build = 'make',
        install = 'make install',
    },
    {
        name = 'nuklear',
        get = 'wget https://github.com/Immediate-Mode-UI/Nuklear/releases/tag/4.12.3',
        include = {
            'nuklear.h'
        },
    },
}

return deps
