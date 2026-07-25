local spawnPoint = GarageBridge.loadModule('modules.spawnpoint')
local pedcreator = GarageBridge.loadModule('modules.pedcreator')

local listGarage

local function buildGarageZone(points)
    if type(points) ~= 'table' or #points < 3 then return end

    local zonePoints = {}
    for index = 1, #points do
        local point = points[index]
        zonePoints[index] = vec3(point.x, point.y, point.z)
    end

    return {
        points = zonePoints,
        thickness = 4.0,
    }
end

local function returnToContext(contextId)
    if not contextId then return end

    CreateThread(function()
        Wait(0)
        pr_lib.showContext(contextId)
    end)
end

--- Blip Input
---@param impound boolean
---@return promise
local function blipInput(impound, gLabel)
    local p = promise.new()
    CreateThread(function()
        ---@class BlipData
        local br = {}
        
        ::tryAgain::
        local blipinput = pr_lib.inputDialog('BLIP', {
            { type = 'number', label = GarageBridge.locale("input.admin.creator_bliptype"), required = true, default = impound and 68 or 357},
            { type = 'number', label = GarageBridge.locale("input.admin.creator_blipcolor"), required = true, default = 3},
            { type = 'input', label = GarageBridge.locale("input.admin.creator_bliplabel"), required = true, default = gLabel },
        })

        local hi = blipinput
        if not hi then
            return
        end

        if utils.string.isEmpty(hi[3]) then
            goto tryAgain
        end

        br.type = hi[1]
        br.color = hi[2]
        br.label = hi[3]
        p:resolve(br)
    end)
    return Citizen.Await(p)
end

--- Create garage input
local function createGarage ()
    local started = pr_lib.devtools.drawPolyzone3D({
        minPoints = 3,
        wallHeight = 4.0,
        freezePlayer = true,
    }, function(points)
        local zones = buildGarageZone(points)
        if not zones then
            listGarage()
            return
        end

            local input = pr_lib.inputDialog('RHD GARAGE (Creator)', {
                { type = 'input', label = GarageBridge.locale("input.admin.creator_labelgarage"), placeholder = 'Alta Garage', required = true },
                { type = 'multi-select', label = GarageBridge.locale("input.admin.creator_typevehicle"), options = {
                    {value = "car", label = "Carros"},
                    {value = "boat", label = "Barcos"},
                    {value = "helicopter", label = "Helicóptero"},
                    {value = "planes", label = "Aviões"},
                    {value = "motorcycle", label = "Motocicleta"},
                    {value = "cycles", label = "Bicicleta"},
                }, required = true},
                { type = 'checkbox', label = "Use Blip", disabled = true},
                { type = 'checkbox', label = "Garagem de Apreensão"},
                { type = 'checkbox', label = "Garagem de Carros Compartilhados"},
                { type = 'checkbox', label = "Garagem com Vagas"},
                { type = 'checkbox', label = "Persistir Veículos Estacionados"},
                { type = 'select', label = "Abrir garagem", options = {
                    { value = "radial",     label = "Usando Radial Menu" },
                    { value = "keypressed", label = "Usando Tecla E" },
                    { value = "targetped",  label = "Usando NPC com Target" }
                }, required = false},
            })
            if input then
                local tPed = input[8] == 'targetped'
                local Impound = not input[5] and input[4] or false
                local label = input[1]
                local gtype = input[2]
                local blip = input[3] and blipInput(Impound, label) or nil
                local shared = input[5]
                local sp = input[6] and spawnPoint.create(zones, false, nil, gtype) or nil ---@type table<string, vector3[]|string[]>
                local persist = input[7]
                local interact = tPed and pedcreator.start(zones) or input[8]

                if tPed and not sp then
                    Wait(1000)
                    sp = spawnPoint.create(zones, true, nil, gtype) or nil ---@type table<string, vector3[]|string[]>
                end

                GarageZone[label] = {
                    type = gtype,
                    blip = blip,
                    zones = zones,
                    impound = Impound,
                    shared = shared,
                    persist = persist,
                    spawnPoint = sp and sp.c or sp,
                    spawnPointVehicle = sp and sp.v or sp,
                    interaction = interact
                }
                
                gzf.save(GarageZone)
                utils.notify(GarageBridge.locale("notify.admin.success_create", label:upper()), "success")
            end
        end)

    if not started then
        listGarage()
    end
end

local function notifyPersistentOpeningIgnored()
    utils.notify("Garagens IPL ou com persistencia ignoram o modo de abertura. A gestao acontece pela persistencia dos veiculos estacionados.", "inform", 9000)
end

local function getIplBucket(label)
    return 200000 + math.abs(GetHashKey(label) % 50000)
end

local function formatIplName(ipl)
    if type(ipl) == "table" then
        return table.concat(ipl, ", ")
    end

    return ipl or "N/A"
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

local function collectKnownCreatorIpls()
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

    for _, garage in pairs(GarageZone or {}) do
        local model = garage and garage.ipl and garage.ipl.model
        local list = normalizeIplList(model)
        for j = 1, #list do
            known[list[j]] = true
        end
    end

    return known
end

