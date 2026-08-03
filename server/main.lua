local activeGarages = {}
local activeStoredVehicles = {}
local storedVehiclesGarage = {}
local withdrawingPersistentVehicles = {}
local revvingPersistentPlates = {}
local revvingPersistentNetIds = {}
local REV_ENGINE_PROTECTION_MS = 5000

local function normalizePlate(plate)
    if not plate then return nil end
    return tostring(plate):gsub("%s+", ""):upper()
end

local function tableKeys(source)
    local keys = {}
    if type(source) ~= 'table' then return keys end

    local lastKey = nil
    while true do
        local ok, key = pcall(next, source, lastKey)
        if not ok or key == nil then break end
        keys[#keys + 1] = key
        lastKey = key
    end

    return keys
end

local function countTableEntries(source)
    return #tableKeys(source)
end

local function extendRevProtection(current, expires)
    if current and current > expires then return current end
    return expires
end

local function protectRevvingPersistentVehicle(plate, netId)
    local expires = GetGameTimer() + REV_ENGINE_PROTECTION_MS
    local plateKey = normalizePlate(plate)

    if plateKey then
        revvingPersistentPlates[plateKey] = extendRevProtection(revvingPersistentPlates[plateKey], expires)
    end
    if netId and netId ~= 0 and netId ~= 65533 then
        revvingPersistentNetIds[netId] = extendRevProtection(revvingPersistentNetIds[netId], expires)
    end
end

local function hasTimedRevProtection(protections, key)
    if not key then return false end
    local expires = protections[key]
    if not expires then return false end
    if expires > GetGameTimer() then return true end
    protections[key] = nil
    return false
end

local function isPersistentVehicleProtected(plate, entity, netId)
    local plateKey = normalizePlate(plate)
    if plateKey and withdrawingPersistentVehicles[plateKey] then return true end
    if hasTimedRevProtection(revvingPersistentPlates, plateKey) then return true end

    if (not netId or netId == 0 or netId == 65533) and entity and DoesEntityExist(entity) then
        netId = NetworkGetNetworkIdFromEntity(entity)
    end
    if hasTimedRevProtection(revvingPersistentNetIds, netId) then return true end

    if entity and DoesEntityExist(entity) and Entity(entity).state.pr_carkeys_revving then
        return true
    end

    return false
end

local function getTrackedPersistentVehicle(garageName, plate)
    local plateKey = normalizePlate(plate)
    if not plateKey then return nil end

    local storedPlates = tableKeys(activeStoredVehicles)
    for i = 1, #storedPlates do
        local storedPlate = storedPlates[i]
        local entity = activeStoredVehicles[storedPlate]
        if normalizePlate(storedPlate) == plateKey and entity and DoesEntityExist(entity) then
            return entity, NetworkGetNetworkIdFromEntity(entity), storedPlate
        end
    end

    local garage = activeGarages[garageName]
    if garage and garage.vehicles then
        local garagePlates = tableKeys(garage.vehicles)
        for i = 1, #garagePlates do
            local storedPlate = garagePlates[i]
            if normalizePlate(storedPlate) == plateKey then
                local netId = garage.vehicles[storedPlate]
                local entity = netId and NetworkGetEntityFromNetworkId(netId) or nil
                if entity and DoesEntityExist(entity) then
                    return entity, netId, storedPlate
                end
            end
        end
    end

    -- Entity tables are rebuilt after a resource restart. Recover orphaned
    -- persistent vehicles from their replicated state instead of spawning a copy.
    local vehicles = GetAllVehicles()
    for i = 1, #vehicles do
        local entity = vehicles[i]
        if entity and DoesEntityExist(entity) then
            local state = Entity(entity).state
            local statePlate = state.plate
            local stateGarage = state.garageName
            if state.isPersistent == true
                and normalizePlate(statePlate) == plateKey
                and (not garageName or not stateGarage or stateGarage == garageName) then
                return entity, NetworkGetNetworkIdFromEntity(entity), statePlate
            end
        end
    end

    return nil
end

local function getWorldVehicleByPlate(plate)
    local plateKey = normalizePlate(plate)
    if not plateKey then return nil end

    local vehicles = GetAllVehicles()
    for i = 1, #vehicles do
        local entity = vehicles[i]
        if entity and DoesEntityExist(entity) then
            local statePlate = Entity(entity).state.plate
            local nativePlate
            if not statePlate then
                local ok, value = pcall(GetVehicleNumberPlateText, entity)
                nativePlate = ok and value or nil
            end

            if normalizePlate(statePlate or nativePlate) == plateKey then
                return entity, NetworkGetNetworkIdFromEntity(entity)
            end
        end
    end

    return nil
end

local function trackPersistentVehicle(garageName, plate, entity, netId)
    local plateKey = normalizePlate(plate)
    if not plateKey or not entity or not DoesEntityExist(entity) then return end

    local storedPlates = tableKeys(activeStoredVehicles)
    for i = 1, #storedPlates do
        local storedPlate = storedPlates[i]
        if normalizePlate(storedPlate) == plateKey then
            activeStoredVehicles[storedPlate] = nil
            storedVehiclesGarage[storedPlate] = nil
        end
    end

    if activeGarages[garageName] and activeGarages[garageName].vehicles then
        local garagePlates = tableKeys(activeGarages[garageName].vehicles)
        for i = 1, #garagePlates do
            local storedPlate = garagePlates[i]
            if normalizePlate(storedPlate) == plateKey then
                activeGarages[garageName].vehicles[storedPlate] = nil
            end
        end
    end

    local canonicalPlate = tostring(plate)
    activeStoredVehicles[canonicalPlate] = entity
    storedVehiclesGarage[canonicalPlate] = garageName
    if activeGarages[garageName] and activeGarages[garageName].vehicles then
        activeGarages[garageName].vehicles[canonicalPlate] = netId or NetworkGetNetworkIdFromEntity(entity)
    end
end

local function removeTrackedPersistentVehicle(garageName, plate, netId)
    local plateKey = normalizePlate(plate)
    if not plateKey then return end

    if activeGarages[garageName] and activeGarages[garageName].vehicles then
        local vehiclePlates = tableKeys(activeGarages[garageName].vehicles)
        for i = 1, #vehiclePlates do
            local storedPlate = vehiclePlates[i]
            local storedNetId = activeGarages[garageName].vehicles[storedPlate]
            if normalizePlate(storedPlate) == plateKey or storedNetId == netId then
                activeGarages[garageName].vehicles[storedPlate] = nil
            end
        end
    end

    local storedVehiclePlates = tableKeys(activeStoredVehicles)
    for i = 1, #storedVehiclePlates do
        local storedPlate = storedVehiclePlates[i]
        if normalizePlate(storedPlate) == plateKey then
            activeStoredVehicles[storedPlate] = nil
        end
    end

    local storedGaragePlates = tableKeys(storedVehiclesGarage)
    for i = 1, #storedGaragePlates do
        local storedPlate = storedGaragePlates[i]
        if normalizePlate(storedPlate) == plateKey then
            storedVehiclesGarage[storedPlate] = nil
        end
    end
end

--- callback
GarageBridge.callback.register('forge_garage:cb_server:removeMoney', function(src, type, amount)
    return pr_lib.framework.RemovePlayerAccountBalance(src, type, amount, "Garage interaction")
end)

GarageBridge.callback.register('forge_garage:cb_server:pullVehicleFromBucket', function(source, plate, coords, garageName)
    local src = source
    local vehicleData = GarageDB.gpvbp(plate)
    local trackedGarage = vehicleData and vehicleData.garage or garageName
    local entity, netId = getTrackedPersistentVehicle(trackedGarage, plate)

    if not vehicleData or tonumber(vehicleData.state) ~= 1 then
        return { success = false, reason = "vehicle_not_stored" }
    end

    if entity and DoesEntityExist(entity) then
        local displayPlate = vehicleData.fakeplate or vehicleData.plate
        if not GarageDB.uvs(vehicleData.plate, 0, trackedGarage, nil) then
            return { success = false, reason = "database_update_failed" }
        end

        local playerPed = GetPlayerPed(src)
        local playerBucket = GetEntityRoutingBucket(playerPed)

        pcall(SetVehicleNumberPlateText, entity, displayPlate)
        SetEntityRoutingBucket(entity, playerBucket)

        if GetResourceState('pr_carkeys') == 'started' then
            exports['pr_carkeys']:SetLockState(entity, 1)
        end

        SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, true)
        SetEntityHeading(entity, coords.w or coords.h or 0.0)
        FreezeEntityPosition(entity, false)

        local state = Entity(entity).state
        state:set('isPersistent', false, true)
        state:set('garageName', nil, true)

        removeTrackedPersistentVehicle(trackedGarage, vehicleData.plate, netId)
        netId = NetworkGetNetworkIdFromEntity(entity)
        TriggerClientEvent('forge_garage:client:detachPersistentVehicle', -1, vehicleData.plate, netId)
        return { success = true, netId = netId, plate = vehicleData.plate, displayPlate = displayPlate }
    end

    return { success = false, reason = "persistent_entity_not_found" }
end)

