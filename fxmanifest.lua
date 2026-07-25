fx_version 'cerulean'
game 'gta5'
version '1.4.1'
author 'Reyghita Hafizh Firmanda'
description 'Garage system for ESX & QBCore made by RHD Team'

shared_scripts {
    '@pr_bridge/init.lua',
    'shared/bridge.lua',
    'shared/config.lua',
    'shared/utils.lua',
    'shared/houses.lua'
}

client_scripts {
    'client/radialmenu.lua',
    'client/keymanager.lua',
    'client/persist.lua',
    'client/blip.lua',
    'client/zone.lua',
    'client/vehicle.lua',
    'client/main.lua',
    'client/jobvehshop.lua',
    'client/police_impound.lua',
    'client/creator.lua',
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
    'modules/deformation.lua',
    'modules/spawnpoint.lua',
    'modules/pedcreator.lua',
    'modules/zone.lua',
}

dependencies {
    'pr_bridge'
}

lua54 'yes'
