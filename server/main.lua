if not lib.checkDependency('ox_lib', '3.23.1') then error('This resource requires ox_lib version 3.23.1') end
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
lib.callback.register('forge_garage:cb_server:removeMoney', function(src, type, amount)
    return pr_lib.framework.RemovePlayerAccountBalance(src, type, amount, "Garage interaction")
end)

lib.callback.register('forge_garage:cb_server:pullVehicleFromBucket', function(source, plate, coords, garageName)
    local src = source
    local entity, netId = getTrackedPersistentVehicle(garageName, plate)
    
    if entity and DoesEntityExist(entity) then
        local playerPed = GetPlayerPed(src)
        local playerBucket = GetEntityRoutingBucket(playerPed)
        
        -- Move back to player's routing bucket
        SetEntityRoutingBucket(entity, playerBucket)
        
        -- Lock the vehicle using pr_carkeys
        if GetResourceState('pr_carkeys') == 'started' then
            exports['pr_carkeys']:SetLockState(entity, 2)
        end
        
        -- Teleport to target coordinates
        SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, true)
        SetEntityHeading(entity, coords.w or coords.h or 0.0)
        FreezeEntityPosition(entity, false)
        
        removeTrackedPersistentVehicle(garageName, plate, netId)
        netId = NetworkGetNetworkIdFromEntity(entity)
        return { success = true, netId = netId }
    end
    
    return { success = false }
end)

lib.callback.register('forge_garage:cb_server:getvehowner', function (src, plate, shared, pleaseUpdate)
    return GarageDB.gvobp(src, plate, {
        owner = shared
    }, pleaseUpdate)
end)

lib.callback.register('forge_garage:cb_server:getvehiclePropByPlate', function (_, plate)
    return GarageDB.gpvbp(plate)
end)

lib.callback.register('forge_garage:cb_server:getVehicleList', function(src, garage, impound, shared)
    return GarageDB.gpvbg(src, garage, {
        impound = impound,
        shared = shared
    })
end)

lib.callback.register("forge_garage:cb_server:swapGarage", function (source, clientData)
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
        return false, locale("notify.error.cannot_transfer_to_myself")
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

        local choice = lib.callback.await('forge_garage:cb_client:requestPayment', targetSrc, sellerName, plate, vehName, price, taxActive, taxAmount)
        
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

lib.callback.register("forge_garage:cb_server:transferVehicle", function (src, clientData)
    local targetSrc = tonumber(clientData.targetSrc)
    local plate = clientData.plate
    local price = tonumber(clientData.price or 0)
    return handleInteractiveSale(src, targetSrc, plate, price)
end)

lib.callback.register('forge_garage:cb_server:getVehicleInfoByPlate', function (_, plate)
    return GarageDB.gpvbp(plate)
end)

--- Event
RegisterNetEvent("forge_garage:server:removeTemp", function ( data )
    if GetInvokingResource() then return end
    local citizenid = pr_lib.framework.GetIdentifier(source)
    if tempVehicle[citizenid] == data.model then
        tempVehicle[citizenid] = nil
    end
end)

lib.addCommand('removeTemp', {
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
        lib.notify(tonumber(args.id), {description = "Seus veículos de aluguel foram recuperados.", type = "success", duration = 10000})
        lib.notify(source, {description = "Garagem recuperada do id: " .. args.id .. " cidadão: " .. citizenid .. " de nome " .. playerName .. ".", type = "success", duration = 10000})
    else
        lib.notify(source, {description = "ID inválido.", type = "error", duration = 10000})
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

lib.callback.register('forge_garage:server:spawnVehicle', function(source, model, coords, props)
    local playerId = source

    if vehicleSpawnCooldown[playerId] then
        return false, false
    end

    vehicleSpawnCooldown[playerId] = true

    local netid, veh = qbx.spawnVehicle({
        model = model,
        spawnSource = coords,
        warp = false,
        props = props
    })

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

lib.callback.register('forge_garage:cb_server:getPlayerKeyItems', function(source)
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

lib.callback.register('forge_garage:cb_server:getOwnedVehiclesForKeys', function(source)
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

lib.callback.register('forge_garage:cb_server:copyInventoryKey', function(source, barcode)
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

lib.callback.register('forge_garage:cb_server:buyOriginalKeyForPlate', function(source, plate)
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

lib.callback.register('forge_garage:cb_server:transferVehicleByCitizenId', function(source, clientData)
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
lib.callback.register('forge_garage:cb_server:hasKeyForPlate', function(source, plate)
    local src = source
    local targetPlate = normalizePlate(plate)
    if not targetPlate then return false end

    if GetResourceState('pr_carkeys') == 'started' then
        local ok, hasAccess = pcall(function()
            return exports['pr_carkeys']:HasVehicleAccess(src, targetPlate)
        end)
        if ok then
            return hasAccess == true
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

        -- Detach the already spawned entity from the persistent garage cache.
        -- This does not spawn or warp anything; it only stops treating the current entity as parked.
        TriggerClientEvent('forge_garage:client:detachPersistentVehicle', -1, plate, netId)
    end

    SetTimeout(3000, function()
        withdrawingPersistentVehicles[plateKey] = nil
    end)
end)
