-- default configuration for the deps package manager
return {
    install = {
        include = 'build/include',
        lib = 'build/lib',
    },
    cmd = {
        get = 'wget -O $name-$tag $url',
        get_fallback = 'curl $url --output $filename',
        git_clone = 'git clone --depth 1',
        build = 'make',
        install_file = 'cp',
        install_dir = 'cp -R',
    },
    location = 'deps',
    deps = {}
}