GarageBridge.callback.register('forge_garage:cb_server:getvehowner', function (src, plate, shared, pleaseUpdate)
    return GarageDB.gvobp(src, plate, {
        owner = shared
    }, pleaseUpdate)
end)

GarageBridge.callback.register('forge_garage:cb_server:getvehiclePropByPlate', function (_, plate)
    return GarageDB.gpvbp(plate)
end)

GarageBridge.callback.register('forge_garage:cb_server:getVehicleList', function(src, garage, impound, shared)
    return GarageDB.gpvbg(src, garage, {
        impound = impound,
        shared = shared
    })
end)

GarageBridge.callback.register("forge_garage:cb_server:swapGarage", function (source, clientData)
    return GarageDB.svg(clientData.newgarage, clientData.plate)
end)

local function isSocietyActive(name)
    if GetResourceState('Renewed-Banking') == 'started' then
        local ok, val = pcall(function()
            return exports['Renewed-Banking']:getAccountMoney(name)
        end)
        return ok and val ~= nil
    elseif GetResourceState('qb-banking') == 'started' then
        local ok, val = pcall(function()
            return exports['qb-banking']:GetAccount(name)
        end)
        return ok and val ~= nil
    elseif GetResourceState('esx_society') == 'started' then
        local ok = false
        TriggerEvent('esx_society:getSociety', name, function(soc)
            if soc then ok = true end
        end)
        return ok
    end
    return false
end

local function handleInteractiveSale(src, targetSrc, plate, price)
    if src == targetSrc then
        return false, GarageBridge.locale("notify.error.cannot_transfer_to_myself")
    end

    local buyer = pr_lib.framework.GetPlayer(targetSrc)
    if not buyer then
        return false, "O comprador não está online."
    end

    local taxActive = isSocietyActive('government') and Config.TransferTax.enable
    local taxAmount = taxActive and math.floor(price * 0.10) or 0
    local buyerTotal = price + taxAmount
    local sellerPayout = price - taxAmount
    local totalTax = taxAmount * 2

    if price > 0 then
        local vehInfo = GarageDB.gpvbp(plate)
        local vehName = vehInfo and (vehInfo.fullname or vehInfo.model) or plate
        local sellerName = pr_lib.framework.GetPlayerName(src)

        local choice = GarageBridge.callback.await('forge_garage:cb_client:requestPayment', targetSrc, sellerName, plate, vehName, price, taxActive, taxAmount)
        
        if not choice or choice == 'decline' then
            return false, "A proposta de compra foi recusada pelo comprador."
        end

        local buyerBalance = pr_lib.framework.getPlayerMoney(targetSrc, choice)
        if not buyerBalance or buyerBalance < buyerTotal then
            utils.notify(targetSrc, "Você não possui fundos suficientes na conta selecionada.", "error")
            return false, "O comprador não possui fundos suficientes."
        end

        local deduct = pr_lib.framework.removePlayerMoney(targetSrc, choice, buyerTotal, "Vehicle Purchase")
        if not deduct then
            return false, "Falha ao debitar valor do comprador."
        end

        pr_lib.framework.addPlayerMoney(src, "bank", sellerPayout, "Vehicle Sale Payout")

        if taxActive and totalTax > 0 then
            pr_lib.framework.addSocietyBalance('government', totalTax, "Vehicle Sale Tax")
        end

        local success = GarageDB.uvo(src, targetSrc, plate)
        if success then
            utils.notify(targetSrc, ("Você comprou o veículo %s (%s) por R$ %s."):format(vehName, plate, buyerTotal), "success")
            return true, ("Veículo transferido com sucesso! Você recebeu R$ %s."):format(sellerPayout)
        else
            -- refund buyer
            pr_lib.framework.addPlayerMoney(targetSrc, choice, buyerTotal, "Vehicle Purchase Refund")
            -- remove seller payout
            pr_lib.framework.removePlayerMoney(src, "bank", sellerPayout, "Vehicle Sale Refund")
            if taxActive and totalTax > 0 then
                pr_lib.framework.removeSocietyBalance('government', totalTax, "Vehicle Sale Refund")
            end
            return false, "Erro ao transferir no banco de dados."
        end
    else
        local success = GarageDB.uvo(src, targetSrc, plate)
        if success then
            utils.notify(targetSrc, ("Você recebeu o veículo %s de presente."):format(plate), "success")
            return true, "Veículo transferido como presente com sucesso."
        else
            return false, "Erro ao transferir no banco de dados."
        end
    end
