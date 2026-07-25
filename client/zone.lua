gzf = {}

local CreatedZone = {}
local ped = nil
local stui = false
local garageTransitionBusy = false
local zoneInteractionBusy = false
local activeGarageIpl = nil
local function tableKeys(source)
    local keys = {}
    if type(source) ~= "table" then return keys end

    local lastKey = nil
    while true do
        local ok, key = pcall(next, source, lastKey)
        if not ok or key == nil then break end
        keys[#keys + 1] = key
        lastKey = key
    end

    return keys
end

local function playGarageDoorSound()
    RequestScriptAudioBank("GTAO_Script_Doors_Faded_Screen_Sounds", false)
    PlaySoundFrontend(-1, "Garage_Door_Open", "GTAO_Script_Doors_Faded_Screen_Sounds", true)
end

local function runGarageTransition(label, action)
    if garageTransitionBusy then return false end

    garageTransitionBusy = true
    stui = false
    utils.drawtext('hide')
    playGarageDoorSound()

    DoScreenFadeOut(600)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    if label then
        BeginTextCommandBusyspinnerOn("STRING")
        AddTextComponentSubstringPlayerName(label)
        EndTextCommandBusyspinnerOn(4)
    end

    Wait(450)

    local ok, err = pcall(action)
    if not ok and err then
        print(("[forge-garage] garage transition error: %s"):format(err))
    end

    Wait(350)
    BusyspinnerOff()

    DoScreenFadeIn(700)
    while not IsScreenFadedIn() do
        Wait(0)
    end

    garageTransitionBusy = false
    return ok
end

local function runZoneInteraction(action)
    if zoneInteractionBusy then return false end

    zoneInteractionBusy = true
    CreateThread(function()
        local ok, err = pcall(action)
        if not ok and err then
            print(("[forge-garage] zone interaction error: %s"):format(err))
        end
        zoneInteractionBusy = false
    end)

    return true
end

local function normalizeIplList(ipl)
    local list = {}
    local added = {}
    local selectedExclusiveGroups = {}

    local function addIpl(iplName)
        if not iplName or added[iplName] then return end

        for groupIndex = 1, #(Config.ExclusiveGarageIplGroups or {}) do
            local group = Config.ExclusiveGarageIplGroups[groupIndex]
            for memberIndex = 1, #group do
                if group[memberIndex] == iplName then
                    if selectedExclusiveGroups[groupIndex] then
                        return
                    end

                    selectedExclusiveGroups[groupIndex] = iplName
                    break
                end
            end
        end

        added[iplName] = true
        list[#list + 1] = iplName
    end

    if type(ipl) == "table" then
        for i = 1, #ipl do
            addIpl(ipl[i])
        end
    elseif ipl then
        addIpl(ipl)
    end

    return list
end

local function waitForIplState(iplNames, active)
    local deadline = GetGameTimer() + 5000

    repeat
        local ready = true
        for i = 1, #iplNames do
            if IsIplActive(iplNames[i]) ~= active then
                ready = false
                break
            end
        end

        if ready then return true end
        Wait(0)
    until GetGameTimer() >= deadline

    return false
end

local function setGarageIplDefaults(iplName, active)
    local defaults = Config.GarageIplDefaults and Config.GarageIplDefaults[iplName]
    if not defaults or not defaults.interiorId then return end

    if active then
        PinInteriorInMemory(defaults.interiorId)
        LoadInterior(defaults.interiorId)
    end

    for i = 1, #(defaults.entitySets or {}) do
        local entitySet = defaults.entitySets[i]
        if active then
            if not IsInteriorEntitySetActive(defaults.interiorId, entitySet) then
                ActivateInteriorEntitySet(defaults.interiorId, entitySet)
            end
        elseif IsInteriorEntitySetActive(defaults.interiorId, entitySet) then
            DeactivateInteriorEntitySet(defaults.interiorId, entitySet)
        end
    end

    RefreshInterior(defaults.interiorId)
    if not active then
        UnpinInterior(defaults.interiorId)
    end
end

local function collectKnownGarageIpls()
    local known = {}

    for i = 1, #(Config.GarageIplCleanup or {}) do
        known[Config.GarageIplCleanup[i]] = true
    end

    for i = 1, #(Config.GarageIpls or {}) do
        local model = Config.GarageIpls[i] and Config.GarageIpls[i].ipl
        local list = normalizeIplList(model)
        for j = 1, #list do
            known[list[j]] = true
        end
    end

    local garageKeys = tableKeys(GarageZone)
    for i = 1, #garageKeys do
        local garage = GarageZone[garageKeys[i]]
        local model = garage and garage.ipl and garage.ipl.model
        local list = normalizeIplList(model)
        for j = 1, #list do
            known[list[j]] = true
        end
    end

    return known
end

local function unloadKnownGarageIpls(exceptIpls)
    local known = collectKnownGarageIpls()
    local removed = {}

    for iplName, _ in pairs(known) do
        if not exceptIpls or not exceptIpls[iplName] then
            setGarageIplDefaults(iplName, false)
            RemoveIpl(iplName)
            removed[#removed + 1] = iplName
        end
    end

    if #removed > 0 and not waitForIplState(removed, false) then
        print("[forge-garage] timeout while disabling garage IPLs")
    end
end

local function unloadActiveGarageIpl()
    unloadKnownGarageIpls()
    activeGarageIpl = nil
end

local function waitForGarageInteriors(iplNames)
    local interiorIds = {}

    for i = 1, #iplNames do
        local defaults = Config.GarageIplDefaults and Config.GarageIplDefaults[iplNames[i]]
        if defaults and defaults.interiorId then
            interiorIds[#interiorIds + 1] = defaults.interiorId
        end
    end

    if #interiorIds == 0 then
        Wait(500)
        return true
    end

    local deadline = GetGameTimer() + 5000
    repeat
        local ready = true
        for i = 1, #interiorIds do
            if not IsInteriorReady(interiorIds[i]) then
                LoadInterior(interiorIds[i])
                ready = false
            end
        end

        if ready then return true end
        Wait(0)
    until GetGameTimer() >= deadline

    print("[forge-garage] timeout while preparing selected garage interior")
    return false
end

local function loadGarageIpl(ipl)
    local nextIpls = {}
    local list = normalizeIplList(ipl)

    for i = 1, #list do
        nextIpls[list[i]] = true
    end

    unloadKnownGarageIpls(nextIpls)

    for i = 1, #list do
        RequestIpl(list[i])
    end

    for i = 1, #list do
        setGarageIplDefaults(list[i], true)
    end

    waitForGarageInteriors(list)
    activeGarageIpl = ipl
end

function gzf.prepareIpl(ipl)
    if not ipl then return false end
    loadGarageIpl(ipl)
    return true
end

function gzf.unloadIpl()
    unloadActiveGarageIpl()
end

local function accessModeAllows(mode, inVehicle)
    if mode ~= "ped" and mode ~= "vehicle" and mode ~= "both" then
        mode = "both"
    end
    if inVehicle then
        return mode == "both" or mode == "vehicle"
    end

    return mode == "both" or mode == "ped"
end

local function accessModeLabel(mode)
    if mode == "ped" then return "somente a pe" end
    if mode == "vehicle" then return "somente veiculo" end
    return "a pe/veiculo"
end

local function getPointCoords(point)
    return point and (point.coords or point) or nil
end

local function walkPedForward(distance)
    local target = GetOffsetFromEntityInWorldCoords(GarageBridge.cache.ped, 0.0, distance or 2.0, 0.0)
    TaskGoStraightToCoord(GarageBridge.cache.ped, target.x, target.y, target.z, 1.0, 2000, GetEntityHeading(GarageBridge.cache.ped), 0.2)
end

local function rollVehicleForward(vehicle, distance)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleForwardSpeed(vehicle, 2.5)

    CreateThread(function()
        local untilAt = GetGameTimer() + math.floor(((distance or 10.0) / 2.5) * 1000)
        while DoesEntityExist(vehicle) and GetGameTimer() < untilAt do
            SetVehicleForwardSpeed(vehicle, 2.5)
            Wait(500)
        end
    end)
end

local function waitForCollisionAt(coords)
    local deadline = GetGameTimer() + 5000
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    while not HasCollisionLoadedAroundEntity(GarageBridge.cache.ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    return HasCollisionLoadedAroundEntity(GarageBridge.cache.ped)
end

local function teleportPedOrVehicle(coords, moveMode)
    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 50.0, 0)
    SetPedCoordsKeepVehicle(GarageBridge.cache.ped, coords.x, coords.y, coords.z)
    SetEntityHeading(GarageBridge.cache.ped, coords.w or coords.h or 0.0)

    local vehicle = GarageBridge.cache.vehicle or GetVehiclePedIsIn(GarageBridge.cache.ped, false)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetEntityHeading(vehicle, coords.w or coords.h or 0.0)
    end

    if not waitForCollisionAt(coords) then
        print("[forge-garage] timeout while loading collision around the garage teleport")
    end

    NewLoadSceneStop()
    ClearFocus()

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and moveMode == "vehicleRoll10m" then
        rollVehicleForward(vehicle, 10.0)
    elseif (not vehicle or vehicle == 0) and moveMode == "pedWalk2m" then
        walkPedForward(2.0)
    end
end

local function getIplEntries(ipl)
    local entries = {}

    if ipl and type(ipl.entries) == "table" then
        for i = 1, #ipl.entries do
            local entry = ipl.entries[i]
            local coords = getPointCoords(entry)
            if coords then
                entries[#entries + 1] = {
                    label = entry.label or ("Entrada " .. i),
                    coords = coords,
                    mode = entry.mode or (ipl.allowVehicle == false and "ped" or "both")
                }
            end
        end
    end

    if #entries == 0 and ipl and ipl.entry then
        entries[1] = {
            label = "Entrada 1",
            coords = ipl.entry,
            mode = ipl.allowVehicle == false and "ped" or "both"
        }
    end

    return entries
end

local function getIplFloors(ipl)
    local floors = {}

    if ipl and type(ipl.floors) == "table" then
        for i = 1, #ipl.floors do
            local floor = ipl.floors[i]
            local coords = getPointCoords(floor)
            if coords then
                floors[#floors + 1] = {
                    index = i,
                    label = floor.label or ("Andar " .. i),
                    coords = coords,
                    mode = floor.mode or (ipl.allowVehicle == false and "ped" or "both")
                }
            end
        end
    end

    if #floors == 0 and ipl and ipl.exit then
        floors[1] = {
            index = 1,
            label = "Andar 1",
            coords = ipl.exit,
            mode = ipl.allowVehicle == false and "ped" or "both"
        }
    end

    return floors
end

local function filterIplPoints(points, inVehicle)
    local filtered = {}

    for i = 1, #points do
        if accessModeAllows(points[i].mode, inVehicle) then
            filtered[#filtered + 1] = points[i]
        end
    end

    return filtered
end

local function selectIplPoint(title, points)
    if #points == 1 then
        return points[1]
    end

    local options = {}
    for i = 1, #points do
        options[#options + 1] = {
            value = i,
            label = ("%s (%s)"):format(points[i].label or ("Ponto " .. i), accessModeLabel(points[i].mode))
        }
    end

    local input = pr_lib.inputDialog(title, {
        { type = "select", label = "Destino", options = options, required = true }
    })

    if not input or not input[1] then return end
    return points[tonumber(input[1])]
end

local function selectElevatorDestination(title, floors, entries, currentFloorIndex)
    local destinations = {}
    local options = {}

    for i = 1, #floors do
        local floor = floors[i]
        if floor.index ~= currentFloorIndex then
            destinations[#destinations + 1] = { kind = "floor", point = floor }
            options[#options + 1] = {
                value = #destinations,
                label = ("Andar: %s (%s)"):format(floor.label, accessModeLabel(floor.mode))
            }
        end
    end

    for i = 1, #entries do
        local entry = entries[i]
        destinations[#destinations + 1] = { kind = "exit", point = entry }
        options[#options + 1] = {
            value = #destinations,
            label = ("Sair: %s (%s)"):format(entry.label, accessModeLabel(entry.mode))
        }
    end

    if #destinations == 0 then return nil end
    if #destinations == 1 then return destinations[1] end

    local input = pr_lib.inputDialog(title, {
        { type = "select", label = "Destino", options = options, required = true }
    })

    if not input or not input[1] then return nil end
    return destinations[tonumber(input[1])]
end

local function getIplParkingSpots(ipl)
    local spots = {}

    if ipl and type(ipl.parkingSpots) == "table" then
        for i = 1, #ipl.parkingSpots do
            local spot = ipl.parkingSpots[i]
            local coords = spot.coords or spot
            if coords then
                spots[#spots + 1] = {
                    label = spot.label or ("Vaga " .. i),
                    coords = coords,
                    radius = spot.radius or 3.0
                }
            end
        end
    end

    return spots
end

--- Job & Gang Checking
---@param key string
---@param val table
---@return boolean
function gzf.authorize(key, val)
    if not val.impound then
        if val.gang then if not utils.GangCheck({garage = key, gang = val.gang}) then return false end end
        if val.job then if not utils.JobCheck({garage = key, job = val.job}) then return false end end
    end

    return true
end

function gzf.refresh ()
    if not GarageZone or type(GarageZone) ~= "table" then return end

    if activeGarageIpl then
        loadGarageIpl(activeGarageIpl)
    else
        unloadActiveGarageIpl()
    end
    gb.refresh(GarageZone)
    local createdZoneKeys = tableKeys(CreatedZone)
    for i = 1, #createdZoneKeys do
        local k = createdZoneKeys[i]
        local v = CreatedZone[k]
        if v and v.remove then
            v:remove()
        end
    end
    CreatedZone = {}

    local garageKeys = tableKeys(GarageZone)
    for i = 1, #garageKeys do
        local k = garageKeys[i]
        local v = GarageZone[k]
        if v.ipl and v.ipl.enabled then
            local args = {
                garage = k,
                impound = v.impound,
                shared = v.shared,
                type = v.type,
                spawnpoint = v.spawnPoint,
                vehicles = v.vehicles,
                ignoreDist = true
            }

            local entries = getIplEntries(v.ipl)
            for entryIndex = 1, #entries do
                local entry = entries[entryIndex]
                local entryCoords = entry.coords
                CreatedZone[k .. ":ipl_entry:" .. entryIndex] = GarageBridge.zones.sphere({
                    coords = vec3(entryCoords.x, entryCoords.y, entryCoords.z),
                    radius = 2.5,
                    inside = function()
                        if not stui then
                            local dl = GarageBridge.cache.vehicle and ('[E/Buzina] - Entrar %s'):format(entry.label or k) or ('[E] - Entrar %s'):format(entry.label or k)
                            utils.drawtext('show', dl, 'warehouse')
                            stui = true
                        end

                        if (IsControlJustPressed(0, 38) or IsControlJustPressed(0, 86)) then
                            runZoneInteraction(function()
                                local inVehicle = GarageBridge.cache.vehicle and true or false
                                if not accessModeAllows(entry.mode, inVehicle) then
                                    return utils.notify(("Esta entrada aceita %s."):format(accessModeLabel(entry.mode)), "error")
                                end
                                if not gzf.authorize(k, v) then return end
                                local floors = filterIplPoints(getIplFloors(v.ipl), inVehicle)
                                if #floors == 0 then
                                    return utils.notify("Nenhum elevador compativel foi configurado para este tipo de acesso.", "error")
                                end

                                local floor = selectIplPoint("Escolher andar - " .. k, floors)
                                if not floor or not floor.coords then return end

                                runGarageTransition("Entrando na garagem...", function()
                                    loadGarageIpl(v.ipl.model)
                                    TriggerServerEvent("forge_garage:server:setPlayerGarageBucket", v.ipl.bucket or 0)
                                    Wait(100)
                                    teleportPedOrVehicle(floor.coords, inVehicle and "none" or "pedWalk2m")
                                    TriggerServerEvent('forge_garage:server:enterPersistentZone', k)
                                end)
                            end)
                        end
                    end,
                    onExit = function()
                        stui = false
                        utils.drawtext('hide')
                    end
                })
            end

            local floors = getIplFloors(v.ipl)
            for floorIndex = 1, #floors do
                local floor = floors[floorIndex]
                local floorCoords = floor.coords
                CreatedZone[k .. ":ipl_exit:" .. floorIndex] = GarageBridge.zones.sphere({
                    coords = vec3(floorCoords.x, floorCoords.y, floorCoords.z),
                    radius = 2.5,
                    inside = function()
                        if not stui then
                            local dl = GarageBridge.cache.vehicle and ('[E/Buzina] - Elevador %s'):format(floor.label) or ('[E] - Elevador %s'):format(floor.label)
                            utils.drawtext('show', dl, 'warehouse')
                            stui = true
                        end

                        if (IsControlJustPressed(0, 38) or IsControlJustPressed(0, 86)) then
                            runZoneInteraction(function()
                                local inVehicle = GarageBridge.cache.vehicle and true or false
                                if not accessModeAllows(floor.mode, inVehicle) then
                                    return utils.notify(("Este elevador aceita %s."):format(accessModeLabel(floor.mode)), "error")
                                end
                                if not gzf.authorize(k, v) then return end

                                local elevatorFloors = filterIplPoints(getIplFloors(v.ipl), inVehicle)
                                local exitEntries = filterIplPoints(getIplEntries(v.ipl), inVehicle)
                                local destination = selectElevatorDestination(
                                    "Elevador - " .. (floor.label or k),
                                    elevatorFloors,
                                    exitEntries,
                                    floor.index
                                )

                                if not destination or not destination.point or not destination.point.coords then
                                    if #elevatorFloors <= 1 and #exitEntries == 0 then
                                        utils.notify("Nenhum destino compativel foi configurado para este elevador.", "error")
                                    end
                                    return
                                end

                                if destination.kind == "floor" then
                                    runGarageTransition("Trocando de andar...", function()
                                        teleportPedOrVehicle(destination.point.coords, inVehicle and "none" or "pedWalk2m")
                                    end)
                                    return
                                end

                                runGarageTransition("Saindo da garagem...", function()
                                    TriggerServerEvent('forge_garage:server:exitPersistentZone', k)
                                    TriggerServerEvent("forge_garage:server:setPlayerGarageBucket", 0)
                                    Wait(100)
                                    teleportPedOrVehicle(destination.point.coords, inVehicle and "vehicleRoll10m" or "pedWalk2m")
                                    unloadActiveGarageIpl()
                                end)
                            end)
                        end
                    end,
                    onExit = function()
                        stui = false
                        utils.drawtext('hide')
                    end
                })
            end

            local parkingSpots = getIplParkingSpots(v.ipl)
            for spotIndex = 1, #parkingSpots do
                local spot = parkingSpots[spotIndex]
                local spotCoords = spot.coords
                CreatedZone[k .. ":ipl_parking:" .. spotIndex] = GarageBridge.zones.sphere({
                    coords = vec3(spotCoords.x, spotCoords.y, spotCoords.z),
                    radius = spot.radius or 3.0,
                    inside = function()
                        if GarageBridge.cache.vehicle then
                            if not stui then
                                local dl = ('[E/Buzina] - Estacionar %s'):format(spot.label or k)
                                utils.drawtext('show', dl, 'warehouse')
                                stui = true
                            end

                            if (IsControlJustPressed(0, 38) or IsControlJustPressed(0, 86)) then
                                runZoneInteraction(function()
                                    if not gzf.authorize(k, v) then return end
                                    exports['forge-garage']:storeVehicle(args)
                                end)
                            end
                        elseif stui then
                            stui = false
                            utils.drawtext('hide')
                        end
                    end,
                    onExit = function()
                        stui = false
                        utils.drawtext('hide')
                    end
                })
            end

            goto continue
        end

        if not v.zones or not v.zones.points then
            goto continue
        end

        do
        local zoneOptions = {
            points = v.zones.points,
            thickness = v.zones.thickness,
        }

        local args = {
            garage = k,
            impound = v.impound,
            shared = v.shared,
            type = v.type,
            spawnpoint = v.spawnPoint,
            vehicles = v.vehicles,
            ignoreDist = true
        }

        if type(v.interaction) == "table" then
            
            function zoneOptions:inside()
                if not stui then
                    local dl = GarageBridge.cache.vehicle and ('[E/Buzina] - %s'):format(k) or k
                    utils.drawtext('show', dl, 'warehouse')
                    stui = true
                end
                if (IsControlJustPressed(0, 38) or IsControlJustPressed(0, 86)) and GarageBridge.cache.vehicle then
                    runZoneInteraction(function()
                        if not gzf.authorize(k, v) then return end
                        exports['forge-garage']:storeVehicle(args)
                    end)
                end
            end

            function zoneOptions:onEnter()
                if not gzf.authorize(k, v) then return end
                local model = v.interaction.model
                local pc = v.interaction.coords
                if ped then DeleteEntity(ped) ped = nil end
                ped = utils.createTargetPed(model, pc, {
                    {
                        name = "open_garage",
                        label = "Abrir Garagem",
                        icon = "fas fa-warehouse",
                        action = function ()
                            args.ignoreDist = true
                            exports['forge-garage']:openMenu(args)
                        end,
                        distance = 1.5
                    }
                })
            end

            function zoneOptions:onExit()
                stui = false
                utils.drawtext('hide')
                local id = Config.Target == "ox" and "open_garage" or "Open Garage"
                utils.removeTargetPed(ped, id)
            end
        elseif v.interaction == "keypressed" then
            local promptAllowed = false
            local nextPromptRefresh = 0

            function zoneOptions:inside()
                if promptAllowed then
                    local now = GetGameTimer()
                    if now >= nextPromptRefresh then
                        local dl = GarageBridge.cache.vehicle and ('[E/Buzina] - %s'):format(k) or ('[E] - %s'):format(k)
                        utils.drawtext('show', dl, 'warehouse')
                        nextPromptRefresh = now + 1000
                    end
                end

                if IsControlJustPressed(0, 38) then
                    runZoneInteraction(function()
                        if not gzf.authorize(k, v) then return end
                        if GarageBridge.cache.vehicle then
                            return exports['forge-garage']:storeVehicle(args)
                        end
                        exports['forge-garage']:openMenu(args)
                    end)
                elseif IsControlJustPressed(0, 86) and GarageBridge.cache.vehicle then
                    runZoneInteraction(function()
                        if not gzf.authorize(k, v) then return end
                        exports['forge-garage']:storeVehicle(args)
                    end)
                end
            end

            function zoneOptions:onEnter()
                promptAllowed = gzf.authorize(k, v)
                nextPromptRefresh = 0
            end

            function zoneOptions:onExit()
                promptAllowed = false
                nextPromptRefresh = 0
                utils.drawtext('hide')
            end
        elseif v.interaction == "radial" then
            function zoneOptions:onEnter()
                if not gzf.authorize(k, v) then return end
                utils.drawtext('show', k:upper(), 'warehouse')

                radFunc.create({
                    id = "open_garage",
                    label = v.impound and GarageBridge.locale('garage.access_impound') or GarageBridge.locale("garage.open"),
                    icon = "warehouse",
                    event = "forge_garage:radial:open",
                    args = args
                })

                if not v.impound then
                    radFunc.create({
                        id = "store_veh",
                        label = GarageBridge.locale("garage.store"),
                        icon = "parking",
                        event = "forge_garage:radial:store",
                        args = args
                    })
                end
            end

            function zoneOptions:onExit()
                utils.drawtext('hide')

                radFunc.remove("open_garage")
                radFunc.remove("store_veh")
            end
        elseif v.persist then
            local promptVisible = false
            local nextPromptRefresh = 0

            function zoneOptions:inside()
                if GarageBridge.cache.vehicle then
                    local now = GetGameTimer()
                    if not promptVisible or now >= nextPromptRefresh then
                        local dl = ('[E/Buzina] - Estacionar em %s'):format(k)
                        utils.drawtext('show', dl, 'warehouse')
                        promptVisible = true
                        nextPromptRefresh = now + 1000
                    end

                    if (IsControlJustPressed(0, 38) or IsControlJustPressed(0, 86)) then
                        runZoneInteraction(function()
                            if not gzf.authorize(k, v) then return end
                            exports['forge-garage']:storeVehicle(args)
                        end)
                    end
                elseif promptVisible then
                    utils.drawtext('hide')
                    promptVisible = false
                    nextPromptRefresh = 0
                end
            end

            function zoneOptions:onEnter()
                -- Handled inside()
            end

            function zoneOptions:onExit()
                promptVisible = false
                nextPromptRefresh = 0
                utils.drawtext('hide')
            end
        end
        CreatedZone[k] = GarageBridge.zones.poly(zoneOptions)
        end
        ::continue::
    end
    pcall(function()
        exports['forge-garage']:setupPersistentGarages()
    end)
end

GarageBridge.onCache('vehicle', function(value)
    stui = false
end)

function gzf.save ( data )
    TriggerServerEvent("forge_garage:server:saveGarageZone", data)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    unloadActiveGarageIpl()
end)
