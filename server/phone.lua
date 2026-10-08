-- Read-only phone view. Ownership is checked on every list/detail/route request.
local db = pr_lib.database
local function clean(value)
    if type(value) ~= 'string' or #value > 50 then return nil end
    local plate = value:upper():gsub('%s+', '')
    return plate ~= '' and plate or nil
end
local function number(value)
    local n = tonumber(value)
    if n and n == n and math.abs(n) < math.huge then return n end
end
local function point(value)
    if not value then return nil end
    local kind = type(value)
    if kind ~= 'table' and kind ~= 'vector3' and kind ~= 'vector4' then return nil end
    local x, y, z = number(value.x), number(value.y), number(value.z)
    if x and y and z then return {x=x,y=y,z=z} end
end
local function entry(garage)
    if type(garage) ~= 'table' then return nil end
    if garage.ipl and garage.ipl.enabled then
        for _, p in ipairs(garage.ipl.entries or {}) do
            local coords = point(p.coords or p)
            if coords and p.mode ~= 'vehicle' then return coords end
        end
        return point(garage.ipl.entry) or point(garage.ipl.entries and garage.ipl.entries[1] and garage.ipl.entries[1].coords)
    end
    return point(type(garage.interaction) == 'table' and garage.interaction.coords)
        or point(garage.takeVehicle) or point(garage.coords)
        or point(garage.zones and garage.zones.points and garage.zones.points[1])
        or point(garage.spawnPoint and garage.spawnPoint[1])
end
local function location(name)
    return GarageZone[name] or (Config.HouseGarages or {})[name]
end
local function nearestDepot(src, vehicleType)
    local origin = point(GetEntityCoords(GetPlayerPed(src)))
    local best, distance
    for name, garage in pairs(GarageZone) do
        local compatible = not garage.type or #garage.type == 0
        for _, kind in ipairs(garage.type or {}) do if kind == vehicleType then compatible = true end end
        if garage.impound and compatible and not garage.job and not garage.gang then
            local coords = entry(garage)
            if coords then
                local d = origin and ((coords.x-origin.x)^2 + (coords.y-origin.y)^2) or 0
                if not best or d < distance or (d == distance and name < best.label) then
                    best, distance = {kind='insurance',label=name,coords=coords,action='Ir até o seguro'}, d
                end
            end
        end
    end
    return best
end
local function policeDestination(name)
    for _, garage in pairs((Config.PoliceImpound or {}).location or {}) do
        if garage.label == name and entry(garage) then
            return {kind='impound',label=name,coords=entry(garage),action='Ir até o pátio'}
        end
    end
    if name and location(name) and entry(location(name)) then
        return {kind='impound',label=name,coords=entry(location(name)),action='Ir até o pátio'}
    end
end
local fields = 'vehicle, plate, garage, fuel, engine, body, state, paymentsleft'
local function phoneOwner(src)
    return pr_lib.phone and pr_lib.phone.GetActiveOwnerIdentifier
        and pr_lib.phone.GetActiveOwnerIdentifier(src)
        or nil
end
local function owned(src, plate)
    local citizenid = phoneOwner(src)
    plate = clean(plate)
    if not citizenid or not plate then return nil end
    local row = db.single("SELECT "..fields.." FROM player_vehicles WHERE citizenid=? AND (UPPER(REPLACE(plate,' ',''))=? OR UPPER(REPLACE(fakeplate,' ',''))=?) LIMIT 1", {citizenid,plate,plate})
    return row, citizenid
end
local function impound(plate)
    if not Config.UsePoliceImpound then return nil end
    return db.single("SELECT garage, reason, fine, paid, date FROM police_impound WHERE UPPER(REPLACE(plate,' ',''))=? LIMIT 1", {plate})