end

GarageBridge.callback.register("forge_garage:cb_server:transferVehicle", function (src, clientData)
    local targetSrc = tonumber(clientData.targetSrc)
    local plate = clientData.plate
    local price = tonumber(clientData.price or 0)
    return handleInteractiveSale(src, targetSrc, plate, price)
end)

GarageBridge.callback.register('forge_garage:cb_server:getVehicleInfoByPlate', function (_, plate)
    return GarageDB.gpvbp(plate)
end)

local function hasGarageAdminAccess(source)
    if source == 0 then return true end
    if IsPlayerAceAllowed(source, "group.admin")
        or IsPlayerAceAllowed(source, "admin")
        or IsPlayerAceAllowed(source, "command.garagelist") then
        return true
    end

    local hasPermission = pr_lib.framework and pr_lib.framework.HasPermission
    if type(hasPermission) == "function" then
        local ok, allowed = pcall(hasPermission, source, { "god", "admin" })
        if ok and allowed then return true end
    end

    return false
end

GarageBridge.callback.register('forge_garage:cb_server:getPersistentGarageVehicles', function(source, garageName)
    if not hasGarageAdminAccess(source) then
        return { allowed = false, vehicles = {} }
    end

    local outsideOnly = garageName == "__outside__"
    if not outsideOnly and (type(garageName) ~= "string" or not GarageZone or not GarageZone[garageName]) then
        return { allowed = true, vehicles = {} }
    end

    local rows = GarageDB.getManagementVehicles(garageName, outsideOnly)
    local vehicles = {}

    for i = 1, #rows do
        local row = rows[i]
        local coords = row.parking_coords
        if type(coords) == "string" then
            local ok, decoded = pcall(json.decode, coords)
            coords = ok and decoded or nil
        end

        local rowGarage = row.garage
        local entity, netId = getTrackedPersistentVehicle(rowGarage, row.plate)
        if not entity or not DoesEntityExist(entity) then
            entity, netId = getWorldVehicleByPlate(row.plate)
        end

        local spawned = entity and DoesEntityExist(entity) or false
        local entityBucket = spawned and GetEntityRoutingBucket(entity) or nil
        local garageData = rowGarage and GarageZone and GarageZone[rowGarage] or nil
        local expectedBucket = garageData and garageData.ipl and garageData.ipl.enabled
            and (garageData.ipl.bucket or 0)
            or 0
        local rendered = spawned and entityBucket == expectedBucket

        if spawned then
            local entityCoords = GetEntityCoords(entity)
            coords = {
                x = entityCoords.x,
                y = entityCoords.y,
                z = entityCoords.z,
                h = GetEntityHeading(entity),
            }
        end

        vehicles[#vehicles + 1] = {
            plate = row.plate,
            fakeplate = row.fakeplate,
            vehicle = row.vehicle,
            label = row.vehicle_name,
            garage = rowGarage,
            state = tonumber(row.state) or 0,
            coords = coords,
            spawned = spawned == true,
            rendered = rendered == true,
            netId = spawned and netId or nil,
            bucket = entityBucket,
            expectedBucket = expectedBucket,
        }
    end

    table.sort(vehicles, function(a, b)
        return tostring(a.plate or "") < tostring(b.plate or "")
    end)

    return { allowed = true, vehicles = vehicles, outside = outsideOnly }
end)
GarageBridge.callback.register('forge_garage:cb_server:adminPullGarageVehicle', function(source, garageName, plate, coords)
    if not hasGarageAdminAccess(source) then
        return { success = false, reason = "permission_denied" }
    end
    if type(garageName) ~= "string" or type(plate) ~= "string" or type(coords) ~= "table" then
        return { success = false, reason = "invalid_request" }
    end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    local heading = tonumber(coords.w or coords.h) or 0.0
    if not x or not y or not z then
        return { success = false, reason = "invalid_coords" }
    end

    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed == 0 then
        return { success = false, reason = "player_not_found" }
    end

    local playerCoords = GetEntityCoords(playerPed)
    local dx, dy, dz = x - playerCoords.x, y - playerCoords.y, z - playerCoords.z
    if (dx * dx + dy * dy + dz * dz) > 225.0 then
        return { success = false, reason = "coords_too_far" }
    end

    local vehicleData = GarageDB.gpvbp(plate)
    local outsideOnly = garageName == "__outside__"
    local vehicleState = vehicleData and tonumber(vehicleData.state) or nil
    local vehicleGarage = vehicleData and vehicleData.garage or nil
    local hasNoGarage = vehicleGarage == nil or tostring(vehicleGarage):match("^%s*$") ~= nil
    if not vehicleData
        or (outsideOnly and vehicleState ~= 0 and not hasNoGarage)
        or (not outsideOnly and vehicleGarage ~= garageName) then
        return { success = false, reason = "vehicle_not_available" }
    end

    local actualGarage = vehicleData.garage
    local entity, netId = getTrackedPersistentVehicle(actualGarage, vehicleData.plate)
    if not entity or not DoesEntityExist(entity) then
        entity, netId = getWorldVehicleByPlate(vehicleData.plate)
    end

    local reused = entity and DoesEntityExist(entity) or false
    local targetCoords = { x = x, y = y, z = z, w = heading }
    local displayPlate = vehicleData.fakeplate or vehicleData.plate

    if not reused then
        local props = type(vehicleData.mods) == "table" and vehicleData.mods or {}
        props.plate = displayPlate
        netId, entity = GarageBridge.spawnVehicle(vehicleData.model, targetCoords, props)
        if not netId or not entity or not DoesEntityExist(entity) then
            return { success = false, reason = "spawn_failed" }
        end
    end

    if not GarageDB.setVehicleOutside(vehicleData.plate) then
        if not reused and entity and DoesEntityExist(entity) then DeleteEntity(entity) end
        return { success = false, reason = "database_update_failed" }
    end

    pcall(SetVehicleNumberPlateText, entity, displayPlate)
    SetEntityRoutingBucket(entity, GetEntityRoutingBucket(playerPed))
    SetEntityCoords(entity, x, y, z, false, false, false, true)
    SetEntityHeading(entity, heading)
    FreezeEntityPosition(entity, false)

    local state = Entity(entity).state
    state:set('isPersistent', false, true)
    state:set('plate', vehicleData.plate, true)
    state:set('garageName', nil, true)

    removeTrackedPersistentVehicle(actualGarage, vehicleData.plate, netId)
    TriggerClientEvent('forge_garage:client:detachPersistentVehicle', -1, vehicleData.plate, netId)

    if GetResourceState('pr_carkeys') == 'started' then
        exports['pr_carkeys']:SetLockState(entity, 1)
        if Config.GiveKeys.tempkeys then
            exports['pr_carkeys']:GiveKeys(source, vehicleData.plate)
        end
    end

    return {
        success = true,
        netId = NetworkGetNetworkIdFromEntity(entity),
        plate = vehicleData.plate,
        displayPlate = displayPlate,
        reused = reused,
    }
end)

