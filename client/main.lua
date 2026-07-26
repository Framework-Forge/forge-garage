local VehicleShow = nil
local Deformation = GarageBridge.loadModule('modules.deformation')

local function destroyPreview()
    if VehicleShow and DoesEntityExist(VehicleShow) then
        utils.destroyPreviewCam(VehicleShow)
        DeleteVehicle(VehicleShow)
        VehicleShow = nil
    end
    while DoesEntityExist(VehicleShow) do
        Wait(100)
    end
    return true
end

local function swapEnabled(from)
    if GarageZone[from] then
        local fromJob = GarageZone[from]['job']
        local fromGang = GarageZone[from]['gang']
        
        if GarageZone[from]['vehicles'] and #GarageZone[from]['vehicles'] > 0 then
            return false
        end
        return not (fromJob or fromGang)
    else
        return false
    end

end

local function canSwapVehicle(to)
    local toJob = GarageZone[to]['job']
    local toGang = GarageZone[to]['gang']
    
    if GarageZone[to]['vehicles'] and #GarageZone[to]['vehicles'] > 0 then
        return false
    end
    
    return not (toJob or toGang)
end

local isSpawning = false

--- Spawn Vehicle
---@param data GarageVehicleData
local function spawnvehicle(data)
    if isSpawning then
        utils.notify('Aguarde enquanto o veículo está sendo spawnado.', 'error')
        return
    end
    LocalPlayer.state:set('garageBusy', true)

    -- The server owns the persistent entity registry. A vehicle in another
    -- routing bucket is intentionally invisible to this client.
    if data.plate and data.garage then
        local callbackData = GarageBridge.callback.await('forge_garage:cb_server:pullVehicleFromBucket', false, data.plate, data.coords or GetEntityCoords(GarageBridge.cache.ped), data.garage)
        
        if callbackData and callbackData.success then
            local netId = callbackData.netId
            local vehEntity = NetworkGetEntityFromNetworkId(netId)
            
            local timeout = 0
            while not DoesEntityExist(vehEntity) and timeout < 100 do
                Wait(10)
                vehEntity = NetworkGetEntityFromNetworkId(netId)
                timeout = timeout + 1
            end
            
            if DoesEntityExist(vehEntity) then
                local expectedPlate = callbackData.displayPlate or callbackData.plate or data.plate
                if expectedPlate then
                    SetVehicleNumberPlateText(vehEntity, expectedPlate)
                    CreateThread(function()
                        for _ = 1, 8 do
                            Wait(100)
                            if not DoesEntityExist(vehEntity) then return end
                            SetVehicleNumberPlateText(vehEntity, expectedPlate)
                        end
                    end)
                end
                FreezeEntityPosition(vehEntity, false)
                SetVehicleHandbrake(vehEntity, false)
                SetVehicleUndriveable(vehEntity, false)
                SetVehicleDoorsLocked(vehEntity, 1)
                Entity(vehEntity).state:set("doorslockstate", 1, true)
                SetVehicleEngineOn(vehEntity, false, true, true)

                local state = Entity(vehEntity).state
                state:set('isPersistent', nil, true)
                state:set('plate', callbackData.plate or data.plate, true)
                state:set('garageName', nil, true)
                state:set('pr_carkeys_skipRevPed', nil, true)

                exports['forge-garage']:unregisterStoredPersistentVehicle(data.plate)

                if Config.SpawnInVehicle then
                    TaskWarpPedIntoVehicle(GarageBridge.cache.ped, vehEntity, -1)
                end

                if Config.GiveKeys.tempkeys then
                    TriggerEvent("vehiclekeys:client:SetOwner", data.plate:trim())
                end

                utils.notify("Você liberou seu veículo estacionado!", "success")
                LocalPlayer.state:set('garageBusy', false)
                return
            end
        end
    end

    isSpawning = true

    local success, errorMsg = pcall(function()
        local vehData = {
            model = data.model,
            plate = data.plate,
        }
        
        if data.plate then
            local callbackData = GarageBridge.callback.await('forge_garage:cb_server:getvehiclePropByPlate', false, data.plate)
            if not callbackData then
                error('Failed to load vehicle data with number plate ' .. data.plate)
            end
            for key, value in pairs(callbackData) do
                vehData[key] = value
            end
        end

        if Config.InDevelopment then
            print(json.encode(data))
        end
        
        local spawnProps = type(vehData.mods) == "table" and vehData.mods or {}
        local expectedPlate = spawnProps.plate or vehData.fakeplate or vehData.plate or data.plate
        if expectedPlate then
            spawnProps.plate = expectedPlate
        end

        local vehEntity
        utils.createPlyVeh(vehData.model, data.coords, function(veh) vehEntity = veh end, true, spawnProps)
        
        local timeout = 0
        while (not vehEntity or vehEntity == 0 or not DoesEntityExist(vehEntity)) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end

        if vehEntity and vehEntity ~= 0 and DoesEntityExist(vehEntity) then
            if expectedPlate then
                SetVehicleNumberPlateText(vehEntity, expectedPlate)
            end
            SetVehicleOnGroundProperly(vehEntity)
            FreezeEntityPosition(vehEntity, true) -- Frozen
            SetVehicleDoorsLocked(vehEntity, 2) -- Locked
            Entity(vehEntity).state:set("doorslockstate", 2, true)
            SetVehicleHandbrake(vehEntity, true)
            
            -- Force lock status multiple times to override any network sync delay
            CreateThread(function()
                local timeout = 0
                while timeout < 20 do
                    if DoesEntityExist(vehEntity) then
                        SetVehicleDoorsLocked(vehEntity, 2)
                        Entity(vehEntity).state:set("doorslockstate", 2, true)
                    end
                    Wait(100)
                    timeout = timeout + 1
                end
            end)
            
            local state = Entity(vehEntity).state
            state:set('isPersistent', true, true)
            state:set('plate', vehData.plate or data.plate, true)
            state:set('garageName', vehData.garage or data.garage, true)
            
            local netId = NetworkGetNetworkIdFromEntity(vehEntity)
            exports['forge-garage']:registerStoredPersistentVehicle(vehData.plate or data.plate, netId, vehEntity)
        end

        if (not vehData.mods or json.encode(vehData.mods) == "[]") and
            (not data.prop or json.encode(data.prop) == "[]") and
            data.plate then
            SetVehicleNumberPlateText(vehEntity, data.plate)
            if Config.GiveKeys.tempkeys then
                TriggerEvent("vehiclekeys:client:SetOwner", data.plate)
            end
        end

        SetVehicleEngineHealth(vehEntity, (vehData.engine or 1000) + 0.0)
        SetVehicleBodyHealth(vehEntity, (vehData.body or 1000) + 0.0)
        utils.setFuel(vehEntity, vehData.fuel or 100)
        
        if vehData.deformation or data.deformation then
            Deformation.set(vehEntity, vehData.deformation or data.deformation)
        end

        while not vehEntity do
            Wait(100)
        end

        Entity(vehEntity).state:set('vehlabel', vehData.vehicle_name or data.vehicle_name)
        
        TriggerServerEvent("forge_garage:server:updateState", {
            plate = vehData.plate or data.plate,
            state = 0,
            garage = vehData.garage or data.garage
        })

        if Config.SpawnInVehicle then
            TaskWarpPedIntoVehicle(GarageBridge.cache.ped, vehEntity, -1)
        end



        if Config.GiveKeys.tempkeys then
            TriggerEvent("vehiclekeys:client:SetOwner", (vehData.plate or data.plate):trim())
        end

        if not data.plate and Config.GiveKeys.tempkeys then
            local plate = GetVehicleNumberPlateText(vehEntity)
            TriggerEvent("vehiclekeys:client:SetOwner", plate)
        end

        GarageBridge.progressCircle({
            duration = 3000,
            position = 'bottom',
            label = 'Estacionando veículo...',
            useWhileDead = false,
            canCancel = false,
            disable = {
                move = false,
                car = false,
                combat = true,
                sprint = true,
            }
        })

    end)

    isSpawning = false
    LocalPlayer.state:set('garageBusy', false)
    if not success then
        utils.notify('Erro ao spawnar veículo: ' .. (errorMsg or 'desconhecido'), 'error')
    end
