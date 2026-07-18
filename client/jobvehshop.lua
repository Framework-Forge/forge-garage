if not Config.UseJobVechileShop then return end

local ped = {}
local vehPreview = nil

local function getRankVehicles(vehicle)
    local job = pr_lib.framework.GetPlayerData().job
    local myRank = job and (type(job.grade) == "table" and job.grade.level or job.grade) or 0
    local list = vehicle

    local index = 1
    local results = {}
    for model, data in pairs(list) do
        if data.forRank[myRank] and IsModelValid(model) then
            results[index] = {model = model, label = data.label, price = data.price, prefixPlate = data.prefixPlate}
            index += 1
        end
    end

    return results
end

local function destroyPreviewVehicle()
    if DoesEntityExist(vehPreview) then
        utils.destroyPreviewCam(vehPreview)
        SetEntityAsMissionEntity(vehPreview, true, true)
        DeleteEntity(vehPreview)
    end
end

local function previwVehicle(veh, coords, label)
    local model = veh.model
    local price = veh.price
    local vehLabel = veh.label
    local prefixPlate = veh.prefixPlate
    
    lib.requestModel(model, 150000)
    vehPreview = utils.createPreviewVeh(model, coords, nil, false)
    utils.createPreviewCam(vehPreview)

    lib.registerContext({
        id = 'forge_garage:jobvehshopAction',
        title = label,
        onBack = destroyPreviewVehicle,
        onExit = destroyPreviewVehicle,
        menu = 'forge_garage:jobvehshopMenu',
        options = {
            {
                title = vehLabel,
                description = locale('context.vehicleshop.menu_description_buy'),
                onSelect = function(args)
                    destroyPreviewVehicle()
                    Wait(100)
                    local newVeh = utils.createPlyVeh(model, coords)
                    TaskWarpPedIntoVehicle(cache.ped, newVeh, -1)
                    SetVehicleFixed(newVeh)
                    SetVehicleNumberPlateText(newVeh, prefixPlate .. ' ' .. lib.string.random('1111'))
                    utils.setFuel(newVeh, 100)

                    local data = {
                        label = vehLabel,
                        price = price,
                        model = model,
                        job = pr_lib.framework.GetPlayerData().job and pr_lib.framework.GetPlayerData().job.name or "none",
                        plate = utils.getPlate(newVeh),
                        props = vehFunc.gvp(newVeh),
                    }

                    TriggerServerEvent('forge_garage:server:buyVehicle', data)
                end,
                metadata = {
                    Price = '$' .. lib.math.groupdigits(price, '.')
                }
            },
        },
    })
    lib.showContext('forge_garage:jobvehshopAction')
end

local function showMenu(data)
    local filteredVehicles = getRankVehicles(data.vehicle)
    if not filteredVehicles[1] then return
        utils.notify(locale('notify.error.vehicleshop.no_vehicle_available'), 'error', 8000)
    end

    local context = {
        id = 'forge_garage:jobvehshopMenu',
        title = data.label,
        options = {}
    }

    for i=1, #filteredVehicles do
        local veh = filteredVehicles[i]
        local class = GetVehicleClassFromName(veh.model)
        context.options[#context.options+1] = {
            title = veh.label,
            icon = Config.Icons[class] or 'car',
            description = locale('context.vehicleshop.menu_description_preview'),
            onSelect = function ()
                return previwVehicle(veh, data.spawn, data.label)
            end
        }
    end

    lib.registerContext(context)
    lib.showContext('forge_garage:jobvehshopMenu')
end

CreateThread(function ()
    local vehShopConfig = Config.JobVehicleShop
    for i=1, #vehShopConfig do
        local data = vehShopConfig[i]
        local pedModel = joaat(data.ped.model)
        local pedCoords = data.ped.coords
        local groups = data.job

        ped[i] = utils.createTargetPed(pedModel, pedCoords, {
            {
                label = "Open Shops",
                icon = "fas fa-warehouse",
                action = function ()
                    showMenu(data)
                end,
                groups = groups,
                distance = 1.5
            }
        })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if DoesEntityExist(vehPreview) then
            DeleteEntity(vehPreview)
        end
    end
end)