GarageBridge = GarageBridge or {}

local bridge = GarageBridge
local isServer = IsDuplicityVersion()
local resourceName = GetCurrentResourceName()
local loadedModules = {}

function bridge.loadModule(path)
    local modulePath = tostring(path or ""):gsub("%.", "/")
    if not modulePath:match("%.lua$") then
        modulePath = modulePath .. ".lua"
    end

    if loadedModules[modulePath] ~= nil then
        return loadedModules[modulePath]
    end

    local source = LoadResourceFile(resourceName, modulePath)
    if not source then
        error(("module '%s' file not found (%s)"):format(tostring(path), modulePath), 2)
    end

    local chunk, loadError = load(source, ("@@%s/%s"):format(resourceName, modulePath), "t", _ENV)
    if not chunk then
        error(("module '%s' failed to compile: %s"):format(tostring(path), tostring(loadError)), 2)
    end

    local result = chunk()
    if result == nil then result = true end
    loadedModules[modulePath] = result
    return result
end
local function safeCall(label, callback, ...)
    if type(callback) ~= "function" then return end

    local ok, result = pcall(callback, ...)
    if not ok then
        print(("[forge-garage][bridge] %s: %s"):format(label, tostring(result)))
        return nil
    end

    return result
end

local function normalizeJsonPath(path)
    if type(path) ~= "string" or path == "" then return nil end

    local normalized = path:gsub("\\", "/")
    if not normalized:find("/", 1, true) then
        normalized = normalized:gsub("%.", "/")
    end
    if not normalized:match("%.json$") then
        normalized = normalized .. ".json"
    end
    return normalized
end

function bridge.loadJson(path, optional)
    local normalized = normalizeJsonPath(path)
    local content = normalized and LoadResourceFile(resourceName, normalized)

    if not content then
        if optional then return nil end
        error(("JSON não encontrado: %s"):format(tostring(normalized or path)), 2)
    end

    local ok, decoded = pcall(json.decode, content)
    if not ok then
        if optional then return nil end
        error(("JSON inválido em %s: %s"):format(normalized, tostring(decoded)), 2)
    end

    return decoded
end

local function normalizeLocaleName(value)
    value = tostring(value or ""):gsub("_", "-"):lower()
    if value == "" then return "pt-br" end
    if value == "ptbr" then return "pt-br" end
    if value == "enus" then return "en-us" end
    return value
end

local configuredLocale = GetConvar("pr_bridge:locale", "")
if configuredLocale == "" or configuredLocale == "en-us" then
    configuredLocale = GetConvar("locale", "pt-br")
end
configuredLocale = normalizeLocaleName(configuredLocale)

