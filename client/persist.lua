local activeZones = {}
local spawnedVehs = {} -- key: netId, value: entity handle
local spawnedPlates = {} -- key: plate, value: entity handle
local spawningPlates = {}
local unlockedPersistent = {}
local withdrawingPlates = {}
local detachedPersistent = {}
local driverKeyCache = {}
local revvingPlates = {}
local revvingNetIds = {}
local revvingVehicles = {}
local getPersistentVehicleEntity
local REV_ENGINE_PROTECTION_MS = 5000

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

local function getPersistentZoneAnchor(garage)
    local points = garage and garage.zones and garage.zones.points
    if type(points) == 'table' and #points > 0 then
        local x, y, z = 0.0, 0.0, 0.0
        for index = 1, #points do
            local point = points[index]
            x = x + (tonumber(point.x) or 0.0)
            y = y + (tonumber(point.y) or 0.0)
            z = z + (tonumber(point.z) or 0.0)
        end

        return vec3(x / #points, y / #points, z / #points)
    end

    local ipl = garage and garage.ipl
    local firstFloor = ipl and type(ipl.floors) == 'table' and ipl.floors[1]
    local coords = firstFloor and (firstFloor.coords or firstFloor) or ipl and ipl.exit
    if coords then
        return vec3(coords.x, coords.y, coords.z)
    end
end

local function normalizePlate(plate)
    if not plate then return nil end
    return tostring(plate):gsub("%s+", ""):upper()
end

local function enforceVehiclePlate(vehicle, plate)
    if not vehicle or vehicle == 0 or not plate or not DoesEntityExist(vehicle) then return end

    SetVehicleNumberPlateText(vehicle, tostring(plate))
    CreateThread(function()
        for _ = 1, 8 do
            Wait(100)
            if not DoesEntityExist(vehicle) then return end
            SetVehicleNumberPlateText(vehicle, tostring(plate))
        end
    end)
end

local function setPersistentUnlocked(plate, value)
    local key = normalizePlate(plate)
    if not key then return end

    unlockedPersistent[key] = value == true or nil
    if pr_lib and pr_lib.cache then
        local cacheKey = 'persistent:unlocked:' .. key
        if value == true then
            pr_lib.cache.set(cacheKey, true)
        else
            pr_lib.cache.clear(cacheKey)
        end
    end
end

local function setPersistentDetached(plate, value)
    local key = normalizePlate(plate)
    if not key then return end

    detachedPersistent[key] = value == true or nil
    if value == true then
        setPersistentUnlocked(key, false)
    end
end

local function setRevvingVehicle(plate, vehicle, netId, active)
    local key = normalizePlate(plate)
    local expires = GetGameTimer() + REV_ENGINE_PROTECTION_MS

    local function extendProtection(current)
        if current and current > expires then return current end
        return expires
    end

    if key then
        revvingPlates[key] = extendProtection(revvingPlates[key])
    end
    if netId and netId ~= 0 and netId ~= 65533 then
        revvingNetIds[netId] = extendProtection(revvingNetIds[netId])
    end
    if vehicle and vehicle ~= 0 then
        revvingVehicles[vehicle] = extendProtection(revvingVehicles[vehicle])
    end
end

local function isRevvingVehicle(plate, vehicle, netId)
    local now = GetGameTimer()
    local key = normalizePlate(plate)

    if key and revvingPlates[key] then
        if revvingPlates[key] > now then return true end
        revvingPlates[key] = nil
    end
    if netId and revvingNetIds[netId] then
        if revvingNetIds[netId] > now then return true end
        revvingNetIds[netId] = nil
    end
    if vehicle and vehicle ~= 0 and revvingVehicles[vehicle] then
        if revvingVehicles[vehicle] > now then return true end
        revvingVehicles[vehicle] = nil
    end
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and Entity(vehicle).state.pr_carkeys_revving then
        return true
    end

    return false
end

local function requestEntityControl(entity, timeoutMs)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    local deadline = GetGameTimer() + (timeoutMs or 750)
    NetworkRequestControlOfEntity(entity)

    while DoesEntityExist(entity) and not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end

    return DoesEntityExist(entity) and NetworkHasControlOfEntity(entity)
end

local function settlePersistentVehicle(vehicle, coords)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not coords then return false end

    FreezeEntityPosition(vehicle, false)
    SetEntityCollision(vehicle, true, true)
    SetEntityLoadCollisionFlag(vehicle, true)
    SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z + 0.5, false, false, false)
    SetEntityHeading(vehicle, coords.h or coords.w or 0.0)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local collisionDeadline = GetGameTimer() + 2500
    while not HasCollisionLoadedAroundEntity(vehicle) and GetGameTimer() < collisionDeadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
    end

    local grounded = false
    for _ = 1, 20 do
        if SetVehicleOnGroundProperly(vehicle) then
            grounded = true
            break
        end
        Wait(50)
    end

    if not grounded then
        SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z, false, false, false)
    end

    SetEntityHeading(vehicle, coords.h or coords.w or 0.0)
    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
    Wait(100)
    return grounded