end

local function getVehMetadata(data)
    local fuel = data.fuel
    local body = data.body
    local engine = data.engine
    return {
        {label = '⛽ Combustível', value = math.floor(fuel) .. '%', progress = math.floor(fuel), colorScheme = utils.getColorLevel(math.floor(fuel))},
        {label = '🧰 Lataria', value = math.floor(body / 10) .. '%', progress = math.floor(body / 10), colorScheme = utils.getColorLevel(math.floor(body / 10))},
        {label = '🔧 Motor', value = math.floor(engine / 10) .. '%', progress = math.floor(engine / 10), colorScheme = utils.getColorLevel(math.floor(engine / 10))}
    }
end
--- Garage Action
---@param data GarageVehicleData
local function actionMenu(data)
    local actionData = {
        id = 'garage_action',
        title = data.plate or data.vehName,
        description = data.vehicle_name,
        menu = 'garage_menu',
        onBack = destroyPreview,
        onExit = destroyPreview,
        options = {
            {
                title = data.vehName,
                icon = data.icon --[[@as string]],
                readOnly = true,
                iconAnimation = Config.IconAnimation,
                metadata = getVehMetadata(data),
            },
            {
                title = data.impound and GarageBridge.locale('garage.pay_impound') or GarageBridge.locale('garage.take_out_veh'),
                icon = data.impound and 'hand-holding-dollar' or 'sign-out-alt',
                iconAnimation = Config.IconAnimation,
                onSelect = function()
                    if data.impound then
                        utils.createMenu({
                            id = 'pay_methode',
                            title = GarageBridge.locale('context.insurance.pay_methode_header'):upper(),
                            onExit = destroyPreview,
                            menu = 'garage_action',
                            options = {
                                {
                                    title = GarageBridge.locale('context.insurance.pay_methode_cash_title'):upper(),
                                    icon = 'dollar-sign',
                                    description = GarageBridge.locale('context.insurance.pay_methode_cash_desc'),
                                    iconAnimation = Config.IconAnimation,
                                    onSelect = function()
                                        destroyPreview()
                                        if pr_lib.framework.GetMoney('cash') < data.depotprice then return utils.notify(GarageBridge.locale('notify.error.not_enough_cash'), 'error') end
                                        local success = GarageBridge.callback.await('forge_garage:cb_server:removeMoney', false, 'cash', data.depotprice)
                                        if success then
                                            utils.notify(GarageBridge.locale('garage.success_pay_impound'), 'success')
                                            return spawnvehicle(data)
                                        end
                                    end
                                },
                                {
                                    title = GarageBridge.locale('context.insurance.pay_methode_bank_title'):upper(),
                                    icon = 'fab fa-cc-mastercard',
                                    description = GarageBridge.locale('context.insurance.pay_methode_bank_desc'),
                                    iconAnimation = Config.IconAnimation,
                                    onSelect = function()
                                        destroyPreview()
                                        if pr_lib.framework.GetMoney('bank') < data.depotprice then return utils.notify(GarageBridge.locale('notify.error.not_enough_bank'), 'error') end
                                        local success = GarageBridge.callback.await('forge_garage:cb_server:removeMoney', false, 'bank', data.depotprice)
                                        if success then
                                            utils.notify(GarageBridge.locale('garage.success_pay_impound'), 'success')
                                            return spawnvehicle(data)
                                        end
                                    end
                                }
                            }
                        })
                        return
                    end
                    local success = destroyPreview()
                    while not success do
                        Wait(100)
                    end
                    spawnvehicle(data)
                end
            },
        
        }
    }
    
    if not data.impound and data.plate then
        -- TransferVehicle option has been removed from garage menu and moved to Key Manager menu export
        
        
        if Config.SwapGarage.enable and swapEnabled(data.garage) then
            actionData.options[#actionData.options + 1] = {
                title = GarageBridge.locale('context.garage.swapgarage'),
                icon = "retweet",
                iconAnimation = Config.IconAnimation,
                metadata = {
                    ["Preço"] = 'R$ ' .. GarageBridge.math.groupdigits(Config.SwapGarage.price, '.')
                },
                onSelect = function()
                    destroyPreview()
                    
                    local garageTable = function()
                        local result = {}
                        for k, v in pairs(GarageZone) do
                            if k ~= data.garage and not v.impound and canSwapVehicle(k) then
                                result[#result + 1] = {value = k}
                            end
                        end
                        return result
                    end
                    
                    local garageInput = pr_lib.inputDialog(data.garage:upper(), {
                        {type = 'select', label = GarageBridge.locale('input.garage.swapgarage'), options = garageTable(), required = true},
                    })
                    
                    if garageInput then
                        local vehdata = {
                            plate = data.plate,
                            newgarage = garageInput[1]
                        }
                        
                        if pr_lib.framework.GetMoney('cash') < Config.SwapGarage.price then return utils.notify(GarageBridge.locale("notify.error.need_money", GarageBridge.math.groupdigits(Config.SwapGarage.price, '.')), 'error') end
                        local success = GarageBridge.callback.await('forge_garage:cb_server:removeMoney', false, 'cash', Config.SwapGarage.price)
                        if not success then return end
                        
                        GarageBridge.callback('forge_garage:cb_server:swapGarage', false, function(success)
                            if not success then return
                                utils.notify(GarageBridge.locale("notify.error.swapgarage"), "error")
                            end
                            
                            utils.notify(GarageBridge.locale('notify.success.swapgarage', vehdata.newgarage), "success")
                        end, vehdata)
                    end
                end
            }
        end
        
        actionData.options[#actionData.options + 1] = {
            title = GarageBridge.locale('context.garage.change_veh_name'),
            icon = 'pencil',
            iconAnimation = Config.IconAnimation,
            metadata = {
                ["Preço"] = 'R$ ' .. GarageBridge.math.groupdigits(Config.SwapGarage.price, '.')
            },
            onSelect = function()
                destroyPreview()
                
                local input = pr_lib.inputDialog(data.vehName, {
                    {type = 'input', label = '', placeholder = GarageBridge.locale('input.garage.change_veh_name'), required = true, max = 20},
                })
                
                if input then
                    if pr_lib.framework.GetMoney('cash') < Config.changeNamePrice then return utils.notify(GarageBridge.locale('notify.error.not_enough_cash'), 'error') end
                    
                    local success = GarageBridge.callback.await('forge_garage:cb_server:removeMoney', false, 'cash', Config.changeNamePrice)
                    if success then
                        CNV[data.plate] = {
                            name = input[1]
                        }
                        TriggerServerEvent('forge_garage:server:saveCustomVehicleName', CNV)
                    end
                end
            end
        }
        
        -- GiveKeys (copy) option has been removed from garage menu and moved to Key Manager menu export
    end
    
    utils.createMenu(actionData)
end

--- Get available spawn point
---@param points table
---@param ignoreDist boolean?
---@param defaultCoords vector4?
---@return vector4?
local function getAvailableSP(points, ignoreDist, defaultCoords)
    if type(points) ~= "table" and ignoreDist then
        return points
    end
    assert(
        type(points) == "table" and points[1], 'Invalid "points" parameter: Expected a non-empty array table.'
    )
    for k, v in pairs(points) do
        local sp = vec(v.x, v.y, v.z, v.w)
        local vehEntity = GarageBridge.getClosestVehicle(sp.xyz, 2.0, true)
        
        if ignoreDist and not vehEntity then
            return sp
        end
        
        local dist = #(defaultCoords.xyz - sp.xyz)
        if dist < 2.0 and not vehEntity then
            return sp
        end
    end
end

local function listAddedVehicles(data, menuData)
    for i = 1, #data.vehicles do
        local v = data.vehicles[i]
        local vehModel = v
        local vehName = GetLabelText(GetDisplayNameFromVehicleModel(v))
        
        
        menuData.options[#menuData.options + 1] = {
            title = vehName,
            icon = 'car',
            iconColor = 'white',
            onSelect = function()
                local defaultcoords = vec(GetOffsetFromEntityInWorldCoords(GarageBridge.cache.ped, 0.0, 2.0, 0.5), GetEntityHeading(GarageBridge.cache.ped) + 90)
                
                if data.spawnpoint then
                    defaultcoords = getAvailableSP(data.spawnpoint, data.ignoreDist, defaultcoords)
                end
                
                if not defaultcoords then
                    return utils.notify(GarageBridge.locale('notify.error.no_parking_spot'), 'error', 8000)
                end
                
                local vehInArea = GarageBridge.getClosestVehicle(defaultcoords.xyz)
                if DoesEntityExist(vehInArea) then return utils.notify(GarageBridge.locale('notify.error.no_parking_spot'), 'error') end
                
                VehicleShow = utils.createPreviewVeh(vehModel, defaultcoords)
                FreezeEntityPosition(VehicleShow, true)
                SetVehicleDoorsLocked(VehicleShow, 2)
                utils.createPreviewCam(VehicleShow)
                
                actionMenu({
                    prop = nil,
                    engine = 1000,
                    fuel = 100,
                    body = 1000,
                    model = vehModel,
                    plate = nil,
                    coords = defaultcoords,
                    garage = data.garage,
                    vehName = vehName,
                    vehicle_name = nil,
                    impound = data.impound,
                    shared = data.shared,
                    deformation = nil,
                    depotprice = nil,
                    entity = VehicleShow
                })
            end,
        }
    end
    
    return menuData
end

--- Open Garage
---@param data GarageVehicleData
local function openMenu(data)
    if LocalPlayer.state.garageBusy then return end
    if not data then return end
    data.type = data.type or "car"
    
    local menuData = {
        id = 'garage_menu',
        title = data.garage,
        options = {}
    }
    
    if data.vehicles then
        menuData = listAddedVehicles(data, menuData)
        if #menuData.options >= 1 then
            utils.createMenu(menuData)
            return
        end
    end
    
    local vehData = GarageBridge.callback.await('forge_garage:cb_server:getVehicleList', false, data.garage, data.impound, data.shared)
    
    if not vehData or #vehData == 0 then
        utils.notify("Você não possui chaves de nenhum veículo para esta garagem no seu inventário ou bolsa!", "error", 8000)
        return
    end
    
    for i = 1, #vehData do
        local vd = vehData[i]
        local vehProp = vd.vehicle
        local vehModel = vd.model
        local plate = utils.string.trim(vd.plate)
        local vehDeformation = vd.deformation
        local gState = vd.state
        local pName = vd.owner or "Unkown Players"
        local fakeplate = vd.fakeplate and utils.string.trim(vd.fakeplate)
        local engine = vd.engine
        local body = vd.body
        local fuel = vd.fuel
        local dp = vd.depotprice
        
        local vehName = vd.vehicle_name or utils.getVehicleLabel(vehModel)
        local customvehName = CNV[plate] and CNV[plate].name
        local vehlabel = customvehName or vehName
        
        local shared_garage = data.shared
        local disabled = false
        local description = ''
        
        plate = fakeplate or plate
        
        local vehicleClass = GetVehicleClassFromName(vehModel)
        local vehicleType = utils.getCategoryByClass(vehicleClass)
        
        if GarageBridge.table.contains(data.type, vehicleType) then
            local icon = Config.Icons[vehicleClass] or 'car'
            local ImpoundPrice = dp > 0 and dp or Config.ImpoundPrice[vehicleClass]
            local impound
            if gState == 0 then
                if (Config.VehiclesInAllGarages and vehFunc.govbp(plate)) or (not Config.VehiclesInAllGarages and vehFunc.tvbp(plate, data.garage)) then
                    disabled = not Config.LocateVehicleOutGarage
                    description = 'STATUS: ' .. GarageBridge.locale('status.out')
                elseif Config.VehiclesInAllGarages and vehFunc.tvbp(plate, nil) then
                    disabled = not Config.LocateVehicleOutGarage
                    description = 'STATUS: ' .. GarageBridge.locale('status.out')
                else
                    if Config.VehiclesInAllGarages then
                        impound = true
                    end
                    description = GarageBridge.locale('garage.impound_price', ImpoundPrice)
                end
            end
            
            if gState == 1 then
                impound = false
                description = 'STATUS: ' .. GarageBridge.locale('status.in')
                if shared_garage then
                    description = GarageBridge.locale('context.garage.owner_label', pName) .. ' \n' .. 'STATUS: ' .. GarageBridge.locale('status.in')
                end
            end
            
            local vehicleLabel = ('%s [ %s ]'):format(vehlabel, plate)
            menuData.options[#menuData.options + 1] = {
                title = vehicleLabel,
                icon = icon,
                disabled = disabled,
                description = description:upper(),
                iconAnimation = Config.IconAnimation,
                metadata = getVehMetadata(vd),
                onSelect = function()
                    if gState == 0 and vehFunc.tvbp(plate, nil) and not disabled then
                        if vehFunc.tvbp(plate, nil, true) then
                            return utils.notify(GarageBridge.locale('notify.success.locate_vehicle'), 'success', 8000)
                        end
                    end

                    local pedHeading = GetEntityHeading(GarageBridge.cache.ped)
                    local worlcoords = GetOffsetFromEntityInWorldCoords(GarageBridge.cache.ped, 0.0, 2.0, 0.5)
                    local defaultcoords = vec(worlcoords, pedHeading + 90)
                    
                    if data.spawnpoint then
                        defaultcoords = getAvailableSP(data.spawnpoint, data.ignoreDist, defaultcoords)--[[@as vector4]]
                    end
                    
                    if not defaultcoords then
                        return utils.notify(GarageBridge.locale('notify.error.no_parking_spot'), 'error', 8000)
                    end
                    
                    local vehInArea = GarageBridge.getClosestVehicle(defaultcoords.xyz)
                    if DoesEntityExist(vehInArea) then return utils.notify(GarageBridge.locale('notify.error.no_parking_spot'), 'error') end
                    
                    VehicleShow = utils.createPreviewVeh(vehModel, defaultcoords)
                    FreezeEntityPosition(VehicleShow, true)
                    SetVehicleDoorsLocked(VehicleShow, 2)
                    utils.createPreviewCam(VehicleShow)
                    
                    if vehProp and next(vehProp) then
                        vehFunc.svp(VehicleShow, vehProp)
                    end
                    
                    actionMenu({
                        prop = vehProp,
                        engine = engine,
                        fuel = fuel,
                        body = body,
                        model = vehModel,
                        plate = plate,
                        coords = defaultcoords,
                        garage = data.garage,
                        vehName = vehicleLabel,
                        vehicle_name = vehlabel,
                        impound = impound,
                        shared = data.shared,
                        deformation = vehDeformation,
                        depotprice = ImpoundPrice,
                        icon = icon
                    })
                end,
            }
        end
    end
    
    if #menuData.options < 1 then
        utils.notify("Você não tem chave de nenhum veículo aqui parqueado!", "error", 8000)
        return
    end
    
    utils.createMenu(menuData)
end

local function returnPrCarKeyFromIgnition(vehicle, plate)
    if GetResourceState('pr_carkeys') ~= 'started' then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if not plate or plate == '' then return end

    local state = Entity(vehicle).state
    local hasIgnitionKey = state.keyInIgnition or state.keyInside or state.keyInVehicle or state.hasKeyInIgnition
    local engineRunning = GetIsVehicleEngineRunning(vehicle)

    if not engineRunning and not hasIgnitionKey then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 or netId == 65533 then return end

    TriggerServerEvent('pr_carkeys:server:returnKeyFromVehicle', netId, plate)
end

--- Store Vehicle To Garage
---@param data GarageVehicleData
local function storeVeh(data)
    local myCoords = GetEntityCoords(GarageBridge.cache.ped)
    local vehicle = GarageBridge.cache.vehicle or GarageBridge.getClosestVehicle(myCoords)
    
    local vehicleClass = GetVehicleClass(vehicle)
    local vehicleType = utils.getCategoryByClass(vehicleClass)
    
    if not vehicle then return
        utils.notify(GarageBridge.locale('notify.error.not_veh_exist'), 'error')
    end
    
    if not GarageBridge.table.contains(data.type, vehicleType) then return
        utils.notify(GarageBridge.locale('notify.info.invalid_veh_classs', data.garage))
    end

    if data.impound then return
        utils.notify("Você não pode guardar veículos no pátio.", 'error')
    end
    
    local prop = vehFunc.gvp(vehicle)
    local plate = prop and utils.string.trim(prop.plate) or data.plate
    local shared = data.shared
    local deformation = Deformation.get(vehicle)
    local fuel = utils.getFuel(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    local body = GetVehicleBodyHealth(vehicle)
    local model = prop.model
    
    local isOwned = GarageBridge.callback.await('forge_garage:cb_server:getvehowner', false, plate, shared, {
        mods = prop,
        deformation = deformation,
        fuel = fuel,
        engine = engine,
        body = body,
        vehicle_name = Entity(vehicle).state.vehlabel
    })

    if not isOwned and not data.vehicles then return
        utils.notify(GarageBridge.locale('notify.error.not_owned'), 'error')
    end
    if isOwned and data.vehicles then return
        utils.notify(GarageBridge.locale('notify.error.is_service_garage'), 'error')
    end

    returnPrCarKeyFromIgnition(vehicle, plate)
    SetVehicleEngineOn(vehicle, false, true, true)

    if GarageBridge.cache.vehicle and GarageBridge.cache.seat == -1 then
        TaskLeaveAnyVehicle(GarageBridge.cache.ped, true, 0)
        Wait(1000)
    end
    
    if DoesEntityExist(vehicle) then
        local garageData = GarageZone[data.garage]

        local coords = GetEntityCoords(vehicle)
        local heading = GetEntityHeading(vehicle)
        local parkingCoords = json.encode({ x = coords.x, y = coords.y, z = coords.z, h = heading })

        -- Make the vehicle stored in place
        FreezeEntityPosition(vehicle, true)
        SetVehicleDoorsLocked(vehicle, 2) -- Locked
        Entity(vehicle).state:set("doorslockstate", 2, true)
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleHandbrake(vehicle, true)
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleDirtLevel(vehicle, 0.0)

        local state = Entity(vehicle).state
        state:set('isPersistent', (garageData and garageData.persist) and true or nil, true)
        state:set('plate', plate, true)
        state:set('garageName', data.garage, true)

        local netId = 0
        local netTimer = 0
        while (netId == 0 or netId == 65533) and netTimer < 100 do
            Wait(10)
            if NetworkGetEntityIsNetworked(vehicle) then
                netId = NetworkGetNetworkIdFromEntity(vehicle)
            end
            netTimer = netTimer + 1
        end

        if netId ~= 0 and netId ~= 65533 then
            if garageData and garageData.persist then
                pcall(function()
                    exports['forge-garage']:registerStoredPersistentVehicle(plate, netId, vehicle)
                end)
            else
                if pr_lib and pr_lib.cache then
                    pr_lib.cache.set('persistent:veh:' .. plate, vehicle)
                end
            end
            
            TriggerServerEvent('forge_garage:server:updateState', {
                plate = plate,
                state = 1,
                garage = data.garage,
                parking_coords = parkingCoords,
                netId = netId
            })
        else
            -- Fallback if networking fails: delete entity and store in DB normally
            DeleteEntity(vehicle)
            TriggerServerEvent('forge_garage:server:updateState', {
                plate = plate,
                state = 1,
                garage = data.garage,
                parking_coords = parkingCoords
            })
        end

        utils.notify(GarageBridge.locale('notify.success.store_veh'), 'success')
    end
end

--- exports
exports('openMenu', openMenu)
exports('storeVehicle', storeVeh)
