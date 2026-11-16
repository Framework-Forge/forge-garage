local function admin(src)
    if IsPlayerAceAllowed(src, 'group.admin') or IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'command.garagelist') then return true end
    local fn = pr_lib.framework.HasPermission
    if type(fn) ~= 'function' then return false end
    local ok, allowed = pcall(fn, src, { 'god', 'admin' })
    return ok and allowed == true
end
local function groupAllowed(requirement, group)
    if not requirement then return true end
    if type(group) ~= 'table' then return false end
    local minimum = requirement[group.name]
    local grade = type(group.grade) == 'table' and group.grade.level or group.grade
    return minimum ~= nil and (tonumber(grade) or 0) >= (tonumber(minimum) or 0)
end
local function access(src, name)
    local garage = type(name) == 'string' and GarageZone[name]
    local ipl = garage and garage.ipl
    local manager = ipl and GarageVisual.manager(ipl.manager)
    if not ipl or not ipl.enabled or not manager or not GarageVisual.catalog(ipl) then return nil, 'Gerenciador indisponível.' end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetPlayerRoutingBucket(src) ~= (ipl.bucket or 0) then return nil, 'Entre na garagem para usar o painel.' end
    local pos, target = GetEntityCoords(ped), manager.coords
    if (pos.x-target.x)^2 + (pos.y-target.y)^2 + (pos.z-target.z)^2 > (manager.radius + 1.0)^2 then
        return nil, 'Aproxime-se do gerenciador visual.'
    end
    if admin(src) then return ipl end
    local player = pr_lib.framework.GetPlayer(src)
    local data = player and (player.PlayerData or player)
    if not data or not groupAllowed(garage.job, data.job) or not groupAllowed(garage.gang, data.gang) then return nil, 'Sem acesso a esta garagem.' end
    if manager.access == 'residential' then
        if not pr_lib.housing.getProvider() then return nil, 'Sistema residencial indisponível.' end
        local ok, allowed = pcall(pr_lib.housing.IsOwner, src, manager.propertyId)
        if not ok or not allowed then return nil, 'Somente moradores autorizados podem alterar este interior.' end
    end
    return ipl
end
local function reply(ipl)
    return { success = true, model = ipl.model, visual = GarageVisual.normalize(ipl, ipl.visual or {}), revision = ipl.visualRevision or 0 }
end
local function persist(name, field, value, revision)
    -- Save first. A failed disk write must not publish settings that will disappear on restart.
    local snapshot = json.decode(json.encode(GarageZone))
    snapshot[name].ipl[field] = value
    if revision then snapshot[name].ipl.visualRevision = revision end
    if not SaveResourceFile(GetCurrentResourceName(), 'data/garages.json', json.encode(snapshot), -1) then return false end
    GarageZone[name].ipl[field] = value
    if revision then GarageZone[name].ipl.visualRevision = revision end
    if field == 'manager' then
        TriggerClientEvent('forge_garage:client:syncConfig', -1, GarageZone)
    else
        TriggerClientEvent('forge_garage:client:iplVisual', -1, name, value, revision)
    end
    return true
end
GarageBridge.callback.register('forge_garage:visual:open', function(src, name)
    local ipl, reason = access(src, name)
    return ipl and reply(ipl) or { success = false, message = reason }
end)
GarageBridge.callback.register('forge_garage:visual:save', function(src, name, values, revision)
    local ipl, reason = access(src, name)
    if not ipl then return { success = false, message = reason } end
    if revision ~= (ipl.visualRevision or 0) then return { success = false, message = 'Outro jogador alterou o visual. Reabra o painel.' } end
    local normalized = GarageVisual.normalize(ipl, values, true)
    if not normalized then return { success = false, message = 'Opções de visual inválidas.' } end
    if not persist(name, 'visual', normalized, (ipl.visualRevision or 0) + 1) then return { success = false, message = 'Não foi possível salvar o visual.' } end
    return reply(ipl)
end)
GarageBridge.callback.register('forge_garage:visual:properties', function(src)
    if not admin(src) then return {} end
    if not pr_lib.housing.getProvider() then return {} end
    return pr_lib.database.query('SELECT property_id, street FROM properties ORDER BY property_id') or {}
end)
GarageBridge.callback.register('forge_garage:visual:configure', function(src, name, manager)
    if not admin(src) then return { success = false, message = 'Acesso administrativo necessário.' } end
    local garage = type(name) == 'string' and GarageZone[name]
    if not garage or not garage.ipl or not garage.ipl.enabled then return { success = false, message = 'Garagem IPL inválida.' } end
    local value
    if manager ~= false then
        value = GarageVisual.manager(manager)
        if not value or not GarageVisual.catalog(garage.ipl) then return { success = false, message = 'Ponto inválido ou modelo sem personalização cadastrada.' } end
        if value.access == 'residential' then
            if not pr_lib.housing.getProvider() or not pr_lib.database.scalar('SELECT property_id FROM properties WHERE property_id = ?', { value.propertyId }) then
                return { success = false, message = 'Imóvel não encontrado.' }
            end
        end
    end
    local ok = persist(name, 'manager', value)
    return { success = ok, message = ok and 'Gerenciador atualizado.' or 'Não foi possível salvar o ponto.' }
end)