end

local function unlockPersistentVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 and netId ~= 65533 then
        SetNetworkIdCanMigrate(netId, true)
    end

    requestEntityControl(vehicle, 1000)

    FreezeEntityPosition(vehicle, false)
    SetVehicleHandbrake(vehicle, false)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
    Entity(vehicle).state:set("doorslockstate", 1, true)

    CreateThread(function()
        for _ = 1, 15 do
            if not DoesEntityExist(vehicle) then return end
            FreezeEntityPosition(vehicle, false)
            SetVehicleHandbrake(vehicle, false)
            SetVehicleUndriveable(vehicle, false)
            SetVehicleDoorsLocked(vehicle, 1)
            SetVehicleDoorsLockedForAllPlayers(vehicle, false)
            SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
            Wait(100)
        end
    end)
end

local function releaseLocalPersistentVehicle(plate, vehicle, netId)
    local key = normalizePlate(plate)
    if not key then return end

    setPersistentDetached(key, true)
    driverKeyCache[key] = nil

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local state = Entity(vehicle).state
        state:set('isPersistent', nil, false)
        state:set('garageName', nil, false)
        state:set('pr_carkeys_skipRevPed', nil, false)
        unlockPersistentVehicle(vehicle)
    end

    local vehKeys = tableKeys(spawnedVehs)
    for i = 1, #vehKeys do
        local storedNetId = vehKeys[i]
        if storedNetId == netId or spawnedVehs[storedNetId] == vehicle then
            spawnedVehs[storedNetId] = nil
        end
    end

    local plateKeys = tableKeys(spawnedPlates)
    for i = 1, #plateKeys do
        local storedPlate = plateKeys[i]
        if normalizePlate(storedPlate) == key or spawnedPlates[storedPlate] == vehicle then
            spawnedPlates[storedPlate] = nil
        end
    end

    if pr_lib and pr_lib.cache then
        pr_lib.cache.clear('persistent:veh:' .. plate)
        pr_lib.cache.clear('persistent:veh:' .. key)
        pr_lib.cache.clear('persistent:unlocked:' .. key)
    end
end

local function isPersistentUnlocked(plate)
    local key = normalizePlate(plate)
    if not key then return false end
    if unlockedPersistent[key] then return true end
    if pr_lib and pr_lib.cache then
        return pr_lib.cache.get('persistent:unlocked:' .. key) == true
    end
    return false
end

local function hasDriverKeyForPlate(plate)
    local key = normalizePlate(plate)
    if not key then return false end

    local cached = driverKeyCache[key]
    local now = GetGameTimer()
    if cached and cached.expires > now then
        return cached.value == true
    end

    local value = GarageBridge.callback.await('forge_garage:cb_server:hasKeyForPlate', false, plate) == true
    driverKeyCache[key] = {
        value = value,
        expires = now + 1500
    }
    return value
end