end
local kindMap = {bike='motorcycle',bicycle='cycles',heli='helicopter',plane='planes',boat='boat',motorcycles='motorcycle',cycles='cycles',helicopters='helicopter',planes='planes',boats='boat'}
local function describe(src, row, custody)
    local plate = clean(row.plate)
    local catalog = pr_lib.framework.GetVehicleData(row.vehicle) or {}
    local vehicleType = kindMap[catalog.type] or kindMap[catalog.category] or 'car'
    local state = number(row.state)
    local live = state == 0 and vehFuncS.govbp(plate) or nil
    if live and not live.exist then live = nil end
    local engine, body = number(row.engine), number(row.body)
    local engineSource, bodySource = 'saved', 'saved'
    -- Only use synchronized live health when the vehicle has an owner, avoiding uninitialized entities.
    if live and NetworkGetEntityOwner(live.entity) > 0 then
        if type(GetVehicleEngineHealth) == 'function' then
            local value = number(GetVehicleEngineHealth(live.entity))
            if value then engine, engineSource = value, 'live' end
        end
        if type(GetVehicleBodyHealth) == 'function' then
            local value = number(GetVehicleBodyHealth(live.entity))
            if value then body, bodySource = value, 'live' end
        end
    end
    local totalLoss = (engine and engine <= 0) or (body and body <= 0) or false
    local stateCode = state == 1 and 'garaged' or state == 2 and 'impounded' or state == 0 and (live and 'out' or 'insurance') or 'unknown'
    local labels = {garaged='Na garagem',impounded='Apreendido',out='Fora da garagem',insurance='No seguro',unknown='Situação desconhecida'}
    local destination, routeUnavailable
    if stateCode == 'garaged' then
        local coords = entry(location(row.garage))
        if coords then destination = {kind='garage',label=row.garage,coords=coords,action='Ir até a garagem'} end
    elseif stateCode == 'impounded' then
        destination = policeDestination(custody and custody.garage or row.garage)
    elseif stateCode == 'insurance' then
        destination = nearestDepot(src, vehicleType)
    elseif live then
        if live.bucket == GetPlayerRoutingBucket(src) then
            destination = {kind='vehicle',label=totalLoss and 'Veículo danificado' or 'Localização do veículo',coords=point(live.coords),action='Localizar veículo'}
        else routeUnavailable = 'Veículo em outra instância; localização indisponível.' end
    end
    if destination and not destination.coords then destination = nil end
    if destination then
        local origin = point(GetEntityCoords(GetPlayerPed(src)))
        if origin then destination.distance = math.floor(math.sqrt((destination.coords.x-origin.x)^2+(destination.coords.y-origin.y)^2)) end
    end
    local custom = CNV and CNV[plate] and CNV[plate].name
    return {
        plate=plate,spawnName=row.vehicle,brand=catalog.brand or '',model=catalog.name or row.vehicle,
        fullname=custom or ((catalog.brand and catalog.brand..' ' or '')..(catalog.name or row.vehicle)),
        garage=row.garage,state=labels[stateCode],stateCode=stateCode,rawState=state,
        fuel=number(row.fuel),engine=engine,body=body,engineSource=engineSource,bodySource=bodySource,fuelSource='saved',
        conditionCode=totalLoss and 'total_loss' or ((not engine or not body) and 'unknown' or ((engine < 700 or body < 700) and 'damaged' or 'normal')),
        condition=totalLoss and 'Veículo com perda total' or ((not engine or not body) and 'Condição incompleta' or ((engine < 700 or body < 700) and 'Danificado' or 'Em condições de uso')),
        paymentsleft=number(row.paymentsleft),destination=destination,disableTracking=not destination,
        routeUnavailable=not destination and (routeUnavailable or 'Nenhum ponto de atendimento configurado para esta situação.') or nil,
        observedAt=os.time(),impound=custody and {garage=custody.garage,reason=custody.reason,
            amount=number(custody.fine),paid=custody.paid==true or tonumber(custody.paid)==1,
            holdUntil=number(custody.date),requiresPolice=true} or nil,
    }
end
local function invoice(external)
    if GetResourceState('Renewed-Banking') ~= 'started' then return nil end
    local ok, value = pcall(function() return exports['Renewed-Banking']:GetInvoice(external) end)
    return ok and type(value) == 'table' and value or nil
end
local function fines(src, plate)
    local list, warnings = {}, {}
    if GetResourceState('forge-police') == 'started' then
        local ok, result = pcall(function() return exports['forge-police']:GetOwnedVehicleCitations(src, plate) end)
        if ok and result and result.success then list = result.entries or {} else warnings[#warnings+1]='Multas policiais indisponíveis no momento.' end
    else warnings[#warnings+1]='Sistema policial indisponível; as multas policiais não foram consultadas.' end
    local ok, rows = pcall(db.query, "SELECT id, amount, created_at, active, location, garage, occurred_time FROM forge_garage_meter_fines WHERE UPPER(REPLACE(plate,' ',''))=? ORDER BY created_at DESC", {plate})
    if ok and rows then
        for _, row in ipairs(rows) do
            local bill = invoice('parking:'..row.id)
            list[#list+1] = {id='parking:'..row.id,kind='parking',description='Multa de parquímetro',
                location=row.location or row.garage,occurredTime=row.occurred_time,amount=number(row.amount) or 0,
                issuedAt=number(row.created_at),status=bill and bill.status or (tonumber(row.active)==1 and 'active' or 'resolved'),
                total=bill and bill.total or nil,dueAt=bill and bill.dueAt or nil,paidAt=bill and bill.paidAt or nil,
                interestRate=bill and bill.interestRate or nil,interestInterval=bill and bill.interestInterval or nil,
                invoiceAvailable=bill~=nil}
        end
    else warnings[#warnings+1]='Multas de parquímetro indisponíveis no momento.' end
    table.sort(list,function(a,b) return (tonumber(a.issuedAt) or 0) > (tonumber(b.issuedAt) or 0) end)
    return list, warnings
end
function GaragePhoneList(src)
    local citizenid = phoneOwner(src)
    if not citizenid then return {} end
    local rows = db.query('SELECT '..fields..' FROM player_vehicles WHERE citizenid=? ORDER BY plate', {citizenid}) or {}
    local result = {}
    for _, row in ipairs(rows) do
        local custody = tonumber(row.state)==2 and impound(clean(row.plate)) or nil
        result[#result+1] = describe(src,row,custody)
    end
    if phoneOwner(src) ~= citizenid then return {} end
    return result
end
pr_lib.callback.register('forge_garage:phone:details',function(src, plate)
    local row, citizenid = owned(src,plate)
    if not row then return {status='error',message='Veículo não encontrado ou não pertence ao personagem.'} end
    local data = describe(src,row,tonumber(row.state)==2 and impound(clean(row.plate)) or nil)
    data.fines,data.warnings = fines(src,data.plate)
    if phoneOwner(src) ~= citizenid then return {status='error',message='Aparelho ativo alterado. Atualize a lista.'} end
    return {status='ok',data=data}
end)
pr_lib.callback.register('forge_garage:phone:route',function(src, plate)
    local row, citizenid = owned(src,plate)
    if not row then return {status='error',message='Veículo não encontrado ou não pertence ao personagem.'} end
    local data = describe(src,row,tonumber(row.state)==2 and impound(clean(row.plate)) or nil)
    if phoneOwner(src) ~= citizenid then return {status='error',message='Aparelho ativo alterado.'} end
    if not data.destination then return {status='error',message=data.routeUnavailable} end
    return {status='ok',data=data.destination}
end)