--- Event
RegisterNetEvent("forge_garage:server:removeTemp", function ( data )
    if GetInvokingResource() then return end
    local citizenid = pr_lib.framework.GetIdentifier(source)
    if tempVehicle[citizenid] == data.model then
        tempVehicle[citizenid] = nil
    end
end)

GarageBridge.addCommand('removeTemp', {
    help = 'Recuperar garagem de player',
    restricted = 'group.admin',
    params = {
        { name = 'id', help = 'ID do player', type = 'number' }
    }
}, function(source, args)
    if args.id then
        local citizenid = pr_lib.framework.GetIdentifier(tonumber(args.id))
        local playerName = pr_lib.framework.GetPlayerName(tonumber(args.id))
        tempVehicle[citizenid] = nil
        GarageBridge.notify(tonumber(args.id), {description = "Seus veículos de aluguel foram recuperados.", type = "success", duration = 10000})
        GarageBridge.notify(source, {description = "Garagem recuperada do id: " .. args.id .. " cidadão: " .. citizenid .. " de nome " .. playerName .. ".", type = "success", duration = 10000})
    else
        GarageBridge.notify(source, {description = "ID inválido.", type = "error", duration = 10000})
    end
end)

RegisterNetEvent("forge_garage:server:updateState", function ( data )
    if GetInvokingResource() then return end
    GarageDB.uvs(data.plate, data.state, data.garage, data.parking_coords)
    
    if data.state == 1 and data.parking_coords and data.garage then
        if data.netId then
            local entity = NetworkGetEntityFromNetworkId(data.netId)
            if entity and DoesEntityExist(entity) then
                local gData = GarageZone and GarageZone[data.garage]
                if gData and gData.persist then
                    if not activeGarages[data.garage] then
                        activeGarages[data.garage] = { players = {}, vehicles = {} }
                    end
                    trackPersistentVehicle(data.garage, data.plate, entity, data.netId)
                else
                    activeStoredVehicles[data.plate] = entity
                    storedVehiclesGarage[data.plate] = data.garage
                    -- Move non-persistent vehicle to private routing bucket
                    local bucketId = 100000 + math.abs(GetHashKey(data.plate) % 100000)
                    SetEntityRoutingBucket(entity, bucketId)
                    FreezeEntityPosition(entity, true)
                end
            end
        else
            triggerPersistentSingleSpawn(data.garage, data.plate, data.parking_coords)
        end
    elseif data.state == 0 and data.garage then
        deletePersistentVehicle(data.garage, data.plate)
        removeTrackedPersistentVehicle(data.garage, data.plate)
        TriggerClientEvent('forge_garage:client:releasePersistentVehicle', -1, data.plate)
    end
end)

RegisterNetEvent("forge_garage:server:saveGarageZone", function(fileData)
    if GetInvokingResource() then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveGarage(fileData)
end)

local propertyGarageCooldown = {}
local propertyGarageVehicleTypes = {
    car = true,
    motorcycle = true,
    cycles = true,
    boat = true,
    helicopter = true,
    planes = true,
}

local function trimPropertyGarageString(value, maxLength)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%z\1-\31\127]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" or #value > maxLength then return nil end
    return value
end

local function propertyGarageAccess(source)
    local config = Config.PropertyGarageCreator or {}
    if config.enabled == false then
        return false, "Criacao de garagens imobiliarias esta desativada."
    end

    if type(config.ace) == "string" and config.ace ~= "" and IsPlayerAceAllowed(source, config.ace) then
        return true
    end

    local player = pr_lib.framework.GetPlayer(source)
    local playerData = player and (player.PlayerData or player)
    local job = playerData and playerData.job
    local jobName = type(job) == "table" and job.name or job
    local grade = type(job) == "table" and job.grade or 0
    if type(grade) == "table" then grade = grade.level or grade.grade or 0 end
    grade = tonumber(grade) or 0

    local minimumGrade = config.jobs and config.jobs[jobName]
    if minimumGrade ~= nil and grade >= (tonumber(minimumGrade) or 0) then
        return true
    end

    return false, "Apenas corretores imobiliarios autorizados podem criar esta garagem."
end

local function findPropertyGarage(propertyId)
    for garageName, garage in pairs(GarageZone or {}) do
        local property = type(garage) == "table" and garage.propertyGarage
        if type(property) == "table" and tostring(property.id) == propertyId then
            return garageName
        end
    end
end