local function unloadKnownCreatorIpls(exceptIpls)
    local known = collectKnownCreatorIpls()
    local removed = {}

    for iplName, _ in pairs(known) do
        if not exceptIpls or not exceptIpls[iplName] then
            setGarageIplDefaults(iplName, false)
            RemoveIpl(iplName)
            removed[#removed + 1] = iplName
        end
    end

    if #removed > 0 and not waitForIplState(removed, false) then
        print("[forge-garage] timeout while disabling garage IPL previews")
    end
end

local function requestGarageIpl(ipl)
    local nextIpls = {}

    local list = normalizeIplList(ipl)
    for i = 1, #list do
        nextIpls[list[i]] = true
    end

    unloadKnownCreatorIpls(nextIpls)

    for iplName, _ in pairs(nextIpls) do
        RequestIpl(iplName)
    end

    Wait(100)

    for iplName, _ in pairs(nextIpls) do
        setGarageIplDefaults(iplName, true)
    end

    return true
end

local function prepareGarageIpl(ipl, coords)
    if gzf and type(gzf.prepareIpl) == "function" then
        return gzf.prepareIpl(ipl)
    end

    return requestGarageIpl(ipl)
end

local function unloadGarageIpl()
    if gzf and type(gzf.unloadIpl) == "function" then
        gzf.unloadIpl()
        return
    end

    unloadKnownCreatorIpls()
end

local function getGarageIplByIndex(index)
    index = tonumber(index)
    return index and Config.GarageIpls and Config.GarageIpls[index] or nil
end

local function currentSafetyEntry()
    local entity = GarageBridge.cache.vehicle and GarageBridge.cache.vehicle ~= 0 and GarageBridge.cache.vehicle or GarageBridge.cache.ped
    local coords = GetEntityCoords(entity)
    return vec4(coords.x, coords.y, coords.z, GetEntityHeading(entity))
end

local function createGarageIpl()
    local input = pr_lib.inputDialog('RHD GARAGE (Creator)', {
        { type = 'input', label = GarageBridge.locale("input.admin.creator_labelgarage"), placeholder = 'Alta Garage', required = true },
        { type = 'multi-select', label = GarageBridge.locale("input.admin.creator_typevehicle"), options = {
            {value = "car", label = "Carros"},
            {value = "boat", label = "Barcos"},
            {value = "helicopter", label = "Helicoptero"},
            {value = "planes", label = "Avioes"},
            {value = "motorcycle", label = "Motocicleta"},
            {value = "cycles", label = "Bicicleta"},
        }, required = true},
        { type = 'checkbox', label = "Use Blip", disabled = true},
        { type = 'checkbox', label = "Garagem de Apreensao"},
        { type = 'checkbox', label = "Garagem de Carros Compartilhados"},
        { type = 'checkbox', label = "Garagem com Vagas"},
        { type = 'checkbox', label = "Persistir Veiculos Estacionados"},
        { type = 'checkbox', label = "Usar modelo IPL"},
        { type = 'select', label = "Abrir garagem", options = {
            { value = "radial",     label = "Usando Radial Menu" },
            { value = "keypressed", label = "Usando Tecla E" },
            { value = "targetped",  label = "Usando NPC com Target" }
        }, required = false},
    })

    if not input then
        listGarage()
        return
    end

    local label = input[1]
    local gtype = input[2]
    local impound = not input[5] and input[4] or false
    local shared = input[5]
    local useIpl = input[8] and true or false
    local persist = useIpl and true or input[7]
    local blip = input[3] and blipInput(impound, label) or nil

    if useIpl or persist then
        notifyPersistentOpeningIgnored()
    end

    if useIpl then
        local safetyEntry = currentSafetyEntry()
        GarageZone[label] = {
            type = gtype,
            blip = blip,
            impound = impound,
            shared = shared,
            persist = true,
            ipl = {
                enabled = true,
                model = nil,
                bucket = getIplBucket(label),
                entry = safetyEntry,
                exit = nil,
                entries = {
                    {
                        label = "Entrada Principal de Seguranca",
                        coords = safetyEntry,
                        mode = "both"
                    }
                },
                floors = {},
                parkingSpots = {},
                allowVehicle = true
            }
        }

        gzf.save(GarageZone)
        utils.notify(GarageBridge.locale("notify.admin.success_create", label:upper()), "success")
        utils.notify("Entrada principal de seguranca criada na sua posicao atual.", "inform", 8000)
        listGarage()
        return
    end

    local started = pr_lib.devtools.drawPolyzone3D({
        minPoints = 3,
        wallHeight = 4.0,
        freezePlayer = true,
    }, function(points)
            local createdZone = buildGarageZone(points)
            if not createdZone then
                listGarage()
                return
            end

            local tPed = not persist and input[9] == 'targetped'
            local sp = input[6] and spawnPoint.create(createdZone, false, nil, gtype) or nil ---@type table<string, vector3[]|string[]>
            local interact = not persist and (tPed and pedcreator.start(createdZone) or input[9]) or nil

            if tPed and not sp then
                Wait(1000)
                sp = spawnPoint.create(createdZone, true, nil, gtype) or nil ---@type table<string, vector3[]|string[]>
            end

            GarageZone[label] = {
                type = gtype,
                blip = blip,
                zones = createdZone,
                impound = impound,
                shared = shared,
                persist = persist,
                spawnPoint = sp and sp.c or sp,
                spawnPointVehicle = sp and sp.v or sp,
                interaction = interact
            }

            gzf.save(GarageZone)
            utils.notify(GarageBridge.locale("notify.admin.success_create", label:upper()), "success")
            listGarage()
        end)

    if not started then
        listGarage()
    end
end

--- Delete garage by index
local function delete(self)
    GarageZone[self.label --[[@as string]]] = nil
    gzf.save(GarageZone)
    utils.notify(GarageBridge.locale("notify.admin.success_deleted", self.label --[[@as string]]), "success")
    listGarage()
end

--- Set blip garage
local function setBlip(self)
    local k, v = self.k, self.v ---@type string, GarageData
    local blipContext = {
        id = "blip_setting",
        title = GarageBridge.locale("context.admin.blip_setting"),
        menu = self.parentMenu or "rhd:action_garage",
        onBack = function()

        end,
        options = {
            {
                title = GarageBridge.locale("context.admin.blip_edit"),
                icon = "pen-to-square",
                onSelect = function ()
                    local gBlip = v.blip

                    local placeholder = {
                        type = gBlip and gBlip.type or '',
                        color = gBlip and gBlip.color or '',
                        label = gBlip and gBlip.label or k
                    }

                    local blipinput = pr_lib.inputDialog('BLIP', {
                        { type = 'number', label = GarageBridge.locale("input.admin.creator_bliptype"), required = true, default = placeholder.type },
                        { type = 'number', label = GarageBridge.locale("input.admin.creator_blipcolor"), required = true, default = placeholder.color },
                        { type = 'input', label = GarageBridge.locale("input.admin.creator_bliplabel"), required = true, default = placeholder.label },
                    })

                    if blipinput then
                        GarageZone[k].blip = {
                            type = blipinput[1],
                            color = blipinput[2],
                            label = blipinput[3]
                        }
                        gzf.save(GarageZone)
                        utils.notify(GarageBridge.locale("notify.admin.success_editblip"), "success")
                    end
                    setBlip({ k = k, v = GarageZone[k], parentMenu = self.parentMenu })
                end
            },
            {
                title = GarageBridge.locale("context.admin.blip_remove"),
                icon = "trash",
                onSelect = function()
                    GarageZone[k].blip = nil
                    gzf.save(GarageZone)
                    utils.notify("Blip berhasil di hapus", "success")
                    setBlip({ k = k, v = GarageZone[k], parentMenu = self.parentMenu })
                end
            }
        }
    }
    utils.createMenu(blipContext)
end

--- Change garage locations
local function changeLocation(self)
    local started = pr_lib.devtools.drawPolyzone3D({
        minPoints = 3,
        wallHeight = 4.0,
        freezePlayer = true,
    }, function(points)
            local Zones = buildGarageZone(points)
            if not Zones then
                returnToContext(self.returnMenu)
                return
            end

            GarageZone[self.label --[[@as string]]].zones = Zones
            gzf.save(GarageZone)
            utils.notify(GarageBridge.locale("notify.admin.success_changelocation"), "success")
            returnToContext(self.returnMenu)
        end)

    if not started then
        returnToContext(self.returnMenu)
    end
end

--- Teleport to garage location
local function teleportToLocation(self)
    local coords = self.coords --[[@as vector3]]
    if not coords then
        utils.notify("Esta garagem ainda nao possui local configurado.", "error")
        returnToContext(self.returnMenu)
        return
    end

    DoScreenFadeOut(500)
    Wait(1000)
    SetPedCoordsKeepVehicle(GarageBridge.cache.ped, coords.x, coords.y, coords.z)
    DoScreenFadeIn(500)
    returnToContext(self.returnMenu)
end

local function currentCoords()
    local coords = GetEntityCoords(GarageBridge.cache.ped)
    local heading = GetEntityHeading(GarageBridge.cache.ped)
    return vec4(coords.x, coords.y, coords.z, heading)
end

local function iplAccessOptions()
    return {
        { value = "both", label = "A pe e veiculo" },
        { value = "ped", label = "Somente a pe" },
        { value = "vehicle", label = "Somente veiculo" }
    }
end

local function accessModeLabel(mode)
    if mode == "ped" then return "Somente a pe" end
    if mode == "vehicle" then return "Somente veiculo" end
    return "A pe e veiculo"
end

local function normalizeAccessMode(mode)
    if mode == "ped" or mode == "vehicle" or mode == "both" then
        return mode
    end

    return "both"
end

local function modeAllowsVehicle(mode)
    return mode == "vehicle" or mode == "both" or mode == nil
end

local function modeAllowsPed(mode)
    return mode == "ped" or mode == "both" or mode == nil
end

local function pointFromVehiclePlacement(placement)
    if type(placement) ~= "table" then return nil end
    local coords = type(placement.coords) == "table" and placement.coords or placement
    return vec4(
        tonumber(coords.x or coords[1]) or 0.0,
        tonumber(coords.y or coords[2]) or 0.0,
        tonumber(coords.z or coords[3]) or 0.0,
        tonumber(placement.heading or coords.w or coords.h or coords[4]) or 0.0
    )
end

local function placeIplVehiclePoint(label, defaultHeading, cb)
    if not pr_lib or not pr_lib.devtools or type(pr_lib.devtools.placeVehicle) ~= "function" then
        utils.notify("DevTools do pr_bridge indisponivel para posicionar veiculo.", "error", 8000)
        return false
    end

    utils.notify(label .. ": posicione o veiculo e pressione ENTER para salvar.", "inform", 8000)
    local started = pr_lib.devtools.placeVehicle("kuruma", 1, function(placement)
        local point = pointFromVehiclePlacement(placement)
        if not point then
            utils.notify("Posicionamento cancelado.", "inform")
        end
        cb(point)
    end, {
        preview = true,
        freezePlayer = true,
        heading = defaultHeading,
        heightOffset = 0.0,
        heightStep = 0.01,
        modelTimeout = 5000
    })

    if started ~= true then
        utils.notify("Nao foi possivel iniciar o posicionador de veiculo.", "error")
        return false
    end

    return true
end

local function ensureIplData(k)
    GarageZone[k].ipl = GarageZone[k].ipl or {}
    GarageZone[k].ipl.enabled = true
    GarageZone[k].ipl.bucket = GarageZone[k].ipl.bucket or getIplBucket(k)
    GarageZone[k].ipl.allowVehicle = GarageZone[k].ipl.allowVehicle ~= false
    GarageZone[k].ipl.entries = GarageZone[k].ipl.entries or {}
    if GarageZone[k].ipl.entry and #GarageZone[k].ipl.entries == 0 then
        GarageZone[k].ipl.entries[1] = {
            label = "Entrada 1",
            coords = GarageZone[k].ipl.entry,
            mode = GarageZone[k].ipl.allowVehicle == false and "ped" or "both"
        }
    end
    GarageZone[k].ipl.floors = GarageZone[k].ipl.floors or {}
    GarageZone[k].ipl.parkingSpots = GarageZone[k].ipl.parkingSpots or {}
    if GarageZone[k].ipl.exit and #GarageZone[k].ipl.floors == 0 then
        GarageZone[k].ipl.floors[1] = {
            label = "Andar 1",
            coords = GarageZone[k].ipl.exit,
            mode = GarageZone[k].ipl.allowVehicle == false and "ped" or "both"
        }
    end
    GarageZone[k].ipl.entry = GarageZone[k].ipl.entries[1] and GarageZone[k].ipl.entries[1].coords or GarageZone[k].ipl.entry
    GarageZone[k].ipl.exit = GarageZone[k].ipl.floors[1] and GarageZone[k].ipl.floors[1].coords or GarageZone[k].ipl.exit
    GarageZone[k].persist = true
    GarageZone[k].interaction = nil
    return GarageZone[k].ipl
end

local function hasValidIplEntry(data)
    if data and type(data.entries) == "table" then
        for i = 1, #data.entries do
            if data.entries[i] and (data.entries[i].coords or data.entries[i].x) then
                return true
            end
        end
    end

    return data and data.entry ~= nil
end

local teleportToIplPoint

local function applyIplModel(self)
    local selected = getGarageIplByIndex(self.index)
    if not selected then
        returnToContext(self.returnMenu)
        return
    end

    local data = ensureIplData(self.k)
    if not hasValidIplEntry(data) then
        utils.notify("Crie uma entrada externa antes de selecionar o modelo IPL.", "error", 8000)
        returnToContext(self.returnMenu)
        return
    end

    data.label = selected.label
    data.model = selected.ipl
    data.preview = selected.preview
    data.floors = selected.floors or data.floors or {}
    if selected.preview and #data.floors == 0 then
        data.floors[1] = {
            label = "Andar 1",
            coords = selected.preview
        }
        data.exit = selected.preview
    end
    gzf.save(GarageZone)

    if selected.preview then
        teleportToIplPoint({ coords = selected.preview, bucket = data.bucket, ipl = data.model })
    elseif not prepareGarageIpl(data.model) then
        returnToContext(self.returnMenu)
        return
    end

    utils.notify("Modelo IPL selecionado: " .. selected.label, "success", 8000)
    returnToContext(self.returnMenu)
end

local function setIplModel(self)
    local data = ensureIplData(self.k)
    if not hasValidIplEntry(data) then
        utils.notify("Crie uma entrada externa antes de selecionar o modelo IPL.", "error", 8000)
        returnToContext(self.returnMenu)
        return
    end

    local current = data.model
    local contextId = "rhd:ipl_models_" .. self.k
    local options = {}

    for i = 1, #(Config.GarageIpls or {}) do
        local item = Config.GarageIpls[i]
        local selected = current and formatIplName(current) == formatIplName(item.ipl)
        options[#options + 1] = {
            title = item.label,
            icon = selected and "circle-check" or "warehouse",
            description = ("IPL tecnico: %s%s"):format(formatIplName(item.ipl), item.preview and " | Preview disponivel" or " | Sem preview configurado"),
            onSelect = applyIplModel,
            args = {
                k = self.k,
                index = i,
                returnMenu = self.returnMenu
            }
        }
    end

    if #options == 0 then
        utils.notify("Nenhum modelo IPL foi configurado em Config.GarageIpls.", "error", 8000)
        returnToContext(self.returnMenu)
        return
    end

    utils.createMenu({
        id = contextId,
        title = "Selecionar Modelo IPL",
        menu = self.returnMenu,
        options = options
    })
end

local function setIplEntry(self)
    local data = ensureIplData(self.k)
    local options = {}

    for i = 1, #data.entries do
        options[#options + 1] = {
            value = i,
            label = data.entries[i].label or ("Entrada " .. i)
        }
    end

    options[#options + 1] = {
        value = 0,
        label = "Adicionar nova entrada"
    }

    local input = pr_lib.inputDialog("Entrada do IPL", {
        { type = "select", label = "Entrada", options = options, default = 0, required = true },
        { type = "input", label = "Nome da entrada", placeholder = "Ex: Rua / Fundos / Subsolo", required = false },
        { type = "select", label = "Permitir acesso", options = iplAccessOptions(), default = data.entries[1] and data.entries[1].mode or "both", required = true }
    })

    if not input then
        returnToContext(self.returnMenu)
        return
    end

    local index = tonumber(input[1]) or 0
    local mode = input[3] or "both"
    local label = input[2]
    if utils.string.isEmpty(label or "") then
        label = index > 0 and data.entries[index] and data.entries[index].label or ("Entrada " .. (#data.entries + 1))
    end

    local function saveEntry(coords)
        if not coords then
            returnToContext(self.returnMenu)
            return
        end

        local entry = {
            label = label,
            coords = coords,
            mode = mode
        }

        if index > 0 and data.entries[index] then
            data.entries[index] = entry
        else
            data.entries[#data.entries + 1] = entry
        end

        data.entry = data.entries[1] and data.entries[1].coords or data.entry
        gzf.save(GarageZone)
        utils.notify("Entrada do IPL salva com sucesso.", "success")
        returnToContext(self.returnMenu)
    end

    if modeAllowsVehicle(mode) then
        if not placeIplVehiclePoint("Entrada do IPL", data.entries[index] and data.entries[index].coords and data.entries[index].coords.w, saveEntry) then
            returnToContext(self.returnMenu)
        end
    else
        saveEntry(currentCoords())
    end
end

local function setIplFloor(self)
    local data = ensureIplData(self.k)
    local options = {}

    for i = 1, #data.floors do
        options[#options + 1] = {
            value = i,
            label = ("%s | %s"):format(data.floors[i].label or ("Andar " .. i), accessModeLabel(data.floors[i].mode))
        }
    end

    options[#options + 1] = {
        value = 0,
        label = "Adicionar novo andar"
    }

    local selection = pr_lib.inputDialog("Elevador do IPL", {
        { type = "select", label = "Ponto do elevador", options = options, default = 0, required = true }
    })

    if not selection then
        returnToContext(self.returnMenu)
        return
    end

    local index = tonumber(selection[1]) or 0
    local current = index > 0 and data.floors[index] or nil
    local input = pr_lib.inputDialog(index > 0 and "Editar elevador" or "Novo elevador", {
        {
            type = "input",
            label = "Nome do andar",
            placeholder = "Ex: Andar 1 / Subsolo / Oficina",
            default = current and current.label or nil,
            required = false
        },
        {
            type = "select",
            label = "Tipo de elevador",
            options = iplAccessOptions(),
            default = current and current.mode or "both",
            required = true
        }
    })

    if not input then
        returnToContext(self.returnMenu)
        return
    end

    local label = input[1]
    local mode = input[2] or "both"
    if utils.string.isEmpty(label or "") then
        label = index > 0 and data.floors[index] and data.floors[index].label or ("Andar " .. (#data.floors + 1))
    end

    local function saveFloor(coords)
        if not coords then
            returnToContext(self.returnMenu)
            return
        end

        local floor = {
            label = label,
            coords = coords,
            mode = mode
        }

        if index > 0 and data.floors[index] then
            data.floors[index] = floor
        else
            data.floors[#data.floors + 1] = floor
        end

        data.exit = data.floors[1] and data.floors[1].coords or data.exit
        gzf.save(GarageZone)
        utils.notify("Ponto de elevador salvo com sucesso.", "success")
        returnToContext(self.returnMenu)
    end

    if modeAllowsVehicle(mode) then
        if not placeIplVehiclePoint("Elevador interno do IPL", data.floors[index] and data.floors[index].coords and data.floors[index].coords.w, saveFloor) then
            returnToContext(self.returnMenu)
        end
    else
        saveFloor(currentCoords())
    end
end

local function setIplParkingSpot(self)
    local data = ensureIplData(self.k)
    local existing = { c = {}, v = {} }

    for i = 1, #data.parkingSpots do
        local spot = data.parkingSpots[i]
        existing.c[i] = spot.coords
        existing.v[i] = spot.vehicle or spot.model or "kuruma"
    end

    local result = spawnPoint.create(nil, false, existing, GarageZone[self.k].type, true)
    if not result then
        returnToContext(self.returnMenu)
        return
    end

    data.parkingSpots = {}
    for i = 1, #(result.c or {}) do
        data.parkingSpots[i] = {
            label = "Vaga " .. i,
            coords = result.c[i],
            vehicle = result.v and result.v[i] or nil,
            radius = 3.0
        }
    end

    gzf.save(GarageZone)
    utils.notify("Vagas IPL atualizadas com sucesso.", "success")
    returnToContext(self.returnMenu)
end

local function listIplParkingSpots(self)
    local data = ensureIplData(self.k)
    local contextId = "rhd:ipl_parking_" .. self.k
    local context = {
        id = contextId,
        title = "Vagas IPL: " .. self.k,
        menu = self.parentMenu or "rhd:action_garage",
        options = {
            {
                title = "Editar Vagas",
                icon = "square-parking",
                description = "Usa o criador original de vagas, sem limitar por polyzone.",
                onSelect = setIplParkingSpot,
                args = { k = self.k, returnMenu = contextId }
            }
        }
    }

    for i = 1, #data.parkingSpots do
        local spot = data.parkingSpots[i]
        context.options[#context.options + 1] = {
            title = spot.label or ("Vaga " .. i),
            icon = "location-dot",
            description = ("Raio: %sm"):format(spot.radius or 3.0),
            onSelect = teleportToIplPoint,
            args = { coords = spot.coords, bucket = data.bucket, ipl = data.model, returnMenu = contextId }
        }
    end

    utils.createMenu(context)
end

local listIplFloors

local function deleteIplFloor(self)
    local data = ensureIplData(self.k)
    local floor = data.floors[self.index]
    if not floor then
        listIplFloors({ k = self.k, mode = self.mode, parentMenu = self.parentMenu })
        return
    end

    if #data.floors <= 1 and data.model then
        utils.notify("Nao e possivel apagar o ultimo elevador interno enquanto houver um modelo IPL selecionado.", "error", 8000)
        returnToContext(self.returnMenu)
        return
    end

    local confirmed = pr_lib.alertDialog({
        header = "Apagar Andar",
        content = ("Deseja apagar o andar/elevador interno **%s**?"):format(floor.label or self.index),
        centered = true,
        cancel = true
    }) == "confirm"

    if not confirmed then
        returnToContext(self.returnMenu)
        return
    end

    table.remove(data.floors, self.index)
    data.exit = data.floors[1] and data.floors[1].coords or nil
    gzf.save(GarageZone)
    utils.notify("Andar/elevador interno apagado com sucesso.", "success")
    listIplFloors({ k = self.k, mode = self.mode, parentMenu = self.parentMenu })
end

local function openIplFloorActions(self)
    local data = ensureIplData(self.k)
    local floor = data.floors[self.index]
    if not floor then
        listIplFloors({ k = self.k, mode = self.mode, parentMenu = self.parentMenu })
        return
    end

    local contextId = ("rhd:ipl_floor_actions_%s_%s"):format(self.k, self.index)
    utils.createMenu({
        id = contextId,
        title = floor.label or ("Andar " .. self.index),
        menu = self.listMenu,
        options = {
            {
                title = "Teleportar para o Andar",
                icon = "location-dot",
                description = "Carrega o IPL e teleporta para este elevador interno.",
                onSelect = teleportToIplPoint,
                args = { coords = floor.coords, bucket = data.bucket, ipl = data.model, returnMenu = contextId }
            },
            {
                title = "Apagar Andar",
                icon = "trash",
                description = "Remove permanentemente este elevador interno.",
                onSelect = deleteIplFloor,
                args = {
                    k = self.k,
                    index = self.index,
                    mode = self.mode,
                    parentMenu = self.parentMenu,
                    returnMenu = contextId
                }
            }
        }
    })
end

listIplFloors = function(self)
    local data = ensureIplData(self.k)
    local mode = self.mode
    local modeTitles = {
        ped = "Elevadores a pe",
        vehicle = "Elevadores de veiculo",
        both = "Elevadores mistos"
    }
    local contextId = ("rhd:ipl_floors_%s_%s"):format(self.k, mode or "all")
    local context = {
        id = contextId,
        title = (modeTitles[mode] or "Todos os elevadores") .. ": " .. self.k,
        menu = self.parentMenu or ("rhd:ipl_elevators_" .. self.k),
        options = {}
    }

    for i = 1, #data.floors do
        local floor = data.floors[i]
        local floorMode = normalizeAccessMode(floor.mode)
        if not mode or floorMode == mode then
            context.options[#context.options + 1] = {
                title = floor.label or ("Andar " .. i),
                icon = floorMode == "ped" and "person" or floorMode == "vehicle" and "car" or "people-arrows-left-right",
                description = "Dentro do IPL | Tipo de acesso: " .. accessModeLabel(floorMode),
                onSelect = openIplFloorActions,
                args = {
                    k = self.k,
                    index = i,
                    mode = mode,
                    parentMenu = self.parentMenu,
                    listMenu = contextId
                }
            }
        end
    end

    if #context.options == 0 then
        context.options[#context.options + 1] = {
            title = "Nenhum andar configurado",
            icon = "circle-info",
            disabled = true
        }
    end

    utils.createMenu(context)
end

local function listIplElevators(self)
    local data = ensureIplData(self.k)
    local contextId = "rhd:ipl_elevators_" .. self.k
    local counts = { ped = 0, vehicle = 0, both = 0 }

    for i = 1, #data.floors do
        local mode = normalizeAccessMode(data.floors[i].mode)
        counts[mode] = (counts[mode] or 0) + 1
    end

    utils.createMenu({
        id = contextId,
        title = "Elevadores Internos: " .. self.k,
        menu = self.parentMenu or ("rhd:ipl_elevator_system_" .. self.k),
        options = {
            {
                title = "Adicionar/Atualizar Elevador Interno",
                icon = "plus",
                description = "Salva o ponto interno, nome do andar e tipo de acesso.",
                onSelect = setIplFloor,
                args = { k = self.k, returnMenu = contextId }
            },
            {
                title = "Elevadores a Pe",
                icon = "person",
                description = ("Andares exclusivos para pedestres: %s"):format(counts.ped),
                onSelect = listIplFloors,
                args = { k = self.k, mode = "ped", parentMenu = contextId }
            },
            {
                title = "Elevadores de Veiculo",
                icon = "car",
                description = ("Andares exclusivos para veiculos: %s"):format(counts.vehicle),
                onSelect = listIplFloors,
                args = { k = self.k, mode = "vehicle", parentMenu = contextId }
            },
            {
                title = "Elevadores Mistos",
                icon = "people-arrows-left-right",
                description = ("Disponiveis nos dois tipos de elevador: %s"):format(counts.both),
                onSelect = listIplFloors,
                args = { k = self.k, mode = "both", parentMenu = contextId }
            }
        }
    })
end

local function listIplEntries(self)
    local data = ensureIplData(self.k)
    local contextId = "rhd:ipl_entries_" .. self.k
    local hasPedElevator = false
    local hasVehicleElevator = false

    for i = 1, #data.floors do
        local floorMode = normalizeAccessMode(data.floors[i].mode)
        hasPedElevator = hasPedElevator or modeAllowsPed(floorMode)
        hasVehicleElevator = hasVehicleElevator or modeAllowsVehicle(floorMode)
    end

    local context = {
        id = contextId,
        title = "Elevadores Externos: " .. self.k,
        menu = self.parentMenu or ("rhd:ipl_elevator_system_" .. self.k),
        options = {
            {
                title = "Adicionar/Atualizar Elevador Externo",
                icon = "door-open",
                description = "Ponto fora do IPL usado para entrar ou sair da garagem.",
                onSelect = setIplEntry,
                args = { k = self.k, returnMenu = contextId }
            }
        }
    }

    for i = 1, #data.entries do
        local entry = data.entries[i]
        local entryMode = normalizeAccessMode(entry.mode)
        local warnings = {}

        if modeAllowsPed(entryMode) and not hasPedElevator then
            warnings[#warnings + 1] = "sem elevador a pe"
        end
        if modeAllowsVehicle(entryMode) and not hasVehicleElevator then
            warnings[#warnings + 1] = "sem elevador de veiculo"
        end

        local description = "Fora do IPL | Acesso: " .. accessModeLabel(entryMode)
        if #warnings > 0 then
            description = description .. " | ATENCAO: " .. table.concat(warnings, ", ")
        end

        context.options[#context.options + 1] = {
            title = entry.label or ("Entrada " .. i),
            icon = #warnings > 0 and "triangle-exclamation" or "location-dot",
            description = description,
            onSelect = teleportToIplPoint,
            args = { coords = entry.coords, bucket = 0, unloadIpl = true, returnMenu = contextId }
        }
    end

    utils.createMenu(context)
end

local function listIplElevatorSystem(self)
    local data = ensureIplData(self.k)
    local contextId = "rhd:ipl_elevator_system_" .. self.k

    utils.createMenu({
        id = contextId,
        title = "Sistema de Elevadores: " .. self.k,
        menu = "rhd:ipl_settings_" .. self.k,
        options = {
            {
                title = "Elevadores Externos",
                icon = "door-open",
                description = ("Fora do IPL | Entrada e saida | Total: %s"):format(#(data.entries or {})),
                onSelect = listIplEntries,
                args = { k = self.k, parentMenu = contextId }
            },
            {
                title = "Elevadores Internos",
                icon = "layer-group",
                description = ("Dentro do IPL | Comunicacao entre andares | Total: %s"):format(#(data.floors or {})),
                onSelect = listIplElevators,
                args = { k = self.k, parentMenu = contextId }
            }
        }
    })
end

local function listIplTeleports(self)
    local data = ensureIplData(self.k)
    local contextId = "rhd:ipl_teleports_" .. self.k
    local options = {}

    for i = 1, #data.entries do
        local entry = data.entries[i]
        options[#options + 1] = {
            title = "Entrada: " .. (entry.label or i),
            icon = "door-open",
            description = "Exterior | " .. accessModeLabel(entry.mode),
            onSelect = teleportToIplPoint,
            args = { coords = entry.coords, bucket = 0, unloadIpl = true, returnMenu = contextId }
        }
    end

    for i = 1, #data.floors do
        local floor = data.floors[i]
        options[#options + 1] = {
            title = "Elevador: " .. (floor.label or i),
            icon = "layer-group",
            description = "Interior | " .. accessModeLabel(floor.mode),
            onSelect = teleportToIplPoint,
            args = { coords = floor.coords, bucket = data.bucket, ipl = data.model, returnMenu = contextId }
        }
    end

    if #options == 0 then
        options[1] = {
            title = "Nenhum ponto configurado",
            icon = "circle-info",
            disabled = true
        }
    end

    utils.createMenu({
        id = contextId,
        title = "Teleportes: " .. self.k,
        menu = "rhd:ipl_settings_" .. self.k,
        options = options
    })
end

function teleportToIplPoint(self)
    local coords = self.coords
    if not coords then
        utils.notify("Este ponto ainda nao foi configurado.", "error")
        returnToContext(self.returnMenu)
        return
    end

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 50.0, 0)

    if self.ipl then
        prepareGarageIpl(self.ipl, coords)
    elseif self.unloadIpl then
        unloadGarageIpl()
    end

    TriggerServerEvent("forge_garage:server:setPlayerGarageBucket", self.bucket or 0)
    Wait(150)
    SetPedCoordsKeepVehicle(GarageBridge.cache.ped, coords.x, coords.y, coords.z)
    SetEntityHeading(GarageBridge.cache.ped, coords.w or 0.0)

    local vehicle = GarageBridge.cache.vehicle or GetVehiclePedIsIn(GarageBridge.cache.ped, false)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetEntityHeading(vehicle, coords.w or 0.0)
    end

    local deadline = GetGameTimer() + 5000
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    while not HasCollisionLoadedAroundEntity(GarageBridge.cache.ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end


    NewLoadSceneStop()
    ClearFocus()

    DoScreenFadeIn(500)
    returnToContext(self.returnMenu)
end

local function toggleIplVehicleAccess(self)
    local data = ensureIplData(self.k)
    data.allowVehicle = not data.allowVehicle
    gzf.save(GarageZone)
    utils.notify("Entrada com veiculo alterada.", "success")
end

local function iplOptions(self)
    local k, v = self.k, self.v
    local data = ensureIplData(k)
    local hasEntry = hasValidIplEntry(data)
    local contextId = "rhd:ipl_settings_" .. k

    local context = {
        id = contextId,
        title = "IPL: " .. k,
        menu = "rhd:action_garage",
        options = {
            {
                title = "Modelo IPL",
                icon = "warehouse",
                description = not hasEntry and "Bloqueado: crie primeiro uma entrada externa de seguranca."
                    or data.model and ("Atual: " .. (data.label or formatIplName(data.model)))
                    or "Nenhum modelo definido. Selecione para carregar o preview.",
                disabled = not hasEntry,
                onSelect = setIplModel,
                args = { k = k, v = v, returnMenu = contextId }
            },
            {
                title = "Sistema de Elevadores",
                icon = "layer-group",
                description = ("Externos: %s | Internos: %s"):format(#(data.entries or {}), #(data.floors or {})),
                onSelect = listIplElevatorSystem,
                args = { k = k }
            },
            {
                title = "Vagas IPL",
                icon = "square-parking",
                description = ("Criar e visualizar vagas | Total: %s"):format(#(data.parkingSpots or {})),
                onSelect = listIplParkingSpots,
                args = { k = k, parentMenu = contextId }
            },
            {
                title = "Teleportes de Configuracao",
                icon = "location-dot",
                description = "Entradas externas e todos os elevadores internos.",
                onSelect = listIplTeleports,
                args = { k = k }
            }
        }
    }

    utils.createMenu(context)
end

--- Change garage label
local function changeGarageLabel(self)
    local k, v = self.k, self.v ---@type string, GarageData
    
    local inputLabel = pr_lib.inputDialog(GarageBridge.locale("input.admin.header_changelabel"), {
        { type = 'input', label = GarageBridge.locale("input.admin.label_changelabel"), placeholder = 'Alta Garage, Pilbox Garage, Etc', required = true, min = 1 },
    })

    if inputLabel then
        local newLabel = inputLabel[1]
        GarageZone[newLabel] = v
        GarageZone[k] = nil
        gzf.save(GarageZone)
        utils.notify(GarageBridge.locale("notify.admin.success_changelabel", newLabel))
        listGarage()
    else
        returnToContext(self.returnMenu)
    end
end

--- Edit the spawn point
local function setspawnpoint(self)
    local k, v = self.k, self.v ---@type string, GarageData
    if not v.zones then
        utils.notify("Garagens IPL nao usam locais de spawn por polyzone.", "error")
        returnToContext(self.returnMenu)
        return
    end

    local asp = v.spawnPoint or {}
    local avsp = v.spawnPointVehicle or {}
    local noEmpty = asp and #asp > 0

    local context = {
        id = 'rhd:csp',
        title = 'Spawn Point',
        options = {},
        onBack = function ()
            
        end,
        menu = 'rhd:action_garage'
    }

    if noEmpty then
        for i = 1, #asp do
            context.options[#context.options + 1] = {
                title = "Point #" .. i,
                icon = "location-dot",
                description = "click me to teleport to my location",
                onSelect = function()
                    local coords = asp[i]
                    DoScreenFadeOut(500)
                    Wait(1000)
                    SetPedCoordsKeepVehicle(GarageBridge.cache.ped, coords.x, coords.y, coords.z)
                    DoScreenFadeIn(500)
                    setspawnpoint({ k = k, v = GarageZone[k], returnMenu = self.returnMenu })
                end
            }
        end
    end

    context.options[#context.options+1] = {
        title = "Edit Point",
        icon = "pen-to-square",
        onSelect = function ()
            local sp = { c = asp, v = avsp }
            local pr = spawnPoint.create(v.zones, true, sp, v.type) ---@type table<string, vector3[]|string[]>
            if not pr then
                setspawnpoint({ k = k, v = GarageZone[k], returnMenu = self.returnMenu })
                return
            end
            GarageZone[k].spawnPoint = pr.c
            GarageZone[k].spawnPointVehicle = pr.v
            utils.notify("The spawn point has been successfully set", "success", 8000)
            gzf.save(GarageZone)
            setspawnpoint({ k = k, v = GarageZone[k], returnMenu = self.returnMenu })
        end
    }
    utils.createMenu(context)
end

--- Add & Remove job
local function jobOptions(self)
    local k, v = self.k, self.v ---@type string, GarageData

    local contextJob = {
        id = "forge_contextJob",
        title = k,
        menu = self.parentMenu or "rhd:action_garage",
        onBack = function() end,
        options = {}
    }

    if v.job and type(v.job) == "table" then
        for name, grade in pairs(v.job) do
            contextJob.options[#contextJob.options+1] = {
                title = GarageBridge.locale("context.admin.job_description", name, grade),
                icon = "briefcase",
                onSelect = function()
                    local contextJob2 = {
                        id = "forge_contextJob2",
                        title = name,
                        menu = "forge_contextJob",
                        options = {
                            {
                                title = GarageBridge.locale("context.admin.delete"),
                                icon = "trash",
                                onSelect = function ()
                                    v.job[name] = nil

                                    if not next(v.job) then
                                        v.job = nil
                                    end

                                    GarageZone[k].job = v.job
                                    utils.notify(GarageBridge.locale("notify.admin.success_deleted_access"), "success")
                                    gzf.save( GarageZone )
                                    jobOptions({ k = k, v = GarageZone[k], parentMenu = self.parentMenu })
                                end
                            }
                        }
                    }
                    utils.createMenu(contextJob2)
                end
            }
        end
    end

    contextJob.options[#contextJob.options+1] = {
        title = GarageBridge.locale("context.admin.add_job"),
        icon = "plus",
        onSelect = function ()
            local input = pr_lib.inputDialog(GarageBridge.locale("input.admin.garage_access"), {
                { type = 'input', label = GarageBridge.locale("input.admin.garage_access_job"), placeholder = 'police, ambulance, etc', required = true },
                { type = 'number', label = GarageBridge.locale("input.admin.garage_access_grade_job"), required = true}
            })

            if input then
                local name, rank = input[1], input[2]
                if not v.job then v.job = {} end
                v.job[name] = rank
                GarageZone[k].job = v.job
                utils.notify(GarageBridge.locale("notify.admin.success_added_access", input[1]))
                gzf.save( GarageZone )
            end
            jobOptions({ k = k, v = GarageZone[k], parentMenu = self.parentMenu })
        end
    }

    utils.createMenu(contextJob)
end

--- Add & Remove gang
local function gangOptions(self)
    local k, v = self.k, self.v ---@type string, GarageData

    local contextGang = {
        id = "forge_contextGang",
        title = k,
        menu = self.parentMenu or "rhd:action_garage",
        onBack = function() end,
        options = {}
    }

    if v.gang and type(v.gang) == "table" then
        for name, grade in pairs(v.gang) do
            contextGang.options[#contextGang.options+1] = {
                title = GarageBridge.locale("context.admin.gang_description", name, grade),
                icon = "users",
                onSelect = function()
                    local contextGang2 = {
                        id = "forge_contextGang2",
                        title = name,
                        menu = "forge_contextGang",
                        options = {
                            {
                                title = GarageBridge.locale("context.admin.delete"),
                                icon = "trash",
                                onSelect = function ()
                                    v.gang[name] = nil

                                    if not next(v.gang) then
                                        v.gang = nil
                                    end
                                    
                                    GarageZone[k].gang = v.gang
                                    utils.notify(GarageBridge.locale("notify.admin.success_deleted_access"), "success")
                                    gzf.save( GarageZone )
                                    gangOptions({ k = k, v = GarageZone[k], parentMenu = self.parentMenu })
                                end
                            }
                        }
                    }
                    utils.createMenu(contextGang2)
                end
            }
        end
    end

    contextGang.options[#contextGang.options+1] = {
        title = GarageBridge.locale("context.admin.add_gang"),
        icon = "plus",
        onSelect = function ()
            local input = pr_lib.inputDialog(GarageBridge.locale("input.admin.garage_access"), {
                { type = 'input', label = GarageBridge.locale("input.admin.garage_access_gang"), placeholder = 'ballas, vagos, etc', required = true },
                { type = 'number', label = GarageBridge.locale("input.admin.garage_access_grade_gang"), required = true}
            })

            if input then
                if not v.gang then v.gang = {} end
                v.gang[input[1]] = tonumber(input[2])
                GarageZone[k].gang = v.gang
                utils.notify(GarageBridge.locale("notify.admin.success_added_access", input[1]))
                gzf.save( GarageZone )
            end
            gangOptions({ k = k, v = GarageZone[k], parentMenu = self.parentMenu })
        end
    }

    utils.createMenu(contextGang)
end

local function setVehicles(garage)
    local key = garage.index
    local value = garage.value

    local vehicles = exports.qbx_core:GetVehiclesByHash()

    local options = {}
    for k, v in pairs(vehicles) do
        options[#options + 1] = {
            label = v.name,
            value = v.model
        }
    end

    if value.vehicles then
        for k, v in pairs(value.vehicles) do
            for k2, v2 in pairs(options) do
                if v == v2.value then
                    options[k2].selected = true
                end
            end
        end
    end

    for k, v in pairs(options) do
        if v.selected then
            options[k].icon = "check"
        end
    end

    table.sort(options, function(a, b) return a.label < b.label end)

    if not value.vehicles then value.vehicles = {} end

    local input = pr_lib.inputDialog("Carros da Garagem", {
        { type = "multi-select", label = 'Lista', placeholder = 'Selecionar', options = options, default = value.vehicles ,searchable = true, required = false }
    })

    if input then
        if not value.vehicles then value.vehicles = {} end
        value.vehicles = input[1] or {}
        GarageZone[key].vehicles = value.vehicles
        utils.notify("Lista de Veículos alterada com sucesso!", "success", 10000)
        gzf.save( GarageZone )
    end
    returnToContext(garage.returnMenu)
end

local function editGarageSettings(args)
    local k = args.k
    local v = args.v

    local function reopenSettings()
        editGarageSettings({ k = k, v = GarageZone[k], parentMenu = args.parentMenu })
    end

    local context = {
        id = "rhd:edit_settings_" .. k,
        title = "Configurações: " .. k,
        menu = args.parentMenu or "rhd:action_garage",
        options = {
            {
                title = "Garagem de Apreensão (Impound): " .. (v.impound and "ATIVADO" or "DESATIVADO"),
                icon = "building-shield",
                onSelect = function()
                    GarageZone[k].impound = not v.impound
                    gzf.save(GarageZone)
                    reopenSettings()
                    utils.notify("Configuração de apreensão alterada!", "success")
                end
            },
            {
                title = "Garagem Compartilhada: " .. (v.shared and "ATIVADO" or "DESATIVADO"),
                icon = "people-arrows",
                onSelect = function()
                    GarageZone[k].shared = not v.shared
                    gzf.save(GarageZone)
                    reopenSettings()
                    utils.notify("Configuração de compartilhamento alterada!", "success")
                end
            },
            {
                title = "Persistir Veículos: " .. (v.persist and "ATIVADO" or "DESATIVADO"),
                icon = "recycle",
                onSelect = function()
                    local newPersist = not v.persist
                    GarageZone[k].persist = newPersist
                    if newPersist then
                        GarageZone[k].interaction = nil
                        notifyPersistentOpeningIgnored()
                    end
                    gzf.save(GarageZone)
                    reopenSettings()
                    utils.notify("Configuração de persistência alterada!", "success")
                end
            },
            {
                title = "Categorias de Veículos",
                icon = "tags",
                description = "Defina quais tipos de veículos podem ser estacionados aqui.",
                onSelect = function()
                    local currentTypes = {}
                    if type(v.type) == "table" then
                        for _, val in ipairs(v.type) do
                            currentTypes[val] = true
                        end
                    elseif type(v.type) == "string" then
                        currentTypes[v.type] = true
                    end

                    local typeOptions = {
                        { value = "car", label = "Carros" },
                        { value = "boat", label = "Barcos" },
                        { value = "helicopter", label = "Helicópteros" },
                        { value = "planes", label = "Aviões" },
                        { value = "motorcycle", label = "Motocicletas" },
                        { value = "cycles", label = "Bicicletas" }
                    }

                    local input = pr_lib.inputDialog("Editar Categorias de Veículos", {
                        { type = "multi-select", label = "Categorias Permitidas", options = typeOptions, default = type(v.type) == "table" and v.type or {v.type}, required = true }
                    })

                    if input and input[1] then
                        GarageZone[k].type = input[1]
                        gzf.save(GarageZone)
                        utils.notify("Categorias de veículos atualizadas!", "success")
                    end
                    reopenSettings()
                end
            },
            {
                title = "Método de Abertura",
                icon = "door-open",
                description = "Como os jogadores abrem ou interagem com esta garagem.",
                onSelect = function()
                    if v.persist or (v.ipl and v.ipl.enabled) then
                        GarageZone[k].interaction = nil
                        gzf.save(GarageZone)
                        notifyPersistentOpeningIgnored()
                        reopenSettings()
                        return
                    end

                    local currentMethod = "keypressed"
                    if type(v.interaction) == "table" then
                        currentMethod = "targetped"
                    else
                        currentMethod = v.interaction or "keypressed"
                    end

                    local input = pr_lib.inputDialog("Método de Abertura", {
                        { type = "select", label = "Escolha o método", options = {
                            { value = "radial", label = "Usando Radial Menu" },
                            { value = "keypressed", label = "Usando Tecla E" },
                            { value = "targetped", label = "Usando NPC com Target" }
                        }, default = currentMethod, required = true }
                    })

                    if input and input[1] then
                        local newMethod = input[1]
                        if newMethod == "targetped" then
                            local spawnedPedCoords = pedcreator.start(v.zones)
                            if spawnedPedCoords then
                                GarageZone[k].interaction = spawnedPedCoords
                                gzf.save(GarageZone)
                                utils.notify("Método de abertura atualizado para NPC!", "success")
                            else
                                utils.notify("Criação de NPC cancelada.", "error")
                            end
                        else
                            GarageZone[k].interaction = newMethod
                            gzf.save(GarageZone)
                            utils.notify("Método de abertura atualizado com sucesso!", "success")
                        end
                    end
                    reopenSettings()
                end
            }
        }
    }
    utils.createMenu(context)
end

local function openGarageLocationMenu(self)
    if self.isIpl then
        iplOptions({ k = self.k, v = self.v })
        return
    end

    local contextId = "rhd:garage_location_" .. self.k
    utils.createMenu({
        id = contextId,
        title = "Localizacao: " .. self.k,
        menu = "rhd:action_garage",
        options = {
            {
                title = "Editar Area da Garagem",
                icon = "draw-polygon",
                description = "Refaz a PolyZone usada por esta garagem.",
                onSelect = changeLocation,
                args = { label = self.k, k = self.k, v = self.v, returnMenu = contextId }
            }
        }
    })
end

local function teleportToStoredGarageVehicle(self)
    teleportToIplPoint(self)
    if self.garage then
        TriggerServerEvent('forge_garage:server:enterPersistentZone', self.garage)
    end
end

local function listStoredGarageVehicles(self)
    CreateThread(function()
        local response = GarageBridge.callback.await(
            'forge_garage:cb_server:getPersistentGarageVehicles',
            false,
            self.k
        )

        if not response or response.allowed ~= true then
            utils.notify("Acesso administrativo negado.", "error")
            returnToContext(self.parentMenu)
            return
        end

        local contextId = "rhd:stored_vehicles_" .. self.k
        local vehicles = response.vehicles or {}
        local options = {}
        local ipl = self.v and self.v.ipl
        local isIpl = ipl and ipl.enabled

        if #vehicles == 0 then
            options[1] = {
                title = "Nenhum veiculo estacionado",
                icon = "circle-info",
                description = "Banco de dados sem veiculos persistentes nesta garagem.",
                disabled = true,
            }
        end

        for i = 1, #vehicles do
            local vehicle = vehicles[i]
            local coords = vehicle.coords
            local teleportCoords = coords and vec4(
                tonumber(coords.x) or 0.0,
                tonumber(coords.y) or 0.0,
                tonumber(coords.z) or 0.0,
                tonumber(coords.w or coords.h) or 0.0
            ) or nil
            local status = vehicle.rendered and "Renderizado"
                or vehicle.spawned and "Entidade em bucket privado"
                or "Somente no banco"
            local runtime = vehicle.spawned
                and (" | NetID: %s | Bucket: %s/%s"):format(
                    vehicle.netId or "?",
                    vehicle.bucket or "?",
                    vehicle.expectedBucket or "?"
                )
                or ""

            options[#options + 1] = {
                title = vehicle.label or vehicle.vehicle or ("Veiculo " .. i),
                icon = vehicle.rendered and "car" or vehicle.spawned and "archive" or "database",
                description = ("Placa: %s | %s%s"):format(vehicle.plate or "?", status, runtime),
                disabled = teleportCoords == nil,
                onSelect = teleportToStoredGarageVehicle,
                args = {
                    garage = self.k,
                    coords = teleportCoords,
                    bucket = isIpl and (ipl.bucket or 0) or 0,
                    ipl = isIpl and ipl.model or nil,
                    unloadIpl = not isIpl,
                    returnMenu = contextId,
                },
            }
        end

        utils.createMenu({
            id = contextId,
            title = ("Veiculos Estacionados: %s (%s)"):format(self.k, #vehicles),
            menu = self.parentMenu,
            options = options,
        })
    end)
end

local function openGarageVehicleMenu(self)
    local contextId = "rhd:garage_vehicles_" .. self.k
    local options = {}

    if self.v.persist then
        options[#options + 1] = {
            title = "Veiculos Estacionados",
            icon = "list",
            description = "Lista banco, estado renderizado e teleporte por veiculo.",
            onSelect = listStoredGarageVehicles,
            args = { k = self.k, v = self.v, parentMenu = contextId },
        }
    end

    options[#options + 1] = {
        title = self.isIpl and "Vagas IPL" or "Locais de Spawn",
        icon = self.isIpl and "square-parking" or "location-dot",
        description = self.isIpl and "Crie e visualize as vagas internas." or "Configure os pontos de spawn da garagem.",
        onSelect = self.isIpl and listIplParkingSpots or setspawnpoint,
        args = { k = self.k, v = self.v, parentMenu = contextId, returnMenu = contextId },
    }

    options[#options + 1] = {
        title = "Definir Veiculos",
        icon = "car",
        description = "Gerencia os modelos permitidos nesta garagem.",
        onSelect = setVehicles,
        args = { index = self.k, value = self.v, returnMenu = contextId },
    }

    utils.createMenu({
        id = contextId,
        title = "Vagas e Veiculos: " .. self.k,
        menu = "rhd:action_garage",
        options = options,
    })
end

local function openGarageConfigurationMenu(self)
    local contextId = "rhd:garage_config_" .. self.k
    utils.createMenu({
        id = contextId,
        title = "Configuracoes: " .. self.k,
        menu = "rhd:action_garage",
        options = {
            {
                title = GarageBridge.locale("context.admin.blip_setting"),
                icon = "map",
                onSelect = setBlip,
                args = { k = self.k, v = self.v, parentMenu = contextId }
            },
            {
                title = GarageBridge.locale("context.admin.options_changelabel"),
                icon = "pen-to-square",
                onSelect = changeGarageLabel,
                args = { k = self.k, v = self.v, returnMenu = contextId }
            },
            {
                title = "Regras da Garagem",
                icon = "sliders",
                description = "Tipo, persistencia, categorias e metodo de interacao.",
                onSelect = editGarageSettings,
                args = { k = self.k, v = self.v, parentMenu = contextId }
            }
        }
    })
end

local function openGaragePermissionsMenu(self)
    local contextId = "rhd:garage_permissions_" .. self.k
    local options = {}

    if not self.v.impound and not self.v.gang then
        options[#options + 1] = {
            title = GarageBridge.locale("context.admin.job_title"),
            icon = "briefcase",
            onSelect = jobOptions,
            args = { k = self.k, v = self.v, parentMenu = contextId }
        }
    end

    if not self.v.impound and not self.v.job then
        options[#options + 1] = {
            title = GarageBridge.locale("context.admin.gang_title"),
            icon = "users",
            onSelect = gangOptions,
            args = { k = self.k, v = self.v, parentMenu = contextId }
        }
    end

    if #options == 0 then
        options[1] = {
            title = "Nenhuma permissao compativel",
            icon = "circle-info",
            disabled = true
        }
    end

    utils.createMenu({
        id = contextId,
        title = "Permissoes: " .. self.k,
        menu = "rhd:action_garage",
        options = options
    })
end

local function openGarageAdminMenu(self)
    local contextId = "rhd:garage_admin_" .. self.k
    local location = self.isIpl
        and self.v.ipl and ((self.v.ipl.entries and self.v.ipl.entries[1] and self.v.ipl.entries[1].coords) or self.v.ipl.entry)
        or self.v.zones and self.v.zones.points and self.v.zones.points[1]

    utils.createMenu({
        id = contextId,
        title = "Acoes Administrativas: " .. self.k,
        menu = "rhd:action_garage",
        options = {
            {
                title = GarageBridge.locale("context.admin.tptoloc"),
                icon = "location-dot",
                onSelect = self.isIpl and teleportToIplPoint or teleportToLocation,
                args = self.isIpl
                    and { coords = location, bucket = 0, unloadIpl = true, returnMenu = contextId }
                    or { coords = location, returnMenu = contextId }
            },
            {
                title = GarageBridge.locale("context.admin.options_delete"),
                icon = "trash",
                onSelect = delete,
                args = { label = self.k, returnMenu = "rhd:list_garage" }
            }
        }
    })
end

local function openGarageActionsMenu(self)
    utils.createMenu({
        id = "rhd:action_garage",
        title = self.k,
        menu = "rhd:list_garage",
        options = {
            {
                title = self.isIpl and "IPL, Acessos e Elevadores" or "Area e Acesso",
                icon = self.isIpl and "building" or "draw-polygon",
                description = self.isIpl and "Modelo, entradas, elevadores, vagas e previews." or "Localizacao e area da PolyZone.",
                onSelect = openGarageLocationMenu,
                args = { k = self.k, v = self.v, isIpl = self.isIpl }
            },
            {
                title = "Vagas e Veiculos",
                icon = "car",
                description = "Pontos de estacionamento e modelos permitidos.",
                onSelect = openGarageVehicleMenu,
                args = { k = self.k, v = self.v, isIpl = self.isIpl }
            },
            {
                title = "Configuracoes",
                icon = "sliders",
                description = "Blip, rotulo e regras gerais da garagem.",
                onSelect = openGarageConfigurationMenu,
                args = { k = self.k, v = self.v }
            },
            {
                title = "Permissoes",
                icon = "user-shield",
                description = "Acessos por trabalho ou gangue.",
                onSelect = openGaragePermissionsMenu,
                args = { k = self.k, v = self.v }
            },
            {
                title = "Acoes Administrativas",
                icon = "screwdriver-wrench",
                description = "Teleportar para a garagem ou deletar o cadastro.",
                onSelect = openGarageAdminMenu,
                args = { k = self.k, v = self.v, isIpl = self.isIpl }
            }
        }
    })

    return true
end

listGarage = function()
    local context = {
        id = 'rhd:list_garage',
        title = GarageBridge.locale("context.admin.listgarage_title"),
        menu = 'menu_gerencial',
        options = {
            {
                title = GarageBridge.locale('context.admin.addnewgarage'),
                icon = 'plus',
                onSelect = createGarageIpl
            }
        }
    }

    for k, v in pairs(GarageZone) do
        local isIpl = v.ipl and v.ipl.enabled
        context.options[#context.options + 1] = {
            title = k,
            icon = isIpl and "building" or "warehouse",
            description = GarageBridge.locale("context.admin.listgarage_description", v.impound and "Impound" or v.shared and "Shared" or "Public", utils.garageType(v.type)),
            onSelect = function ()
                if openGarageActionsMenu({ k = k, v = v, isIpl = isIpl }) then return end

                local context2 = {
                    id = "rhd:action_garage",
                    title = k,
                    menu = "rhd:list_garage",
                    onBack = function()

                    end,
                    options = {
                        {
                            title = GarageBridge.locale("context.admin.options_delete"),
                            icon = "trash",
                            onSelect = delete,
                            args = {
                                label = k,
                                returnMenu = "rhd:list_garage"
                            }
                        },
                        {
                            title = GarageBridge.locale("context.admin.blip_setting"),
                            icon = "map",
                            onSelect = setBlip,
                            args = {
                                k = k,
                                v = v,
                                returnMenu = "rhd:action_garage"
                            }
                        },
                        {
                            title = isIpl and "Configurar Entrada/Saida IPL" or GarageBridge.locale("context.admin.options_changelocation"),
                            icon = "location-dot",
                            onSelect = isIpl and iplOptions or changeLocation,
                            args = {
                                label = k,
                                k = k,
                                v = v,
                                returnMenu = "rhd:action_garage"
                            }
                        },
                        {
                            title = GarageBridge.locale("context.admin.tptoloc"),
                            icon = "location-dot",
                            onSelect = teleportToLocation,
                            args = {
                                coords = isIpl and v.ipl and ((v.ipl.entries and v.ipl.entries[1] and v.ipl.entries[1].coords) or v.ipl.entry) or v.zones and v.zones.points and v.zones.points[1],
                                returnMenu = "rhd:action_garage"
                            }
                        },
                        {
                            title = GarageBridge.locale("context.admin.options_changelabel"),
                            icon = "pen-to-square",
                            onSelect = changeGarageLabel,
                            args = {
                                k = k,
                                v = v,
                                returnMenu = "rhd:action_garage"
                            }
                        },
                        {
                            title = isIpl and "Vagas IPL" or "Locais de Spawn",
                            icon = isIpl and "square-parking" or "location-dot",
                            onSelect = isIpl and listIplParkingSpots or setspawnpoint,
                            args = {
                                k = k,
                                v = v,
                                returnMenu = "rhd:action_garage"
                            }
                        },
                        {
                            title = "Definir Veículos",
                            icon = "car",
                            onSelect = setVehicles,
                            args = {
                                index = k,
                                value = v,
                                returnMenu = "rhd:action_garage"
                            }
                        },
                        {
                            title = "Editar Configurações",
                            icon = "sliders",
                            description = "Altere o tipo, persistência, categorias e método de interação da garagem.",
                            onSelect = editGarageSettings,
                            args = {
                                k = k,
                                v = v
                            }
                        }
                    }
                }

                if not v.impound and not v.gang then
                    context2.options[#context2.options+1] = {
                        title = GarageBridge.locale("context.admin.job_title"),
                        icon = "briefcase",
                        onSelect = jobOptions,
                        args = {
                            k = k,
                            v = v
                        }
                    }
                end

                if not v.impound and not v.job then
                    context2.options[#context2.options+1] = {
                        title = GarageBridge.locale("context.admin.gang_title"),
                        icon = "users",
                        onSelect = gangOptions,
                        args = {
                            k = k,
                            v = v
                        }
                    }
                end
                utils.createMenu(context2)
            end
        }
    end
    utils.createMenu(context)
end

local playerLoaded = false

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    playerLoaded = true
    gzf.refresh()
    GarageBridge.print.info("Garage data has been successfully loaded (OnPlayerLoaded)")
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    playerLoaded = false
end)

CreateThread(function ()
    while not pr_lib.framework.IsPlayerLoaded() do
        Wait(1000)
    end
    playerLoaded = true
    gzf.refresh()
    GarageBridge.print.info("Garage data has been successfully loaded")
end)

RegisterNetEvent('forge_garage:client:syncConfig', function(newconfig)
    GarageZone = newconfig
    gzf.refresh()
end)

RegisterNetEvent("forge_garage:client:garagelist", listGarage)
