GarageVisualClient = {}
local preview
local layoutNpc, npcSignature, npcGeneration, npcEditing = nil, nil, 0, false
local npcLoading, nextNpcAttempt, lastNpcError = false, 0, nil
local targetName = 'forge_garage:layout_npc'
function GarageVisualClient.clearNpc()
    npcGeneration = npcGeneration + 1
    npcSignature, npcLoading, nextNpcAttempt = nil, false, 0
    if layoutNpc then
        pcall(pr_lib.target.removeLocalEntity, layoutNpc, targetName)
        if DoesEntityExist(layoutNpc) then DeleteEntity(layoutNpc) end
        layoutNpc = nil
    end
end
function GarageVisualClient.syncNpc()
    local name = gzf.activeGarage
    local garage = name and GarageZone[name]
    local ipl = garage and garage.ipl
    local manager = ipl and GarageVisual.manager(ipl.manager)
    -- Interior readiness controls decor, not the lifetime of this frozen local ped.
    if npcEditing or not ipl or not ipl.enabled or not manager or not GarageVisual.catalog(ipl) then
        if npcSignature or layoutNpc then GarageVisualClient.clearNpc() end
        return
    end
    local c = manager.coords
    local signature = table.concat({name, manager.model, c.x, c.y, c.z, manager.heading, manager.radius}, ':')
    if npcSignature == signature then
        if npcLoading or (layoutNpc and DoesEntityExist(layoutNpc)) or GetGameTimer() < nextNpcAttempt then return end
    end
    GarageVisualClient.clearNpc()
    npcSignature, npcLoading = signature, true
    local generation = npcGeneration
    CreateThread(function()
        local hash = joaat(manager.model)
        local ok, reason = pcall(function()
            if not IsModelInCdimage(hash) or not IsModelAPed(hash) then error('modelo de NPC inválido: ' .. manager.model) end
            GarageBridge.requestModel(hash, 5000)
            if generation ~= npcGeneration or gzf.activeGarage ~= name then return end
            if not HasModelLoaded(hash) then error('modelo ainda não carregado: ' .. manager.model) end
            local entity = CreatePed(4, hash, c.x, c.y, c.z, manager.heading, false, true)
            if not entity or entity == 0 or not DoesEntityExist(entity) then error('CreatePed não criou o NPC') end
            layoutNpc = entity
            SetEntityAsMissionEntity(entity, true, true)
            -- DevTools uses noOffset=false for peds. Keep its native model-height
            -- adjustment; NoOffset would put the ped's origin at floor height.
            pr_lib.fivem.streaming.setEntityTransform(entity, c, manager.heading, {
                noOffset = false,
                placeProperly = false,
                placementType = 'ped',
            })
            FreezeEntityPosition(entity, true)
            SetEntityInvincible(entity, true)
            SetBlockingOfNonTemporaryEvents(entity, true)
            SetPedCanRagdoll(entity, false)
            pr_lib.target.addLocalEntity(entity, {{
                name = targetName, label = 'Painel de layout da garagem', icon = 'fas fa-palette', distance = manager.radius,
                canInteract = function() return gzf.activeGarage == name and not IsPedInAnyVehicle(PlayerPedId(), false) end,
                onSelect = function() GarageVisualClient.open(name) end,
            }})
        end)
        SetModelAsNoLongerNeeded(hash)
        if generation ~= npcGeneration then return end
        npcLoading = false
        if not ok then
            if layoutNpc then
                pcall(pr_lib.target.removeLocalEntity, layoutNpc, targetName)
                if DoesEntityExist(layoutNpc) then DeleteEntity(layoutNpc) end
                layoutNpc = nil
            end
            nextNpcAttempt = GetGameTimer() + 5000
            if lastNpcError ~= tostring(reason) then
                lastNpcError = tostring(reason)
                print(('[forge-garage] NPC de layout [%s]: %s; nova tentativa em 5s'):format(name, reason))
            end
        else
            lastNpcError = nil
        end
    end)
end
function GarageVisualClient.editNpc(enabled)
    npcEditing = enabled == true
    GarageVisualClient.syncNpc()
