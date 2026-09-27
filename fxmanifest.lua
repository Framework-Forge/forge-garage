fx_version("cerulean")
game("gta5")
version("1.4.5")
author("Reyghita Hafizh Firmanda")
description("Garage system for ESX & QBCore made by RHD Team")

shared_scripts({
	"@pr_bridge/init.lua",
	"shared/bridge.lua",
	"shared/config.lua",
	"shared/ipl_visual.lua",
	"shared/utils.lua",
	"shared/houses.lua",
})

client_scripts({
	"client/radialmenu.lua",
	"client/keymanager.lua",
	"client/persist.lua",
	"client/parking.lua",
	"client/blip.lua",
	"client/zone.lua",
	"client/ipl_visual.lua",
	"client/vehicle.lua",
	"client/main.lua",
	"client/jobvehshop.lua",
	"client/police_impound.lua",
	"client/creator.lua",
})

exports({
	"openKeyManagerMenu",
})

server_scripts({
	"server/db_update.lua",
	"server/vehicle_identity.lua",
	"server/db.lua",
	"server/main.lua",
	"server/parking.lua",
	"server/police_impound.lua",
	"server/storage.lua",
	"server/ipl_visual.lua",
	"server/vehicle.lua",
	"server/phone.lua",
	"server/command.lua",
	"server/jobvehshop.lua",
	"server/version.lua",
})

files({
	"locales/*.json",
	"data/peds.json",
	"data/garages.json",
	"data/vehiclesname.json",
	"modules/debugzone.lua",
	"modules/deformation.lua",
	"modules/spawnpoint.lua",
	"modules/pedcreator.lua",
	"modules/zone.lua",
})

dependencies({
	"pr_bridge",
})

lua54("yes")
