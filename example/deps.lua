
local deps = {
    {
        'Immediate-Mode-UI/Nuklear',
        name = 'nuklear',
        version = '4.12.3',
        dest = 'vendor', -- default 'deps'
        get = 'wget -O $filename', -- or 'curl' or 'git clone'
        build = 'make', -- or 'cmake'
        include = {
            'nuklear.h'
        },
        lib = {
        },
        before = function()
            os.execute('make -C vendor/nuklear')
        end,
        after = function()
            os.execute('rm -rf vendor/nuklear')
        end,
    },
    {
        'https://raw.githubusercontent.com/nothings/stb/refs/heads/master/stb_ds.h',
        include = {
            'stb_ds.h'
        },
    },
    {
        'lua/lua',
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
}

return {
    location = "deps",
    include_path = '/usr/local/include', -- default 'build/include'
    lib_path = '/usr/local/lib', -- default 'build/lib'
    get = 'wget',
    git_clone = 'git clone',
    build = 'make',
    install_file = 'cp',
    install_dir = 'cp -R',
    dest = 'deps',
    deps = deps
}