local localeCandidates = { configuredLocale }
local languageOnly = configuredLocale:match("^([a-z]+)%-")
if languageOnly then localeCandidates[#localeCandidates + 1] = languageOnly end
localeCandidates[#localeCandidates + 1] = "pt-br"
localeCandidates[#localeCandidates + 1] = "en"

local translations = {}
for index = 1, #localeCandidates do
    local candidate = localeCandidates[index]
    local content = LoadResourceFile(resourceName, ("locales/%s.json"):format(candidate))
    if content then
        local ok, decoded = pcall(json.decode, content)
        if ok and type(decoded) == "table" then
            translations = decoded
            break
        end
    end
end

local function getTranslation(key)
    local value = translations
    for part in tostring(key):gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return type(value) == "string" and value or nil
end

function bridge.locale(key, ...)
    local phrase = getTranslation(key) or tostring(key)
    if select("#", ...) == 0 then return phrase end

    local ok, formatted = pcall(string.format, phrase, ...)
    return ok and formatted or phrase
end

bridge.callback = {}

function bridge.callback.register(name, callback)
    return pr_lib.callback.register(name, callback)
end

function bridge.callback.await(name, targetOrTimeout, ...)
    if isServer then
        local target = tonumber(targetOrTimeout)
        if not target or target <= 0 then return nil, "invalid_target" end
        return pr_lib.callback.awaitClient(target, name, false, ...)
    end

    return pr_lib.callback.await(name, targetOrTimeout, ...)
end

setmetatable(bridge.callback, {
    __call = function(_, name, timeout, callback, ...)
        if isServer then
            local target = tonumber(timeout)
            return pr_lib.callback.triggerClient(target, name, callback, ...)
        end

        return pr_lib.callback.trigger(name, callback, ...)
    end
})

bridge.addCommand = pr_lib.addCommand
bridge.table = {
    contains = function(source, value)
        return pr_lib.table.contains(source, value)
    end
}

bridge.math = {}

function bridge.math.groupdigits(value, separator)
    separator = separator or "."
    local number = tonumber(value) or 0
    local sign = number < 0 and "-" or ""
    local integer, decimal = tostring(math.abs(number)):match("^(%d+)(.*)$")
    integer = integer or "0"

    local reversed = integer:reverse():gsub("(%d%d%d)", "%1" .. separator)
    local grouped = reversed:reverse():gsub("^" .. separator, "")
    return sign .. grouped .. (decimal or "")
end

bridge.string = {}

function bridge.string.random(pattern)
    pattern = tostring(pattern or "")
    local result = {}

    for index = 1, #pattern do
        local token = pattern:sub(index, index)
        if token == "1" then
            result[index] = tostring(math.random(0, 9))
        elseif token == "A" then
            result[index] = string.char(math.random(65, 90))
        elseif token == "a" then
            result[index] = string.char(math.random(97, 122))
        else
            result[index] = token
        end
    end

    return table.concat(result)
end

bridge.print = {
    info = function(message)
        print(("[forge-garage] %s"):format(tostring(message)))
    end
}

if isServer then
    function bridge.notify(target, data)
        TriggerClientEvent("forge_garage:client:bridgeNotify", target, data)
        return true
    end

    function bridge.spawnVehicle(model, coords, properties)
        if type(coords) ~= "vector3" and type(coords) ~= "vector4" and type(coords) ~= "table" then
            return false, false, "invalid_coords"
        end

        local modelHash = type(model) == "number" and model or joaat(model)
        local vehicleData = exports.qbx_core:GetVehiclesByHash(modelHash)
        local vehicleType = vehicleData and vehicleData.type

        if not vehicleType then
            local temporary = CreateVehicle(modelHash, 0.0, 0.0, -200.0, 0.0, true, true)
            local expires = GetGameTimer() + 3000
            while not DoesEntityExist(temporary) and GetGameTimer() < expires do Wait(0) end

            if DoesEntityExist(temporary) then
                vehicleType = GetVehicleType(temporary)
                DeleteEntity(temporary)
            end
        end

        if not vehicleType or vehicleType == "" then
            return false, false, "unknown_vehicle_type"
        end

        local vehicle = CreateVehicleServerSetter(
            modelHash,
            vehicleType,
            coords.x + 0.0,
            coords.y + 0.0,
            coords.z + 0.0,
            (coords.w or coords.h or 0.0) + 0.0
        )

        local expires = GetGameTimer() + 5000
        while not DoesEntityExist(vehicle) and GetGameTimer() < expires do Wait(0) end
        if not DoesEntityExist(vehicle) then
            return false, false, "spawn_timeout"
        end

        SetEntityOrphanMode(vehicle, 2)
        pcall(function()
            exports.qbx_core:EnablePersistence(vehicle)
        end)

        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if type(properties) == "table" then
            pr_lib.vehicleProperties.set(vehicle, properties)
        end

        return netId, vehicle
    end
else
    RegisterNetEvent("forge_garage:client:bridgeNotify", function(data)
        pr_lib.Notify(data)
    end)

    function bridge.notify(data)
        return pr_lib.Notify(data)
    end

    function bridge.showTextUI(text, options)
        options = options or {}

        TriggerEvent("pr_bridge:ui:claim", resourceName)
        TriggerEvent("pr_bridge:ui:send", "textui:show", {
            text = tostring(text or ""),
            position = options.position or "right-center",
            icon = options.icon,
            iconColor = options.iconColor,
            style = options.style,
            debug = options.debug == true,
            __resource = resourceName,
        })

        return true
    end

    function bridge.hideTextUI()
        TriggerEvent("pr_bridge:ui:claim", resourceName)
        TriggerEvent("pr_bridge:ui:send", "textui:hide", {
            __resource = resourceName,
        })

        return true
    end

    function bridge.requestModel(model, timeout)
        return pr_lib.fivem.streaming.requestModel(model, timeout or 150000)
    end

    function bridge.getVehicleProperties(vehicle)
        return pr_lib.fivem.getVehicleProperties(vehicle)
    end

    function bridge.setVehicleProperties(vehicle, properties)
        return pr_lib.fivem.setVehicleProperties(vehicle, properties)
    end

    function bridge.getClosestVehicle(coords, radius)
        radius = tonumber(radius) or 2.0
        local vehicles = GetGamePool("CVehicle")
        local closest, closestDistance

        for index = 1, #vehicles do
            local vehicle = vehicles[index]
            if DoesEntityExist(vehicle) then
                local distance = #(GetEntityCoords(vehicle) - coords)
                if distance <= radius and (not closestDistance or distance < closestDistance) then
                    closest = vehicle
                    closestDistance = distance
                end
            end
        end

        return closest
    end

    function bridge.getClosestPlayer(coords, radius)
        radius = tonumber(radius) or 3.0
        local ownPlayer = PlayerId()
        local closest, closestDistance
        local players = GetActivePlayers()

        for index = 1, #players do
            local player = players[index]
            if player ~= ownPlayer then
                local ped = GetPlayerPed(player)
                if DoesEntityExist(ped) then
                    local distance = #(GetEntityCoords(ped) - coords)
                    if distance <= radius and (not closestDistance or distance < closestDistance) then
                        closest = player
                        closestDistance = distance
                    end
                end
            end
        end

        return closest
    end

    bridge.cache = {
        ped = PlayerPedId(),
        vehicle = false,
        seat = false,
    }

    local cacheListeners = {}

    function bridge.onCache(key, callback)
        if type(key) ~= "string" or type(callback) ~= "function" then return false end
        cacheListeners[key] = cacheListeners[key] or {}
        cacheListeners[key][#cacheListeners[key] + 1] = callback
        return true
    end

    local function findPedSeat(ped, vehicle)
        if not vehicle or vehicle == 0 then return false end
        if GetPedInVehicleSeat(vehicle, -1) == ped then return -1 end

        local passengers = GetVehicleMaxNumberOfPassengers(vehicle)
        for seat = 0, passengers - 1 do
            if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
        end

        return false
    end

    local function updateCacheValue(key, value)
        local oldValue = bridge.cache[key]
        if oldValue == value then return end

        bridge.cache[key] = value
        local listeners = cacheListeners[key]
        if not listeners then return end

        for index = 1, #listeners do
            safeCall(("cache.%s"):format(key), listeners[index], value, oldValue)
        end
    end

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle == 0 then vehicle = false end

            updateCacheValue("ped", ped)
            updateCacheValue("vehicle", vehicle)
            updateCacheValue("seat", findPedSeat(ped, vehicle))
            Wait(100)
        end
    end)

    bridge.zones = {}
    local zones = {}
    local nextZoneId = 0
    local zoneThreadRunning = false

    local function pointInPolygon(coords, points)
        local inside = false
        local previous = #points

        for index = 1, #points do
            local currentPoint = points[index]
            local previousPoint = points[previous]
            local crosses = ((currentPoint.y > coords.y) ~= (previousPoint.y > coords.y))
                and (coords.x < (previousPoint.x - currentPoint.x) * (coords.y - currentPoint.y)
                    / ((previousPoint.y - currentPoint.y) + 0.0) + currentPoint.x)

            if crosses then inside = not inside end
            previous = index
        end

        return inside
    end

    local function contains(zone, coords)
        if zone.kind == "sphere" then
            return #(coords - zone.coords) <= zone.radius
        end

        if #zone.points < 3 then return false end
        if math.abs(coords.z - zone.centerZ) > zone.halfThickness then return false end
        return pointInPolygon(coords, zone.points)
    end

    local function startZoneThread()
        if zoneThreadRunning then return end
        zoneThreadRunning = true

        CreateThread(function()
            while next(zones) do
                local coords = GetEntityCoords(PlayerPedId())
                local hasInsideZone = false

                for _, zone in pairs(zones) do
                    if not zone.removed then
                        local isInside = contains(zone, coords)

                        if isInside ~= zone.isInside then
                            zone.isInside = isInside
                            if isInside then
                                safeCall("zone.onEnter", zone.onEnter, zone)
                            else
                                safeCall("zone.onExit", zone.onExit, zone)
                            end
                        end

                        if isInside then
                            hasInsideZone = true
                            safeCall("zone.inside", zone.inside, zone)
                        end
                    end
                end

                Wait(hasInsideZone and 0 or 200)
            end

            zoneThreadRunning = false
        end)
    end

    local function createZone(kind, options)
        options = options or {}
        nextZoneId = nextZoneId + 1

        local zone = {
            id = nextZoneId,
            kind = kind,
            coords = options.coords,
            radius = tonumber(options.radius) or 1.0,
            points = options.points or {},
            thickness = tonumber(options.thickness) or 4.0,
            inside = options.inside,
            onEnter = options.onEnter,
            onExit = options.onExit,
            isInside = false,
            removed = false,
        }

        if kind == "poly" then
            local totalZ = 0.0
            for index = 1, #zone.points do
                totalZ = totalZ + (zone.points[index].z or 0.0)
            end
            zone.centerZ = #zone.points > 0 and totalZ / #zone.points or 0.0
            zone.halfThickness = zone.thickness / 2.0
        end

        function zone:remove()
            if self.removed then return end
            self.removed = true
            zones[self.id] = nil
            if self.isInside then
                self.isInside = false
                safeCall("zone.onExit", self.onExit, self)
            end
        end

        zones[zone.id] = zone
        startZoneThread()
        return zone
    end

    function bridge.zones.sphere(options)
        return createZone("sphere", options)
    end

    function bridge.zones.poly(options)
        return createZone("poly", options)
    end

    local progressBusy = false

    local function loadAnimDict(dictionary, timeout)
        if not dictionary or dictionary == "" then return false end
        if HasAnimDictLoaded(dictionary) then return true end

        RequestAnimDict(dictionary)
        local expires = GetGameTimer() + (timeout or 5000)
        while not HasAnimDictLoaded(dictionary) and GetGameTimer() < expires do Wait(0) end
        return HasAnimDictLoaded(dictionary)
    end

    local function createProgressProps(propData)
        if type(propData) ~= "table" then return {} end
        if propData.model then propData = { propData } end

        local entities = {}
        local ped = bridge.cache.ped

        for index = 1, #propData do
            local data = propData[index]
            local loaded, model = bridge.requestModel(data.model, 5000)
            if loaded and model then
                local coords = GetEntityCoords(ped)
                local object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
                local position = data.pos or data.coords or {}
                local rotation = data.rot or data.rotation or {}
                AttachEntityToEntity(
                    object,
                    ped,
                    GetPedBoneIndex(ped, data.bone or 60309),
                    position.x or 0.0, position.y or 0.0, position.z or 0.0,
                    rotation.x or 0.0, rotation.y or 0.0, rotation.z or 0.0,
                    true, true, false, true, 1, true
                )
                entities[#entities + 1] = object
                SetModelAsNoLongerNeeded(model)
            end
        end

        return entities
    end

    local function runProgress(options)
        options = options or {}
        if progressBusy then return false end
        progressBusy = true

        local duration = math.max(tonumber(options.duration) or 0, 0)
        local ped = bridge.cache.ped
        local animation = options.anim
        local props = createProgressProps(options.prop)

        if animation and loadAnimDict(animation.dict, 5000) then
            TaskPlayAnim(
                ped,
                animation.dict,
                animation.clip or animation.anim or "",
                3.0,
                3.0,
                duration,
                animation.flags or 49,
                0.0,
                false,
                false,
                false
            )
        end

        if options.label and options.label ~= "" then
            pr_lib.Notify({
                description = options.label,
                type = "info",
                duration = duration,
                showDuration = true,
            })
        end

        local cancelled = false
        local expires = GetGameTimer() + duration

        while GetGameTimer() < expires do
            local disable = options.disable or {}
            if disable.move then
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
            end
            if disable.car then
                DisableControlAction(0, 59, true)
                DisableControlAction(0, 60, true)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
            end
            if disable.combat then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
            end
            if disable.mouse then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
            end
            if disable.sprint then
                DisableControlAction(0, 21, true)
            end

            if options.canCancel and IsControlJustPressed(0, 202) then
                cancelled = true
                break
            end

            if options.useWhileDead == false and IsEntityDead(ped) then
                cancelled = true
                break
            end

            Wait(0)
        end

        if animation then
            StopAnimTask(ped, animation.dict, animation.clip or animation.anim or "", 1.0)
            RemoveAnimDict(animation.dict)
        end

        for index = 1, #props do
            if DoesEntityExist(props[index]) then DeleteEntity(props[index]) end
        end

        progressBusy = false
        return not cancelled
    end

    bridge.progressBar = runProgress
    bridge.progressCircle = runProgress
end

return bridge
