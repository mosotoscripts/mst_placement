fx_version 'cerulean'
game 'gta5'

lua54 'yes'

version '1.0.1'

author 'Mosoto Scripts'
description 'Tool for object placement and repositioning '

dependencies {
    'mst_bridge',
    'ox_lib',
}

shared_scripts {
    'config.lua',
    'locale.lua',
    '@ox_lib/init.lua',
}

client_scripts {
    'placement.lua',
}

files {
    'locales/*.json',
}

exports {
    'useGizmo',
    'isGizmoActive',
    'isAvailable',
    'getPreviewAlpha',
    'releaseInput',
}