end
local appliedVisualKey
local function apply(ipl, values)
    local catalog = GarageVisual.catalog(ipl)
    if not catalog or not IsInteriorReady(catalog.interiorId) then appliedVisualKey = nil; return end
    local normalized = GarageVisual.normalize(ipl, values or {})
    local parts = { tostring(catalog.interiorId) }
    for _, field in ipairs(catalog.fields) do parts[#parts + 1] = tostring(normalized[field.key]) end
    local key = table.concat(parts, ':')
    local matches = appliedVisualKey == key
    for _, field in ipairs(catalog.fields) do
        local selected = field.options[normalized[field.key]].set
        for _, option in ipairs(field.options) do
            if IsInteriorEntitySetActive(catalog.interiorId, option.set) ~= (option.set == selected) then matches = false end
        end
    end
    if matches then return end
    local changed = false
    for _, field in ipairs(catalog.fields) do
        local selected = field.options[normalized[field.key]]
        for _, option in ipairs(field.options) do
            if option.set ~= selected.set and IsInteriorEntitySetActive(catalog.interiorId, option.set) then
                DeactivateInteriorEntitySet(catalog.interiorId, option.set)
                changed = true
            end
        end
        if not IsInteriorEntitySetActive(catalog.interiorId, selected.set) then
            ActivateInteriorEntitySet(catalog.interiorId, selected.set)
            changed = true
        end
        if selected.color and appliedVisualKey ~= key then
            SetInteriorEntitySetColor(catalog.interiorId, selected.set, selected.color)
            changed = true
        end
    end
    appliedVisualKey = key
    if changed then RefreshInterior(catalog.interiorId) end
end
function GarageVisualClient.apply(name)
    local garage = name and GarageZone[name]
    if garage and garage.ipl then apply(garage.ipl, garage.ipl.visual) end
end
function GarageVisualClient.reset(name)
    local garage = name and GarageZone[name]
    if garage and garage.ipl then apply(garage.ipl, {}) end
end
function GarageVisualClient.cancel()
    if not preview then return end
    local name = preview.name
    preview = nil
    if gzf.activeGarage == name then GarageVisualClient.apply(name) end
end
local function nearManager(name)
    if gzf.activeGarage ~= name then return false end
    local garage = GarageZone[name]
    local manager = garage and garage.ipl and garage.ipl.manager
    if not manager then return false end
    local pos, target = GetEntityCoords(PlayerPedId()), manager.coords
    return (pos.x-target.x)^2 + (pos.y-target.y)^2 + (pos.z-target.z)^2 <= (manager.radius + 1.0)^2
end
local show
show = function(session)
    if not nearManager(session.name) then return end
    local ipl = GarageZone[session.name].ipl
    local catalog = GarageVisual.catalog(ipl)
    if not catalog then return end
    if ipl.model ~= session.model or (ipl.visualRevision or 0) ~= session.revision
        or not GarageVisual.normalize(ipl, session.draft, true) then
        utils.notify('A configuração mudou. Reabra o painel de layout.', 'inform')
        if session.parentMenu then pr_lib.showContext(session.parentMenu) end
        return
    end
    preview = session
    apply(ipl, session.draft)
    local options = {}
    for _, field in ipairs(catalog.fields) do
        options[#options+1] = {
            title = field.label,
            description = field.options[session.draft[field.key]].label,
            icon = field.key == 'color' and 'palette' or 'warehouse',
            onSelect = function()
                local choices = {}
                for index, choice in ipairs(field.options) do choices[#choices+1] = { value = index, label = choice.label } end
                local input = pr_lib.inputDialog(field.label, {
                    { type = 'select', label = field.label, options = choices, default = session.draft[field.key], required = true }
                })
                local selected = input and tonumber(input[1])
                if selected and field.options[selected] then session.draft[field.key] = selected end
                show(session)
            end,
        }
    end
    options[#options+1] = {
        title = 'Restaurar padrão no preview', icon = 'rotate-left',
        onSelect = function() session.draft = GarageVisual.normalize(ipl, {}); show(session) end,
    }
    options[#options+1] = {
        title = 'Salvar aparência', icon = 'floppy-disk',
        description = 'Aplica a todos nesta garagem e mantém após reiniciar.',
        onSelect = function()
            local result = GarageBridge.callback.await('forge_garage:visual:save', false, session.name, session.draft, session.revision)
            if not result or not result.success then return utils.notify(result and result.message or 'Não foi possível salvar.', 'error') end
            ipl.visual, ipl.visualRevision = result.visual, result.revision
            GarageVisualClient.apply(session.name)
            utils.notify('Aparência da garagem salva.', 'success')
            if session.parentMenu then pr_lib.showContext(session.parentMenu) end
        end,
    }
    options[#options+1] = { title = 'Cancelar alterações', icon = 'xmark', onSelect = function()
        GarageVisualClient.cancel()
        if session.parentMenu then pr_lib.showContext(session.parentMenu) end
    end }
    utils.createMenu({ id = 'forge_garage:visual', title = 'Visual — ' .. session.name, options = options, menu = session.parentMenu, onBack = GarageVisualClient.cancel, onExit = GarageVisualClient.cancel })
end
function GarageVisualClient.open(name, parentMenu)
    if not nearManager(name) then
        utils.notify('Entre no IPL e aproxime-se do ponto do painel.', 'error')
        if parentMenu then pr_lib.showContext(parentMenu) end
        return
    end
    local result = GarageBridge.callback.await('forge_garage:visual:open', false, name)
    if not result or not result.success then return utils.notify(result and result.message or 'Painel indisponível.', 'error') end
    local ipl = GarageZone[name] and GarageZone[name].ipl
    if not ipl or ipl.model ~= result.model then return end
    ipl.visual, ipl.visualRevision = result.visual, result.revision
    show({ name = name, model = result.model, draft = GarageVisual.normalize(ipl, result.visual, true), revision = result.revision, parentMenu = parentMenu })
end
-- Passengers may enter without the local garage entry action. Resolve only
-- unambiguous interiors; never choose between garages sharing one IPL.
local function currentVisualGarage()
    if gzf.activeGarage then return gzf.activeGarage end
    local interior = GetInteriorFromEntity(PlayerPedId())
    if not interior or interior == 0 then return end
    local name
    for candidate, garage in pairs(GarageZone) do
        local catalog = garage.ipl and GarageVisual.catalog(garage.ipl)
        if catalog and catalog.interiorId == interior then
            if name then return end
            name = candidate
        end
    end
    return name
end
RegisterNetEvent('forge_garage:client:iplVisual', function(name, values, revision)
    local garage = GarageZone[name]
    if not garage or not garage.ipl then return end
    local normalized = GarageVisual.normalize(garage.ipl, values, true)
    if not normalized then return end
    garage.ipl.visual, garage.ipl.visualRevision = normalized, revision
    if preview and preview.name == name then
        GarageVisualClient.cancel()
        pr_lib.hideContext(false)
        utils.notify('O visual foi atualizado. Reabra o painel para continuar.', 'inform')
    end
    if currentVisualGarage() == name then GarageVisualClient.apply(name) end
end)
CreateThread(function()
    local enteredGarage, enteredInterior
    while true do
        Wait(500)
        local name = currentVisualGarage()
        local garage = name and GarageZone[name]
        local catalog = garage and garage.ipl and GarageVisual.catalog(garage.ipl)
        local interior = GetInteriorFromEntity(PlayerPedId())
        if catalog and catalog.interiorId == interior and IsInteriorReady(interior) then
            -- Observe entry/readiness only. Never reapply decor on a timer.
            if enteredGarage ~= name or enteredInterior ~= interior then
                enteredGarage, enteredInterior = name, interior
                if not preview then GarageVisualClient.apply(name) end
            end
        elseif not catalog or catalog.interiorId ~= interior then
            enteredGarage, enteredInterior = nil, nil
        end
        GarageVisualClient.syncNpc()
        if preview and not nearManager(preview.name) then
            GarageVisualClient.cancel()
            pr_lib.hideContext(false)
        end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then GarageVisualClient.cancel(); GarageVisualClient.clearNpc() end
end)