local function requestPersistentWithdraw(garageName, plate, vehicle)
    local key = normalizePlate(plate)
    if not garageName or not key or withdrawingPlates[key] then return end
    local netId = vehicle and DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    if isRevvingVehicle(plate, vehicle, netId) then return end

    withdrawingPlates[key] = true
    releaseLocalPersistentVehicle(plate, vehicle, netId)
    TriggerServerEvent('forge_garage:server:withdrawPersistentVehicle', garageName, plate, netId)
end

RegisterNetEvent('forge_garage:client:markPersistentUnlocked', function(plate)
    setPersistentUnlocked(plate, true)
end)

AddEventHandler('pr_carkeys:client:vehicleLockChanged', function(data)
    if not data or not data.unlocked then return end

    local vehicle = data.vehicle
    if (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and data.netId and NetworkDoesNetworkIdExist(data.netId) then
        vehicle = NetToVeh(data.netId)
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local state = Entity(vehicle).state
    if not state or not state.isPersistent then return end

    local plate = state.plate or data.plate
    setPersistentDetached(plate, false)
    unlockPersistentVehicle(vehicle)
    setPersistentUnlocked(plate, true)
end)

AddEventHandler('pr_carkeys:client:revEngineState', function(data)
    if not data then return end

    local vehicle = data.vehicle
    if (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and data.netId and NetworkDoesNetworkIdExist(data.netId) then
        vehicle = NetToVeh(data.netId)
    end

    local netId = data.netId
    if (not netId or netId == 0 or netId == 65533) and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end

    setRevvingVehicle(data.plate, vehicle, netId, data.active == true)
    TriggerServerEvent('forge_garage:server:setRevvingVehicleProtection', {
        plate = data.plate,
        netId = netId,
        active = data.active == true
    })
end)

RegisterNetEvent('forge_garage:client:detachPersistentVehicle', function(plate, netId)
    local key = normalizePlate(plate)
    if not key then return end

    local storedPlate = plate
    local plateKeys = tableKeys(spawnedPlates)
    for i = 1, #plateKeys do
        local candidate = plateKeys[i]
        if normalizePlate(candidate) == key then
            storedPlate = candidate
            break
        end
    end

    local vehicle = getPersistentVehicleEntity(storedPlate)
    if (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and netId and NetworkDoesNetworkIdExist(netId) then
        vehicle = NetToVeh(netId)
    end

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local state = Entity(vehicle).state
        state:set('isPersistent', nil, false)
        state:set('garageName', nil, false)
        state:set('pr_carkeys_skipRevPed', nil, false)

        unlockPersistentVehicle(vehicle)
    end

    local vehKeys = tableKeys(spawnedVehs)
    for i = 1, #vehKeys do
        local storedNetId = vehKeys[i]
        if spawnedPlates[storedPlate] == spawnedVehs[storedNetId] or storedNetId == netId then
            spawnedVehs[storedNetId] = nil
        end
    end

    spawnedPlates[storedPlate] = nil
    withdrawingPlates[key] = nil
    driverKeyCache[key] = nil
    setPersistentDetached(key, true)

    if pr_lib and pr_lib.cache then
        pr_lib.cache.clear('persistent:veh:' .. storedPlate)
        pr_lib.cache.clear('persistent:veh:' .. key)
    end
end)

local function setupPersistentGarages()
    local zoneKeys = tableKeys(activeZones)
    for i = 1, #zoneKeys do
        local k = zoneKeys[i]
        local v = activeZones[k]
        if v and v.remove then
            v:remove()
        end
    end
    activeZones = {}

    if not GarageZone then return end

    local garageKeys = tableKeys(GarageZone)
    local registered = 0
    local persistentConfigured = 0
    local streamingRadius = math.max(tonumber(Config.PersistentDistance) or 300.0, 50.0)

    for i = 1, #garageKeys do
        local k = garageKeys[i]
        local v = GarageZone[k]
        if v and v.persist then
            persistentConfigured = persistentConfigured + 1
        end
        local anchor = v and v.persist and getPersistentZoneAnchor(v)
        if anchor then
            activeZones[k] = GarageBridge.zones.sphere({
                coords = anchor,
                radius = streamingRadius,
                onEnter = function()
                    if Config.InDevelopment then
                        print(('[forge-garage][persistent] enter garage=%s'):format(k))
                    end
                    TriggerServerEvent('forge_garage:server:enterPersistentZone', k)
                end,
                onExit = function()
                    if Config.InDevelopment then
                        print(('[forge-garage][persistent] exit garage=%s'):format(k))
                    end
                    TriggerServerEvent('forge_garage:server:exitPersistentZone', k)
                end
            })
            registered = registered + 1
            if Config.InDevelopment then
                print(('[forge-garage][persistent] zone garage=%s coords=%.2f,%.2f,%.2f radius=%.1f'):format(
                    k, anchor.x, anchor.y, anchor.z, streamingRadius
                ))
            end
        elseif v and v.persist then
            print(('[forge-garage][persistent] missing zone anchor garage=%s'):format(k))
        end
    end

    if Config.InDevelopment then
        print(('[forge-garage][persistent] setup complete registered=%d configured=%d'):format(
            registered, persistentConfigured
        ))
    end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(2000)
    setupPersistentGarages()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    Wait(2000)
    setupPersistentGarages()
end)

-- Export setupPersistentGarages so it can be called from client/zone.lua refresh
exports('setupPersistentGarages', setupPersistentGarages)

local function registerStoredPersistentVehicle(plate, netId, veh)
    if veh and DoesEntityExist(veh) then
        Entity(veh).state:set('pr_carkeys_skipRevPed', true, true)
    end
    spawnedVehs[netId] = veh
    spawnedPlates[plate] = veh
    local key = normalizePlate(plate)
    if key and key ~= plate then
        spawnedPlates[key] = veh
    end
    setPersistentDetached(plate, false)
    if pr_lib and pr_lib.cache then
        pr_lib.cache.set('persistent:veh:' .. plate, veh)
        if key then
            pr_lib.cache.set('persistent:veh:' .. key, veh)
        end
    end
end
exports('registerStoredPersistentVehicle', registerStoredPersistentVehicle)

function getPersistentVehicleEntity(plate)
    local key = normalizePlate(plate)
    local veh = spawnedPlates[plate]
    if veh and DoesEntityExist(veh) then
        return veh
    end
    if key then
        veh = spawnedPlates[key]
        if veh and DoesEntityExist(veh) then
            return veh
        end
    end
    if pr_lib and pr_lib.cache then
        local cachedVeh = pr_lib.cache.get('persistent:veh:' .. plate)
        if cachedVeh and DoesEntityExist(cachedVeh) then
            return cachedVeh
        end
        if key then
            cachedVeh = pr_lib.cache.get('persistent:veh:' .. key)
            if cachedVeh and DoesEntityExist(cachedVeh) then
                return cachedVeh
            end
        end
    end
    if vehFunc and vehFunc.govbp then
        local poolVeh = vehFunc.govbp(plate)
        if poolVeh and DoesEntityExist(poolVeh) then
            return poolVeh
        end
    end
    if key then
        local vehicles = GetGamePool('CVehicle')
        for i = 1, #vehicles do
            local poolVeh = vehicles[i]
            if DoesEntityExist(poolVeh) and normalizePlate(GetVehicleNumberPlateText(poolVeh)) == key then
                return poolVeh
            end
        end
    end
    return nil
end
exports('getPersistentVehicleEntity', getPersistentVehicleEntity)

local function unregisterStoredPersistentVehicle(plate)
    local vehKeys = tableKeys(spawnedVehs)
    for i = 1, #vehKeys do
        local netId = vehKeys[i]
        local veh = spawnedVehs[netId]
        if spawnedPlates[plate] == veh then
            spawnedVehs[netId] = nil
            break
        end
    end
    spawnedPlates[plate] = nil
    local key = normalizePlate(plate)
    if key then
        spawnedPlates[key] = nil
    end
    setPersistentUnlocked(plate, false)
    if pr_lib and pr_lib.cache then
        pr_lib.cache.clear('persistent:veh:' .. plate)
        if key then
            pr_lib.cache.clear('persistent:veh:' .. key)
        end
    end
end
exports('unregisterStoredPersistentVehicle', unregisterStoredPersistentVehicle)

RegisterNetEvent('forge_garage:client:spawnPersistent', function(garageName, vehicles)
    local spawnsList = {}
    
    -- Map of plates that should be active in this garage according to DB
    local activePlates = {}
    for i = 1, #vehicles do
        activePlates[vehicles[i].plate] = true
        local key = normalizePlate(vehicles[i].plate)
        if key then
            activePlates[key] = true
        end
    end

    -- Clean up vehicles that are no longer in the DB for this garage
    local plateKeys = tableKeys(spawnedPlates)
    for i = 1, #plateKeys do
        local plate = plateKeys[i]
        local veh = spawnedPlates[plate]
        if veh and DoesEntityExist(veh) then
            local state = Entity(veh).state
            if isRevvingVehicle(plate, veh, NetworkGetNetworkIdFromEntity(veh)) then
                goto skipCleanup
            end
            if state.garageName == garageName and not activePlates[plate] and not activePlates[normalizePlate(plate)] then
                DeleteEntity(veh)
                spawnedPlates[plate] = nil
                local key = normalizePlate(plate)
                if key then
                    spawnedPlates[key] = nil
                end
                setPersistentUnlocked(plate, false)
                if pr_lib and pr_lib.cache then
                    pr_lib.cache.clear('persistent:veh:' .. plate)
                    if key then
                        pr_lib.cache.clear('persistent:veh:' .. key)
                    end
                end
            end
            ::skipCleanup::
        else
            spawnedPlates[plate] = nil
            local key = normalizePlate(plate)
            if key then
                spawnedPlates[key] = nil
            end
            setPersistentUnlocked(plate, false)
        end
    end

    for i = 1, #vehicles do
        local data = vehicles[i]
        if spawningPlates[data.plate] or detachedPersistent[normalizePlate(data.plate)] then
            goto continue
        end
        if isRevvingVehicle(data.plate, nil, nil) then
            goto continue
        end
        
        -- Check if vehicle is already spawned/cached anywhere
        local existingVeh = getPersistentVehicleEntity(data.plate)
        if existingVeh and DoesEntityExist(existingVeh) then
            if isRevvingVehicle(data.plate, existingVeh, NetworkGetNetworkIdFromEntity(existingVeh)) then
                goto continue
            end
            enforceVehiclePlate(existingVeh, data.plate)
            Entity(existingVeh).state:set('plate', data.plate, true)
            Entity(existingVeh).state:set('pr_carkeys_skipRevPed', true, true)
            -- Map it in local arrays and register in shared cache
            spawnedPlates[data.plate] = existingVeh
            local key = normalizePlate(data.plate)
            if key then
                spawnedPlates[key] = existingVeh
            end
            local netId = NetworkGetNetworkIdFromEntity(existingVeh)
            if netId and netId ~= 0 and netId ~= 65533 then
                spawnedVehs[netId] = existingVeh
                spawnsList[#spawnsList + 1] = { plate = data.plate, netId = netId }
            end
            if pr_lib and pr_lib.cache then
                pr_lib.cache.set('persistent:veh:' .. data.plate, existingVeh)
                if key then
                    pr_lib.cache.set('persistent:veh:' .. key, existingVeh)
                end
            end
            goto continue
        end

        local coords = json.decode(data.parking_coords)
        if coords then
            spawningPlates[data.plate] = true
            local model = type(data.vehicle) == 'table' and data.vehicle.model or data.vehicle
            if not model then
                local decodedMods = json.decode(data.mods)
                model = decodedMods and decodedMods.model
            end
            if type(model) == 'string' then
                model = joaat(model)
            end

            if model then
                RequestModel(model)
                local timer = 0
                while not HasModelLoaded(model) and timer < 100 do
                    Wait(10)
                    timer = timer + 1
                end

                if HasModelLoaded(model) then
                    local veh = CreateVehicle(model, coords.x, coords.y, coords.z + 0.5, coords.h, true, false)
                    
                    local spawnTimer = 0
                    while not DoesEntityExist(veh) and spawnTimer < 100 do
                        Wait(10)
                        spawnTimer = spawnTimer + 1
                    end

                    if DoesEntityExist(veh) then
                        local mods = type(data.mods) == 'table' and data.mods or json.decode(data.mods)
                        if mods then
                            pcall(function()
                                GarageBridge.setVehicleProperties(veh, mods)
                            end)
                        end
                        enforceVehiclePlate(veh, data.plate)

                        if data.fuel then
                            SetVehicleFuelLevel(veh, tonumber(data.fuel) + 0.0)
                        end

                        if data.engine then
                            SetVehicleEngineHealth(veh, tonumber(data.engine) + 0.0)
                        end
                        if data.body then
                            SetVehicleBodyHealth(veh, tonumber(data.body) + 0.0)
                        end

                        local deformation = type(data.deformation) == 'table' and data.deformation or json.decode(data.deformation or '{}')
                        if deformation then
                            pcall(function()
                                local Deformation = GarageBridge.loadModule('modules.deformation')
                                Deformation.set(veh, deformation)
                            end)
                        end

                        settlePersistentVehicle(veh, coords)

                        SetVehicleDoorsLocked(veh, 2) -- Locked
                        Entity(veh).state:set("doorslockstate", 2, true)
                        FreezeEntityPosition(veh, true) -- Frozen
                        SetVehicleEngineOn(veh, false, true, true)
                        SetVehicleHandbrake(veh, true)
                        SetEntityAsMissionEntity(veh, true, true)

                        local state = Entity(veh).state
                        state:set('isPersistent', true, true)
                        state:set('plate', data.plate, true)
                        state:set('garageName', garageName, true)
                        state:set('pr_carkeys_skipRevPed', true, true)

                        -- Ensure the entity is fully networked and has a valid netId
                        local netId = 0
                        local netTimer = 0
                        while (netId == 0 or netId == 65533) and netTimer < 150 do
                            Wait(10)
                            if NetworkGetEntityIsNetworked(veh) then
                                netId = NetworkGetNetworkIdFromEntity(veh)
                            end
                            netTimer = netTimer + 1
                        end

                        if netId ~= 0 and netId ~= 65533 then
                            SetNetworkIdExistsOnAllMachines(netId, true)
                            SetNetworkIdCanMigrate(netId, true)

                            spawnedVehs[netId] = veh
                            spawnedPlates[data.plate] = veh
                            local key = normalizePlate(data.plate)
                            if key then
                                spawnedPlates[key] = veh
                            end
                            if pr_lib and pr_lib.cache then
                                pr_lib.cache.set('persistent:veh:' .. data.plate, veh)
                                if key then
                                    pr_lib.cache.set('persistent:veh:' .. key, veh)
                                end
                            end
                            spawnsList[#spawnsList + 1] = { plate = data.plate, netId = netId }
                        else
                            DeleteEntity(veh)
                        end
                    end
                end
                SetModelAsNoLongerNeeded(model)
            end
            spawningPlates[data.plate] = nil
        end

        ::continue::
    end

    if #spawnsList > 0 then
        TriggerServerEvent('forge_garage:server:confirmPersistentSpawns', garageName, spawnsList)
    end
end)

RegisterNetEvent('forge_garage:client:despawnPersistent', function(netId)
    local veh = spawnedVehs[netId]
    if veh and DoesEntityExist(veh) then
        local plate = Entity(veh).state.plate
        if plate then
            spawnedPlates[plate] = nil
            setPersistentUnlocked(plate, false)
            if pr_lib and pr_lib.cache then
                pr_lib.cache.clear('persistent:veh:' .. plate)
            end
        end
        DeleteEntity(veh)
    end
    spawnedVehs[netId] = nil
end)

-- Thread to detect when player enters a persistent vehicle
CreateThread(function()
    while true do
        local sleep = 500
        local ped = GarageBridge.cache.ped
        local vehicle = GetVehiclePedIsIn(ped, false)
        
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            sleep = 100
            local state = Entity(vehicle).state
            if state.isPersistent then
                if isRevvingVehicle(state.plate, vehicle, NetworkGetNetworkIdFromEntity(vehicle)) then
                    Wait(sleep)
                    goto continue
                end
                local plate = state.plate
                local garageName = state.garageName
                
                if plate and garageName then
                    local hasKey = hasDriverKeyForPlate(plate)
                    if hasKey then
                        if isPersistentUnlocked(plate) then
                            unlockPersistentVehicle(vehicle)
                        end

                        if IsControlPressed(0, 71) or IsControlPressed(0, 72) or GetEntitySpeed(vehicle) > 0.4 then
                            requestPersistentWithdraw(garageName, plate, vehicle)
                        end
                    else
                        TaskLeaveAnyVehicle(ped, true, 0)
                        utils.notify("Você não tem as chaves deste veículo!", "error")
                    end
                end
            end
        end
        ::continue::
        Wait(sleep)
    end
end)

-- Thread to monitor lock status of persistent vehicles from outside
CreateThread(function()
    while true do
        local sleep = 500
        local ped = GarageBridge.cache.ped
        local pos = GetEntityCoords(ped)
        
        local closestVeh = 0
        local closestDist = 999.0
        local closestPlate = nil
        
        local plateKeys = tableKeys(spawnedPlates)
        for i = 1, #plateKeys do
            local plate = plateKeys[i]
            local veh = spawnedPlates[plate]
            if veh and DoesEntityExist(veh) then
                local vehPos = GetEntityCoords(veh)
                local dist = #(pos - vehPos)
                if dist < 10.0 and dist < closestDist then
                    closestVeh = veh
                    closestDist = dist
                    closestPlate = plate
                end
            end
        end
        
        if closestVeh ~= 0 then
            sleep = 100
            local lockStatus = GetVehicleDoorLockStatus(closestVeh)
            
            -- If the vehicle is unlocked (status is 1 or 0)
            if lockStatus == 1 or lockStatus == 0 then
                local state = Entity(closestVeh).state
                if isRevvingVehicle(closestPlate, closestVeh, NetworkGetNetworkIdFromEntity(closestVeh)) then
                    Wait(sleep)
                    goto continue
                end
                local garageName = state.garageName
                
                if garageName then
                    setPersistentUnlocked(closestPlate, true)
                    unlockPersistentVehicle(closestVeh)
                end
            end
        end
        ::continue::
        Wait(sleep)
    end
end)

RegisterNetEvent('forge_garage:client:releasePersistentVehicle', function(plate)
    local veh = getPersistentVehicleEntity(plate)
    if veh and DoesEntityExist(veh) then
        FreezeEntityPosition(veh, false)
        SetVehicleDoorsLocked(veh, 1) -- Unlocked
        SetVehicleEngineOn(veh, false, true, true)
        SetVehicleHandbrake(veh, false)
        
        local state = Entity(veh).state
        state:set('isPersistent', nil, true)
        state:set('garageName', nil, true)
        state:set('pr_carkeys_skipRevPed', nil, true)
        
        local netId = NetworkGetNetworkIdFromEntity(veh)
        spawnedVehs[netId] = nil
        spawnedPlates[plate] = nil
        withdrawingPlates[normalizePlate(plate)] = nil
        setPersistentUnlocked(plate, false)
        if pr_lib and pr_lib.cache then
            pr_lib.cache.clear('persistent:veh:' .. plate)
        end
    end
end)

RegisterNetEvent('forge_garage:client:registerExistingPersistentVehicle', function(plate, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and DoesEntityExist(veh) then
        local state = Entity(veh).state
        state:set('pr_carkeys_skipRevPed', true, true)
        spawnedVehs[netId] = veh
        spawnedPlates[plate] = veh
        if pr_lib and pr_lib.cache then
            pr_lib.cache.set('persistent:veh:' .. plate, veh)
        end
    end
end)