local function finitePropertyGarageNumber(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value < minimum or value > maximum then return nil end
    return value
end

local function sanitizePropertyGarageVector(value, includeHeading)
    local valueType = type(value)
    if valueType ~= "table" and valueType ~= "vector3" and valueType ~= "vector4" then return nil end
    local x = finitePropertyGarageNumber(value.x or value[1], -10000.0, 10000.0)
    local y = finitePropertyGarageNumber(value.y or value[2], -10000.0, 10000.0)
    local z = finitePropertyGarageNumber(value.z or value[3], -1000.0, 3000.0)
    if not x or not y or not z then return nil end

    local result = { x = x, y = y, z = z }
    if includeHeading then
        local heading = finitePropertyGarageNumber(value.w or value[4] or 0.0, -360.0, 720.0)
        if not heading then return nil end
        result.w = heading % 360.0
    end
    return result
end

local function sanitizePropertyGarage(payload)
    if type(payload) ~= "table" or type(payload.garage) ~= "table" then
        return nil, "Dados da garagem invalidos."
    end

    local config = Config.PropertyGarageCreator or {}
    local propertyId = trimPropertyGarageString(tostring(payload.propertyId or ""), 80)
    local label = trimPropertyGarageString(payload.label, 80)
    if not propertyId then return nil, "propertyId invalido." end
    if not label then return nil, "Nome da garagem invalido." end

    local inputGarage = payload.garage
    local vehicleTypes = {}
    local seenTypes = {}
    if type(inputGarage.type) ~= "table" then return nil, "Selecione ao menos um tipo de veiculo." end
    for index = 1, #inputGarage.type do
        local vehicleType = inputGarage.type[index]
        if propertyGarageVehicleTypes[vehicleType] and not seenTypes[vehicleType] then
            seenTypes[vehicleType] = true
            vehicleTypes[#vehicleTypes + 1] = vehicleType
        end
    end
    if #vehicleTypes == 0 then return nil, "Nenhum tipo de veiculo valido foi selecionado." end

    local zones = inputGarage.zones
    local inputPoints = type(zones) == "table" and zones.points
    local maxZonePoints = tonumber(config.maxZonePoints) or 32
    if type(inputPoints) ~= "table" or #inputPoints < 3 or #inputPoints > maxZonePoints then
        return nil, ("A PolyZone deve possuir entre 3 e %d pontos."):format(maxZonePoints)
    end

    local zonePoints = {}
    for index = 1, #inputPoints do
        local point = sanitizePropertyGarageVector(inputPoints[index], false)
        if not point then return nil, ("Ponto %d da PolyZone e invalido."):format(index) end
        zonePoints[index] = point
    end

    local thickness = finitePropertyGarageNumber(zones.thickness or 4.0, 1.0, 20.0)
    if not thickness then return nil, "Altura da PolyZone invalida." end

    local spawnPoints = {}
    local spawnModels = {}
    local inputSpawnPoints = inputGarage.spawnPoint
    local inputSpawnModels = inputGarage.spawnPointVehicle
    local maxSpawnPoints = tonumber(config.maxSpawnPoints) or 64
    if inputSpawnPoints ~= nil then
        if type(inputSpawnPoints) ~= "table" or #inputSpawnPoints > maxSpawnPoints then
            return nil, ("A garagem aceita no maximo %d vagas."):format(maxSpawnPoints)
        end
        for index = 1, #inputSpawnPoints do
            local point = sanitizePropertyGarageVector(inputSpawnPoints[index], true)
            local model = type(inputSpawnModels) == "table" and trimPropertyGarageString(inputSpawnModels[index], 64)
            if not point or not model or not model:match("^[%w_-]+$") then
                return nil, ("Vaga %d e invalida."):format(index)
            end
            spawnPoints[index] = point
            spawnModels[index] = model
        end
    end

    local persist = inputGarage.persist == true
    local interaction = inputGarage.interaction
    if not persist and interaction ~= "radial" and interaction ~= "keypressed" then
        interaction = "keypressed"
    elseif persist then
        interaction = nil
    end

    return {
        propertyId = propertyId,
        label = label,
        invokingResource = trimPropertyGarageString(tostring(payload.invokingResource or "unknown"), 64) or "unknown",
        garage = {
            type = vehicleTypes,
            zones = {
                points = zonePoints,
                thickness = thickness,
            },
            impound = false,
            shared = false,
            persist = persist,
            spawnPoint = #spawnPoints > 0 and spawnPoints or nil,
            spawnPointVehicle = #spawnModels > 0 and spawnModels or nil,
            interaction = interaction,
        },
    }
end

GarageBridge.callback.register("forge_garage:cb_server:canCreatePropertyGarage", function(source, propertyId)
    local allowed, reason = propertyGarageAccess(source)
    if not allowed then return { success = false, code = "forbidden", message = reason } end

    propertyId = trimPropertyGarageString(tostring(propertyId or ""), 80)
    if not propertyId then
        return { success = false, code = "invalid_property_id", message = "propertyId invalido." }
    end

    local existingGarage = findPropertyGarage(propertyId)
    if existingGarage then
        return {
            success = false,
            code = "property_garage_exists",
            message = ("O imovel ja possui a garagem %s."):format(existingGarage),
            garage = existingGarage,
        }
    end

    return { success = true }
end)

GarageBridge.callback.register("forge_garage:cb_server:createPropertyGarage", function(source, payload)
    local allowed, reason = propertyGarageAccess(source)
    if not allowed then return { success = false, code = "forbidden", message = reason } end

    local now = GetGameTimer()
    local cooldown = tonumber((Config.PropertyGarageCreator or {}).cooldown) or 5000
    if propertyGarageCooldown[source] and propertyGarageCooldown[source] > now then
        return { success = false, code = "cooldown", message = "Aguarde antes de criar outra garagem." }
    end

    local sanitized, validationError = sanitizePropertyGarage(payload)
    if not sanitized then
        return { success = false, code = "invalid_data", message = validationError }
    end

    if GarageZone[sanitized.label] then
        return { success = false, code = "garage_name_exists", message = "Ja existe uma garagem com esse nome." }
    end

    local existingGarage = findPropertyGarage(sanitized.propertyId)
    if existingGarage then
        return {
            success = false,
            code = "property_garage_exists",
            message = ("O imovel ja possui a garagem %s."):format(existingGarage),
            garage = existingGarage,
        }
    end

    local player = pr_lib.framework.GetPlayer(source)
    local playerData = player and (player.PlayerData or player) or {}
    sanitized.garage.propertyGarage = {
        id = sanitized.propertyId,
        public = true,
        createdBy = tostring(playerData.citizenid or playerData.identifier or source),
        createdAt = os.time(),
        resource = sanitized.invokingResource,
    }

    GarageZone[sanitized.label] = sanitized.garage
    propertyGarageCooldown[source] = now + cooldown
    storage.SaveGarage(GarageZone)

    return {
        success = true,
        code = "created",
        message = ("Garagem publica %s criada com sucesso."):format(sanitized.label),
        garage = sanitized.label,
        propertyId = sanitized.propertyId,
        public = true,
    }
end)

AddEventHandler("playerDropped", function()
    propertyGarageCooldown[source] = nil
end)
RegisterNetEvent("forge_garage:server:setPlayerGarageBucket", function(bucket)
    if GetInvokingResource() then return end
    local src = source
    local playerPed = GetPlayerPed(src)
    local bucketId = tonumber(bucket) or 0

    SetPlayerRoutingBucket(src, bucketId)

    if playerPed and playerPed ~= 0 then
        SetEntityRoutingBucket(playerPed, bucketId)

        local vehicle = GetVehiclePedIsIn(playerPed, false)
        if vehicle and vehicle ~= 0 then
            SetEntityRoutingBucket(vehicle, bucketId)
        end
    end
end)

RegisterNetEvent("forge_garage:server:saveCustomVehicleName", function (fileData)
    if GetInvokingResource() then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveVehicleName(fileData)
end)

local vehicleSpawnCooldown = {}

GarageBridge.callback.register('forge_garage:server:spawnVehicle', function(source, model, coords, props)
    local playerId = source

    if vehicleSpawnCooldown[playerId] then
        return false, false
    end

    vehicleSpawnCooldown[playerId] = true

    local netid, veh = GarageBridge.spawnVehicle(model, coords, props)
    if not netid or not veh or not DoesEntityExist(veh) then
        vehicleSpawnCooldown[playerId] = nil
        return false, false
    end

    if GetResourceState('pr_carkeys') == 'started' then
        exports['pr_carkeys']:SetLockState(veh, 2)
    end

    if GetResourceState('pr_carkeys') == 'started' and Config.GiveKeys.tempkeys then
        SetTimeout(200, function()
            local plate = GetVehicleNumberPlateText(veh)
            exports['pr_carkeys']:GiveKeys(playerId, plate)
        end)
    end

    SetTimeout(3000, function()
        vehicleSpawnCooldown[playerId] = nil
    end)

    return netid, veh
end)

--- exports
exports("Garage", function ()
    return GarageZone
end)

-- Key Manager Callbacks

GarageBridge.callback.register('forge_garage:cb_server:getPlayerKeyItems', function(source)
    local src = source
    local keysList = {}
    
    if GetResourceState('ox_inventory') == 'started' then
        local permSlots = exports.ox_inventory:GetSlotsWithItem(src, 'carkey_permanent', nil)
        if permSlots then
            for _, slot in pairs(permSlots) do
                if slot.metadata and slot.metadata.barcode and slot.metadata.plate then
                    keysList[#keysList+1] = {
                        slot = slot.slot,
                        barcode = slot.metadata.barcode,
                        plate = slot.metadata.plate,
                        label = slot.metadata.label or ("Placa: " .. slot.metadata.plate),
                        modelo = slot.metadata.modelo or slot.metadata.plate,
                        type = "original"
                    }
                end
            end
        end

        local copySlots = exports.ox_inventory:GetSlotsWithItem(src, 'carkey_copy', nil)
        if copySlots then
            for _, slot in pairs(copySlots) do
                if slot.metadata and slot.metadata.barcode and slot.metadata.plate then
                    keysList[#keysList+1] = {
                        slot = slot.slot,
                        barcode = slot.metadata.barcode,
                        plate = slot.metadata.plate,
                        label = slot.metadata.label or ("Placa: " .. slot.metadata.plate),
                        modelo = slot.metadata.modelo or slot.metadata.plate,
                        type = "copy"
                    }
                end
            end
        end
    end

    return keysList
end)

GarageBridge.callback.register('forge_garage:cb_server:getOwnedVehiclesForKeys', function(source)
    local src = source
    local citizenid = pr_lib.framework.GetIdentifier(src)
    if not citizenid then return {} end

    local results = MySQL.query.await([[
        SELECT vehicle, vehicle_name, plate, fakeplate
        FROM player_vehicles WHERE citizenid = ?
    ]], {citizenid})

    local vehicles = {}
    if results and #results > 0 then
        for i=1, #results do
            local data = results[i]
            local model = data.vehicle
            local plate = data.plate
            local fakeplate = data.fakeplate
            local name = data.vehicle_name
            
            vehicles[#vehicles+1] = {
                model = model,
                plate = plate,
                fakeplate = fakeplate,
                vehicle_name = name or plate
            }
        end
    end
    return vehicles
end)

GarageBridge.callback.register('forge_garage:cb_server:copyInventoryKey', function(source, barcode)
    local src = source
    if pr_lib.framework.RemovePlayerAccountBalance(src, "cash", Config.GiveKeys.price, "Key Copy Fee") then
        local result = exports["pr_carkeys"]:CopyKey(src, barcode)
        if result and result.success then
            return true, result.barcode
        else
            -- refund if failed
            pr_lib.framework.AddPlayerAccountBalance(src, "cash", Config.GiveKeys.price, "Key Copy Fee Refund")
            return false, result and result.reason or "unknown"
        end
    else
        return false, "no_money"
    end
end)

GarageBridge.callback.register('forge_garage:cb_server:buyOriginalKeyForPlate', function(source, plate)
    local src = source
    if pr_lib.framework.RemovePlayerAccountBalance(src, "cash", Config.LostKeyPrice, "Lost Key Replacement Fee") then
        local result = exports["pr_carkeys"]:BuyOriginalKey(src, plate)
        if result and result.success then
            return true, result.barcode
        else
            -- refund if failed
            pr_lib.framework.AddPlayerAccountBalance(src, "cash", Config.LostKeyPrice, "Lost Key Fee Refund")
            return false, result and result.reason or "unknown"
        end
    else
        return false, "no_money"
    end
end)

GarageBridge.callback.register('forge_garage:cb_server:transferVehicleByCitizenId', function(source, clientData)
    local src = source
    local targetCitizenId = clientData.targetCitizenId
    local plate = clientData.plate
    local price = tonumber(clientData.price or 0)

    local tp = pr_lib.framework.GetPlayerFromIdentifier(targetCitizenId)
    if tp then
        local targetSrc = (tp.PlayerData and tp.PlayerData.source) or tp.source
        return handleInteractiveSale(src, targetSrc, plate, price)
    else
        if price > 0 then
            return false, "O destinatário precisa estar online para aceitar propostas de valor superior a R$ 0."
        else
            local success, response = GarageDB.uvoByCitizenId(src, targetCitizenId, plate)
            if success then
                return true, ("Veículo %s transferido com sucesso (como presente) para o CitizenID %s."):format(plate, targetCitizenId)
            else
                if response == "citizenid_not_found" then
                    return false, "CitizenID não encontrado no banco de dados."
                else
                    return false, "Erro interno ao transferir veículo no banco de dados."
                end
            end
        end
    end
end)

------------------------------------------------------------------------
-- PERSISTENT PARKED VEHICLES MANAGER
------------------------------------------------------------------------

activeGarages = {} -- key: garageName, value: { players = { [src] = true }, vehicles = { [plate] = netId }, spawner = src }

RegisterNetEvent('forge_garage:server:setRevvingVehicleProtection', function(data)
    if GetInvokingResource() or type(data) ~= 'table' then return end

    local netId = tonumber(data.netId)
    if not netId or netId == 0 or netId == 65533 then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or not DoesEntityExist(entity) then return end

    local state = Entity(entity).state
    if state.isPersistent ~= true then return end
    local entityPlate = state.plate or GetVehicleNumberPlateText(entity)
    local suppliedPlate = normalizePlate(data.plate)
    if suppliedPlate and suppliedPlate ~= normalizePlate(entityPlate) then return end

    -- Both start and finish signals extend the grace period. This protects the
    -- network handoff immediately after pr_carkeys removes its statebag.
    protectRevvingPersistentVehicle(entityPlate, netId)
end)

-- Helper to find a spawner player for a garage
local function getSpawnerForGarage(garageName)
    local data = activeGarages[garageName]
    if not data or not data.players then return nil end
    
    if data.spawner and data.players[data.spawner] then
        return data.spawner
    end
    
    local playerKeys = tableKeys(data.players)
    for i = 1, #playerKeys do
        local src = playerKeys[i]
        data.spawner = src
        return src
    end
    return nil
end

function deletePersistentVehicle(garageName, plate)
    local data = activeGarages[garageName]
    if not data or not data.vehicles then return end
    
    local plateKey = normalizePlate(plate)
    local storedPlate = plate
    local netId = data.vehicles[plate]
    if not netId and plateKey then
        local vehiclePlates = tableKeys(data.vehicles)
        for i = 1, #vehiclePlates do
            local candidate = vehiclePlates[i]
            if normalizePlate(candidate) == plateKey then
                storedPlate = candidate
                netId = data.vehicles[candidate]
                break
            end
        end
    end

    if netId then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            if isPersistentVehicleProtected(plate, entity, netId) then return end
            DeleteEntity(entity)
        end
        data.vehicles[storedPlate] = nil
    end
end

function triggerPersistentSingleSpawn(garageName, plate, parkingCoords)
    local data = activeGarages[garageName]
    if not data then return end

    local trackedEntity, trackedNetId = getTrackedPersistentVehicle(garageName, plate)
    if trackedEntity or isPersistentVehicleProtected(plate, trackedEntity, trackedNetId) then return end
    
    local spawner = getSpawnerForGarage(garageName)
    if not spawner then return end

    local result = MySQL.single.await([[
        SELECT mods, deformation, fuel, engine, body
        FROM player_vehicles
        WHERE plate = ? OR fakeplate = ?
    ]], {plate, plate})
    
    if result then
        local vehList = {
            {
                plate = plate,
                mods = result.mods,
                deformation = result.deformation,
                fuel = result.fuel,
                engine = result.engine,
                body = result.body,
                parking_coords = parkingCoords
            }
        }
        TriggerClientEvent('forge_garage:client:spawnPersistent', spawner, garageName, vehList)
    end
end

RegisterNetEvent('forge_garage:server:enterPersistentZone', function(garageName)
    local src = source
    if not activeGarages[garageName] then
        activeGarages[garageName] = { players = {}, vehicles = {} }
    end
    activeGarages[garageName].players[src] = true

    local playerCount = countTableEntries(activeGarages[garageName].players)

    if playerCount == 1 then
        activeGarages[garageName].spawner = src
        
        -- Pull all active vehicles for this garage back to the player's routing bucket
        local playerBucket = GetEntityRoutingBucket(GetPlayerPed(src))
        local storedPlates = tableKeys(activeStoredVehicles)
        for i = 1, #storedPlates do
            local plate = storedPlates[i]
            local entity = activeStoredVehicles[plate]
            if DoesEntityExist(entity) and storedVehiclesGarage[plate] == garageName then
                local netId = NetworkGetNetworkIdFromEntity(entity)
                if isPersistentVehicleProtected(plate, entity, netId) then
                    goto skipStoredVehicleEnter
                end
                SetEntityRoutingBucket(entity, playerBucket)
                FreezeEntityPosition(entity, true)
                if netId and netId ~= 0 and netId ~= 65533 then
                    activeGarages[garageName].vehicles[plate] = netId
                    TriggerClientEvent('forge_garage:client:registerExistingPersistentVehicle', -1, plate, netId)
                end
            end
            ::skipStoredVehicleEnter::
        end

        local vehicles = GarageDB.getPersistentVehicles(garageName)
        if vehicles and #vehicles > 0 then
            local toSpawn = {}
            for i = 1, #vehicles do
                local plate = vehicles[i].plate
                local entity, netId = getTrackedPersistentVehicle(garageName, plate)
                if entity and DoesEntityExist(entity) then
                    trackPersistentVehicle(garageName, plate, entity, netId)
                elseif not isPersistentVehicleProtected(plate, entity, netId) then
                    toSpawn[#toSpawn + 1] = vehicles[i]
                end
            end
            if #toSpawn > 0 then
                TriggerClientEvent('forge_garage:client:spawnPersistent', src, garageName, toSpawn)
            end
        end
    end
end)

RegisterNetEvent('forge_garage:server:exitPersistentZone', function(garageName)
    local src = source
    if not activeGarages[garageName] then return end
    
    activeGarages[garageName].players[src] = nil
    
    local playerCount = countTableEntries(activeGarages[garageName].players)
    
    if playerCount == 0 then
        -- Move all stored vehicle entities for this garage to private routing buckets
        local garageVehiclePlates = tableKeys(activeGarages[garageName].vehicles)
        for i = 1, #garageVehiclePlates do
            local plate = garageVehiclePlates[i]
            if withdrawingPersistentVehicles[normalizePlate(plate)] then
                goto skipGarageVehicleFreeze
            end
            local netId = activeGarages[garageName].vehicles[plate]
            local entity = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(entity) then
                if isPersistentVehicleProtected(plate, entity, netId) then
                    goto skipGarageVehicleFreeze
                end
                local bucketId = 100000 + math.abs(GetHashKey(plate) % 100000)
                SetEntityRoutingBucket(entity, bucketId)
                FreezeEntityPosition(entity, true)
            end
            ::skipGarageVehicleFreeze::
        end
        local storedPlates = tableKeys(activeStoredVehicles)
        for i = 1, #storedPlates do
            local plate = storedPlates[i]
            if withdrawingPersistentVehicles[normalizePlate(plate)] then
                goto skipStoredVehicleFreeze
            end
            local entity = activeStoredVehicles[plate]
            if DoesEntityExist(entity) and storedVehiclesGarage[plate] == garageName then
                local netId = NetworkGetNetworkIdFromEntity(entity)
                if isPersistentVehicleProtected(plate, entity, netId) then
                    goto skipStoredVehicleFreeze
                end
                local bucketId = 100000 + math.abs(GetHashKey(plate) % 100000)
                SetEntityRoutingBucket(entity, bucketId)
                FreezeEntityPosition(entity, true)
            end
            ::skipStoredVehicleFreeze::
        end
        activeGarages[garageName] = nil
    else
        if activeGarages[garageName].spawner == src then
            activeGarages[garageName].spawner = nil
            local playerKeys = tableKeys(activeGarages[garageName].players)
            for i = 1, #playerKeys do
                local newSrc = playerKeys[i]
                activeGarages[garageName].spawner = newSrc
                break
            end
        end
    end
end)

RegisterNetEvent('forge_garage:server:confirmPersistentSpawns', function(garageName, spawnsList)
    if not activeGarages[garageName] or type(spawnsList) ~= 'table' then return end

    for i = 1, #spawnsList do
        local data = spawnsList[i]
        local netId = data and tonumber(data.netId)
        local plate = data and data.plate
        local incomingEntity = netId and NetworkGetEntityFromNetworkId(netId) or nil

        if plate and incomingEntity and DoesEntityExist(incomingEntity) then
            local entityPlate = Entity(incomingEntity).state.plate or GetVehicleNumberPlateText(incomingEntity)
            if normalizePlate(entityPlate) == normalizePlate(plate) then
                local existingEntity, existingNetId = getTrackedPersistentVehicle(garageName, plate)
                local canonicalEntity = incomingEntity
                local canonicalNetId = netId

                if existingEntity and DoesEntityExist(existingEntity) and existingEntity ~= incomingEntity then
                    local incomingProtected = isPersistentVehicleProtected(plate, incomingEntity, netId)
                    local existingProtected = isPersistentVehicleProtected(plate, existingEntity, existingNetId)

                    print(('[forge-garage][persistent] duplicate prevented plate=%s existingNetId=%s incomingNetId=%s'):format(
                        tostring(plate), tostring(existingNetId), tostring(netId)
                    ))

                    if incomingProtected and not existingProtected then
                        DeleteEntity(existingEntity)
                    else
                        DeleteEntity(incomingEntity)
                        canonicalEntity = existingEntity
                        canonicalNetId = existingNetId
                    end
                end

                if canonicalEntity and DoesEntityExist(canonicalEntity) then
                    trackPersistentVehicle(garageName, plate, canonicalEntity, canonicalNetId)
                    TriggerClientEvent('forge_garage:client:registerExistingPersistentVehicle', -1, plate, canonicalNetId)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local garageNames = tableKeys(activeGarages)
    for i = 1, #garageNames do
        local garageName = garageNames[i]
        local data = activeGarages[garageName]
        if data.players[src] then
            data.players[src] = nil
            local playerCount = countTableEntries(data.players)
            if playerCount == 0 then
                local vehiclePlates = tableKeys(data.vehicles)
                for j = 1, #vehiclePlates do
                    local plate = vehiclePlates[j]
                    if withdrawingPersistentVehicles[normalizePlate(plate)] then
                        goto skipDropVehicleDelete
                    end
                    local netId = data.vehicles[plate]
                    local entity = NetworkGetEntityFromNetworkId(netId)
                    if DoesEntityExist(entity) then
                        if isPersistentVehicleProtected(plate, entity, netId) then
                            goto skipDropVehicleDelete
                        end
                        DeleteEntity(entity)
                    end
                    ::skipDropVehicleDelete::
                end
                activeGarages[garageName] = nil
            else
                if data.spawner == src then
                    data.spawner = nil
                    local playerKeys = tableKeys(data.players)
                    for j = 1, #playerKeys do
                        local newSrc = playerKeys[j]
                        data.spawner = newSrc
                        break
                    end
                end
            end
        end
    end
end)

-- Callback to check if player holds keys for a vehicle plate in their inventory
GarageBridge.callback.register('forge_garage:cb_server:hasKeyForPlate', function(source, plate)
    local src = source
    local targetPlate = normalizePlate(plate)
    if not targetPlate then return false end

    if GetResourceState('pr_carkeys') == 'started' then
        local ok, hasAccess = pcall(function()
            return exports['pr_carkeys']:HasVehicleAccess(src, targetPlate)
        end)
        if ok and hasAccess == true then
            return true
        end
    end

    if GetResourceState('ox_inventory') == 'started' then
        local permSlots = exports.ox_inventory:GetSlotsWithItem(src, 'carkey_permanent', nil)
        if permSlots then
            for _, slot in pairs(permSlots) do
                if slot.metadata and normalizePlate(slot.metadata.plate) == targetPlate then
                    return true
                end
            end
        end

        local copySlots = exports.ox_inventory:GetSlotsWithItem(src, 'carkey_copy', nil)
        if copySlots then
            for _, slot in pairs(copySlots) do
                if slot.metadata and normalizePlate(slot.metadata.plate) == targetPlate then
                    return true
                end
            end
        end
    end
    return false
end)

-- Event to withdraw a persistent vehicle when player drives off
RegisterNetEvent('forge_garage:server:withdrawPersistentVehicle', function(garageName, plate, netId)
    local src = source
    if not plate then return end

    local plateKey = normalizePlate(plate)
    if not plateKey then return end
    if withdrawingPersistentVehicles[plateKey] then return end
    withdrawingPersistentVehicles[plateKey] = true
    
    -- Server-side security check: verify the player has keys
    local hasKey = false
    if GetResourceState('pr_carkeys') == 'started' then
        local ok, hasAccess = pcall(function()
            return exports['pr_carkeys']:HasVehicleAccess(src, plateKey)
        end)
        hasKey = ok and hasAccess == true
    end

    if not hasKey and GetResourceState('ox_inventory') == 'started' then
        local permSlots = exports.ox_inventory:GetSlotsWithItem(src, 'carkey_permanent', nil)
        if permSlots then
            for _, slot in pairs(permSlots) do
                if slot.metadata and normalizePlate(slot.metadata.plate) == plateKey then
                    hasKey = true
                    break
                end
            end
        end
        if not hasKey then
            local copySlots = exports.ox_inventory:GetSlotsWithItem(src, 'carkey_copy', nil)
            if copySlots then
                for _, slot in pairs(copySlots) do
                    if slot.metadata and normalizePlate(slot.metadata.plate) == plateKey then
                        hasKey = true
                        break
                    end
                end
            end
        end
    end

    if hasKey then
        -- Update vehicle status to out of garage in database
        local updated = GarageDB.uvs(plate, 0, nil, nil)
        if not updated then
            print(("[forge-garage][persistent] failed to withdraw vehicle from database plate=%s normalized=%s src=%s"):format(tostring(plate), tostring(plateKey), tostring(src)))
            withdrawingPersistentVehicles[plateKey] = nil
            return
        end
        
        removeTrackedPersistentVehicle(garageName, plate, netId)

        -- Detach the already spawned entity from the persistent garage GarageBridge.cache.
        -- This does not spawn or warp anything; it only stops treating the current entity as parked.
        TriggerClientEvent('forge_garage:client:detachPersistentVehicle', -1, plate, netId)
    end

    SetTimeout(3000, function()
        withdrawingPersistentVehicles[plateKey] = nil
    end)
end)
