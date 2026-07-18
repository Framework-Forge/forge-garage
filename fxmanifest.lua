fx_version 'cerulean'
game 'gta5'
version '1.4.1'
author 'Reyghita Hafizh Firmanda'
description 'Garage system for ESX & QBCore made by RHD Team'

shared_scripts {
    '@pr_bridge/init.lua',
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'shared/*.lua',
    'shared/houses.lua'
}

client_scripts {
    'client/radialmenu.lua',
    'client/keymanager.lua',
    'client/persist.lua',
    'client/*.lua',
}

exports {
    'openKeyManagerMenu'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db_update.lua',
    'server/db.lua',
    'server/main.lua',
    'server/police_impound.lua',
    'server/storage.lua',
    'server/vehicle.lua',
    'server/command.lua',
    'server/jobvehshop.lua'
}

files {
    'locales/*.json',
    'data/peds.json',
    'data/garages.json',
    'data/vehiclesname.json',
    'modules/debugzone.lua',
    'modules/zone.lua',
    'modules/deformation.lua',
    'modules/spawnpoint.lua',
    'modules/pedcreator.lua',
}

ox_lib "locale"

dependencies {
    'ox_lib'
}

lua54 'yes'
