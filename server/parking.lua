-- Server-authoritative meter sessions; charges are settled when leaving a bay.
Parking = Parking or {}
local sessions, busy, ready, debtHandler = {}, false, false, nil
local function key(value)
    return type(value) == 'string' and value:gsub('%s+', ''):upper() or ''
end
local function createBankInvoice(row)
    if GetResourceState('Renewed-Banking') ~= 'started' or type(row) ~= 'table' then return false end
    local owner = pr_lib.database.scalar([[SELECT citizenid FROM player_vehicles
        WHERE UPPER(REPLACE(plate,' ',''))=? LIMIT 1]], { key(row.plate) })
    if not owner then return false end
    local description = ('Não pagar estacionamento de parquímetro. Local: %s. Hora: %s. Placa: %s.'):format(
        tostring(row.location or row.garage or 'Não informado'), tostring(row.occurred_time or os.date('%H:%M',tonumber(row.created_at) or os.time())), key(row.plate))
    local metadata = { kind='parking', debtId=row.id, plate=key(row.plate), garage=row.garage,
        location=row.location, time=row.occurred_time }
    local updateOk = pcall(function() return exports['Renewed-Banking']:UpdateInvoice('parking:'..tostring(row.id), {
        amount=tonumber(row.amount), description=description, metadata=metadata }) end)
    if updateOk then
        local existing = exports['Renewed-Banking']:GetInvoice('parking:'..tostring(row.id))
        if existing then return true end
    end
    local ok, result = pcall(function()
        return exports['Renewed-Banking']:CreateInvoice({
            externalId = 'parking:' .. tostring(row.id), recipient = owner,
            issuer = 'Fiscalização de estacionamento', receiverAccount = 'police',
            title = 'Multa de parquímetro',
            description = description,
            amount = tonumber(row.amount),
            metadata = metadata
        })
    end)
    if not ok or type(result) ~= 'table' or result.success ~= true then
        print(('[forge-garage][parking] Banking invoice %s failed: %s'):format(tostring(row.id), tostring(result)))
        return false
    end
    return true
end
local function copy(value) return json.decode(json.encode(value)) end
local function serial(action)
    while busy do Wait(0) end
    busy = true
    local ok, result = pcall(action)
    busy = false
    if not ok then
        print('[forge-garage][parking] ' .. tostring(result))
        return { success = false, reason = 'storage_error' }
    end
    return result
end
local function config(name)
    local g = GarageZone and GarageZone[name]
    return g and g.persist and not g.impound and g.parking and g.parking.enabled and g.parking or nil
end
local function cooldown(g)
    return tonumber(g and g.persistenceCooldownSeconds)
        or tonumber(g and g.parking and g.parking.exitCooldownSeconds) or 120
end
local function spots(g)
    return g.ipl and g.ipl.enabled and g.ipl.parkingSpots or g.spawnPoint or {}
end
local function distance(a, b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
local function meterFor(g, id)
    for _, meter in ipairs(g.parking and g.parking.meters or {}) do
        if meter.id == id then return meter end
    end
end
local function canUse(src, plate)
    local ok, allowed = pcall(function() return exports['pr_carkeys']:HasVehicleAccess(src, plate) end)
    return ok and allowed == true
end
local function save(s)
    local result = pr_lib.database.query([[
        INSERT INTO forge_garage_meter_sessions (plate, payload) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE payload=VALUES(payload)]], {s.plate, json.encode(s)})
    assert(result ~= nil, 'session save failed')
    sessions[s.plate] = s
end
local function gameClockMinute()
    local current = GlobalState.currentTime
    local hour = type(current) == 'table' and tonumber(current.hour)
    local minute = type(current) == 'table' and tonumber(current.minute)
    if not hour or not minute then return nil end
    return (math.floor(hour) % 24) * 60 + (math.floor(minute) % 60)
end
local function advance(s, timestamp, clockMinute)
    if s.pausedUntil and timestamp >= s.pausedUntil then
        -- The grace interval never accrues time, including across restarts.
        s.lastTick = s.pausedUntil
        s.pausedUntil = nil
        s.paid = false
        s.needsRestore = true
    end
    if s.metered ~= false then clockMinute = clockMinute or gameClockMinute() end
    if s.metered ~= false and clockMinute then
        if s.billingClock ~= 'game' then
            local legacyUnit = tonumber(s.unitSeconds) or 120
            local unitMinutes = s.unit == 'day' and 1440 or 60
            s.elapsedGameMinutes = math.max(0, (tonumber(s.elapsed) or 0) / legacyUnit * unitMinutes)
            s.billingClock = 'game'
            s.unitMinutes = unitMinutes
            s.lastGameMinute = clockMinute
        elseif s.lastGameMinute ~= nil then
            local delta = (clockMinute - s.lastGameMinute) % 1440
            -- Normal ticks may jump when the clock is accelerated. Large jumps are
            -- treated as an administrator changing the hour, not parked time.
            if not s.pausedUntil and delta <= 120 then
                s.elapsedGameMinutes = (s.elapsedGameMinutes or 0) + delta
            end
            s.lastGameMinute = clockMinute
        else
            s.lastGameMinute = clockMinute
        end
    end
    s.lastTick = timestamp
end
local function due(s)
    if s.metered == false or s.paid then return 0 end
    local unitMinutes = tonumber(s.unitMinutes) or (s.unit == 'day' and 1440 or 60)
    return math.max(1, math.ceil((s.elapsedGameMinutes or 0) / unitMinutes)) * s.rate
end
local function nearMeter(src, s, id)
    if s.metered == false then return false end
    local g = GarageZone[s.garage]
    local m = g and meterFor(g, id)
    if g and g.parking and g.parking.meterMode=='existing' and id=='map' then
        local ped=GetPlayerPed(src)
        if ped==0 or GetPlayerRoutingBucket(src)~=s.bucket then return false end
        for _,bay in ipairs(spots(g)) do
            if distance(GetEntityCoords(ped),bay.coords or bay)<=34 then return true end
        end
        return false
    end
    local ped = GetPlayerPed(src)
    return m and ped ~= 0 and distance(GetEntityCoords(ped), m.coords) <= 4
        and GetPlayerRoutingBucket(src) == s.bucket
end
local function debts(plate)
    local rows = pr_lib.database.query('SELECT * FROM forge_garage_meter_fines WHERE plate=? AND active=1', {plate}) or {}
    local amount = 0
    for _, row in ipairs(rows) do amount = amount + row.amount end
    -- Preserve debts created by the previous implementation.
    local legacy = pr_lib.database.single('SELECT amount FROM forge_garage_parking_debts WHERE plate=? AND active=1', {plate})
    amount = amount + (legacy and tonumber(legacy.amount) or 0)
    return { active = amount > 0, plate = plate, amount = amount, records = rows }
end
local function dispatch(row)
    if not debtHandler or GetResourceState(debtHandler.resource) ~= 'started' then return end
    local ok, accepted = pcall(function()
        local receiver = exports[debtHandler.resource]
        return receiver[debtHandler.name](receiver, copy(row))
    end)
    if ok and accepted == true then
        pr_lib.database.update('UPDATE forge_garage_meter_fines SET delivered=1 WHERE id=?', {row.id})
    elseif not ok then
        print(('[forge-garage][parking] Debt %s delivery failed: %s'):format(tostring(row.id), tostring(accepted)))
    end
end
local function finish(s)
    local timestamp = os.time()
    advance(s, timestamp)
    local amount = due(s)
    -- A unique session id prevents duplicate fines on retry/restart.
    local statements = {}
    if amount > 0 then
        statements[#statements+1] = {
            query = [[INSERT IGNORE INTO forge_garage_meter_fines
                (id,plate,garage,meter_id,location,occurred_time,amount,created_at,active,delivered)
                VALUES (?,?,?,?,?,?,?,?,1,0)]],
            values = {s.id,s.plate,s.garage,s.meterId,s.location,os.date('%H:%M',timestamp),amount,timestamp}
        }
    end
    statements[#statements+1] = {query='DELETE FROM forge_garage_meter_sessions WHERE plate=?',values={s.plate}}
    assert(pr_lib.database.transaction(statements), 'departure transaction failed')
    sessions[s.plate] = nil
    if amount > 0 then
        dispatch({id=s.id,plate=s.plate,garage=s.garage,meter_id=s.meterId,location=s.location,occurred_time=os.date('%H:%M',timestamp),amount=amount,created_at=timestamp})
        createBankInvoice({id=s.id,plate=s.plate,garage=s.garage,meter_id=s.meterId,location=s.location,occurred_time=os.date('%H:%M',timestamp),amount=amount,created_at=timestamp})
        -- Local server event; never a client-authorized fine.
        TriggerEvent('forge_garage:server:parkingDebtCreated', {
            id=s.id,plate=s.plate,garage=s.garage,meter_id=s.meterId,location=s.location,occurred_time=os.date('%H:%M',timestamp),amount=amount,created_at=timestamp
        })
    end
end
-- Called only by the server persistence registry; free sessions never create debt.
function Parking.trackPersistentEntity(garageName,plate,entity,netId)
    local g=GarageZone and GarageZone[garageName]
    if not ready or not g or not g.persist or config(garageName) then return end
    plate=key(plate)
    if plate=='' or sessions[plate] or not entity or not DoesEntityExist(entity) then return end
    if key(Entity(entity).state.plate or GetVehicleNumberPlateText(entity))~=plate then return end
    local pos=GetEntityCoords(entity)
    local timestamp=os.time()
    sessions[plate]={
        id=plate..':'..timestamp..':'..GetGameTimer(),plate=plate,garage=garageName,
        meterId='none',metered=false,origin={x=pos.x,y=pos.y,z=pos.z},
        netId=netId or NetworkGetNetworkIdFromEntity(entity),bucket=GetEntityRoutingBucket(entity),
        elapsed=0,lastTick=timestamp,rate=0,exitCooldownSeconds=cooldown(g),
        wasUnlocked=false
    }
end
function Parking.onVehicleStored(src, data)
    if not ready then return false end
    return serial(function()
        local p = config(data.garage)
        if not p then return true end
        local plate = key(data.plate)
        local entity = tonumber(data.netId) and NetworkGetEntityFromNetworkId(tonumber(data.netId)) or 0
        if entity == 0 or not DoesEntityExist(entity) or not canUse(src, plate) then return false end
        local actual = key(Entity(entity).state.plate or GetVehicleNumberPlateText(entity))
        local ped = GetPlayerPed(src)
        if actual ~= plate or ped == 0 or distance(GetEntityCoords(ped),GetEntityCoords(entity)) > 12 then return false end
        local g = GarageZone[data.garage]
        local best, bestDist
        for i, spot in ipairs(spots(g)) do
            local d = distance(GetEntityCoords(entity), spot.coords or spot)
            if d <= 3.5 and (not bestDist or d < bestDist) then best,bestDist=i,d end
        end
        if not best then return false end
        for _, occupied in pairs(sessions) do
            if occupied.garage == data.garage and occupied.spotIndex == best and occupied.plate ~= plate then return false end
        end
        local previous = sessions[plate]
        if previous then
            if previous.garage == data.garage and previous.spotIndex == best then return true end
            return false
        end
        local timestamp = os.time()
        local unit = p.unit == 'day' and 'day' or 'hour'
        local rate = tonumber(unit == 'day' and p.ratePerGameDay or p.ratePerGameHour) or 100
        if rate <= 0 or rate > 1000000 then return false end
        local point = spots(g)[best]
        point = point.coords or point
        save({
            id=plate..':'..timestamp..':'..GetGameTimer(),plate=plate,garage=data.garage,meterId='parking',
            spotIndex=best,origin={x=point.x,y=point.y,z=point.z},netId=data.netId,
            bucket=GetEntityRoutingBucket(entity),elapsedGameMinutes=0,lastTick=timestamp,
            rate=math.floor(rate),unitMinutes=unit=='day' and 1440 or 60,unit=unit,metered=true,
            billingClock='game',lastGameMinute=gameClockMinute(),exitCooldownSeconds=cooldown(g),
            account=p.paymentAccount=='cash' and 'cash' or 'bank',wasUnlocked=false,
            location=tostring(data.parkingLocation or data.garage):sub(1,160)
        })
        GarageBridge.notify(src,{description=('Vaga %d: $%s por %s do jogo (ou fracao). Destranque para pausar e pagar em ate %s segundos.'):format(
            best,math.floor(rate),unit=='day' and 'dia' or 'hora',cooldown(g)),type='info',duration=10000})
        return true
    end) == true
end
-- Acceleration alone does not end the bill. The server watches physical departure.
function Parking.onVehicleWithdrawn(plate) return sessions[key(plate)] ~= nil end
GarageBridge.callback.register('forge_garage:cb_server:getParkingVehicles',function(src,garage,id)
    if not ready then return {success=false,reason='not_ready'} end
    return serial(function()
        local vehicles={}
        for _, original in pairs(sessions) do
            if original.garage == garage and nearMeter(src,original,id) and canUse(src,original.plate) then
                local s=copy(original)
                advance(s,os.time())
                save(s)
                vehicles[#vehicles+1]={plate=s.plate,label='Vaga '..s.spotIndex,debt=due(s),
                    canPay=s.pausedUntil~=nil and not s.paid,remaining=s.pausedUntil and math.max(0,s.pausedUntil-os.time()) or 0}
            end
        end
        return {success=true,vehicles=vehicles}
    end)
end)
GarageBridge.callback.register('forge_garage:cb_server:payParking',function(src,garage,id,plate)
    if not ready then return {success=false,reason='not_ready'} end
    return serial(function()
        local original=sessions[key(plate)]
        if not original or original.garage~=garage or not nearMeter(src,original,id)
            or not canUse(src,original.plate) then return {success=false,reason='vehicle_not_available'} end
        local s=copy(original)
        advance(s,os.time())
        if not s.pausedUntil or s.paid then return {success=false,reason='unlock_first'} end
        local amount=due(s)
        if not pr_lib.framework.removePlayerMoney(src,s.account,amount,'Parking meter settlement') then
            return {success=false,reason='not_enough_money'}
        end
        s.paid=true
        s.elapsedGameMinutes=0
        -- Payment keeps the remainder of the same exit window, not unlimited free parking.
        local ok,err=pcall(save,s)
        if not ok then
            pr_lib.framework.addPlayerMoney(src,s.account,amount,'Parking payment refund')
            error(err)
        end
        return {success=true,amount=amount,remaining=math.max(0,s.pausedUntil-os.time())}
    end)
end)
exports('GetParkingDebt',function(plate)
    if not ready then return {active=false,ready=false} end
    return debts(key(plate))
end)
exports('ReportParkingDebt',function(plate,reference)
    if not ready then return {active=false,ready=false} end
    local result=debts(key(plate))
    result.reportReference=tostring(reference or '')
    return result
end)
exports('ResolveParkingDebt',function(plate,reference)
    if not ready then return false end
    return pr_lib.database.transaction({
        {query='UPDATE forge_garage_meter_fines SET active=0,reference=? WHERE plate=? AND active=1',values={tostring(reference or ''),key(plate)}},
        {query='UPDATE forge_garage_parking_debts SET active=0,report_reference=? WHERE plate=?',values={tostring(reference or ''),key(plate)}}
    })
end)
exports('SyncParkingInvoice',function(id)
    if not ready or GetResourceState('Renewed-Banking')~='started' then return false end
    id=tostring(id or '')
    if id=='' or #id>100 then return false end
    local row=pr_lib.database.single('SELECT * FROM forge_garage_meter_fines WHERE id=? LIMIT 1',{id})
    return row and createBankInvoice(row) or false
end)
exports('RegisterParkingDebtHandler',function(exportName)
    local resource=GetInvokingResource()
    if not resource or type(exportName)~='string' or exportName=='' then return false end
    debtHandler={resource=resource,name=exportName}
    return true
end)
CreateThread(function()
    while not pr_lib.database.isReady() do Wait(100) end
    pr_lib.database.query([[CREATE TABLE IF NOT EXISTS forge_garage_meter_sessions (
        plate VARCHAR(50) PRIMARY KEY,payload LONGTEXT NOT NULL)]])
    pr_lib.database.query([[CREATE TABLE IF NOT EXISTS forge_garage_meter_fines (
        id VARCHAR(100) PRIMARY KEY,plate VARCHAR(50) NOT NULL,garage VARCHAR(120),meter_id VARCHAR(80),
        amount INT NOT NULL,created_at BIGINT NOT NULL,active TINYINT DEFAULT 1,delivered TINYINT DEFAULT 0,
        reference VARCHAR(120),location VARCHAR(160),occurred_time CHAR(5),INDEX(plate))]])
    local columns = assert(pr_lib.database.query('SHOW COLUMNS FROM forge_garage_meter_fines'))
    local existing = {}
    for _, column in ipairs(columns) do existing[column.Field] = true end
    if not existing.location then
        assert(pr_lib.database.execute('ALTER TABLE forge_garage_meter_fines ADD COLUMN location VARCHAR(160) NULL AFTER meter_id') ~= nil)
    end
    if not existing.occurred_time then
        assert(pr_lib.database.execute('ALTER TABLE forge_garage_meter_fines ADD COLUMN occurred_time CHAR(5) NULL AFTER location') ~= nil)
    end
    for _, row in ipairs(pr_lib.database.query('SELECT * FROM forge_garage_meter_sessions') or {}) do
        local ok,s=pcall(json.decode,row.payload)
        assert(ok and type(s)=='table','Invalid persisted meter session: '..row.plate)
        s.netId=nil -- network ids can be reused after a restart
        sessions[row.plate]=s
    end
    ready=true
    local nextDiscovery=0
    while true do
        Wait(1000)
        serial(function()
            local world
            -- Recover already-spawned free vehicles on resource start; registry hooks
            -- cover new stores/spawns without a per-frame vehicle pool scan.
            if os.time()>=nextDiscovery then
                world=GetAllVehicles()
                for _,entity in ipairs(world) do
                    local state=Entity(entity).state
                    if state.isPersistent and state.garageName then
                        Parking.trackPersistentEntity(state.garageName,state.plate or GetVehicleNumberPlateText(entity),entity)
                    end
                end
                nextDiscovery=os.time()+30
            end
            for plate,original in pairs(sessions) do
                local s=copy(original)
                local entity=s.netId and NetworkGetEntityFromNetworkId(s.netId) or 0
                if entity==0 or not DoesEntityExist(entity) or key(Entity(entity).state.plate or GetVehicleNumberPlateText(entity))~=plate then
                    entity=0
                    world=world or GetAllVehicles()
                    for _,candidate in ipairs(world) do
                        if key(Entity(candidate).state.plate or GetVehicleNumberPlateText(candidate))==plate then entity=candidate break end
                    end
                end
                local garage=GarageZone and GarageZone[s.garage]
                if s.metered==false and (not garage or not garage.persist) then
                    assert(pr_lib.database.query('DELETE FROM forge_garage_meter_sessions WHERE plate=?',{plate})~=nil)
                    sessions[plate]=nil
                elseif entity~=0 and GetEntityRoutingBucket(entity)==s.bucket then
                    s.netId=NetworkGetNetworkIdFromEntity(entity)
                    advance(s,os.time())
                    if distance(GetEntityCoords(entity),s.origin)>6.0 then
                        finish(s)
                    else
                        if s.needsRestore and GetEntitySpeed(entity)<0.4 then
                            if GarageRestoreMeterParking and GarageRestoreMeterParking(s,entity) then
                                s.needsRestore=nil
                                s.wasUnlocked=false
                            end
                        end
                        local lock=Entity(entity).state.doorslockstate
                        local unlocked=lock==0 or lock==1
                        if unlocked and not s.wasUnlocked and not s.pausedUntil and not s.needsRestore then
                            s.pausedUntil=os.time()+cooldown(garage)
                        end
                        s.wasUnlocked=unlocked
                        -- Persist state transitions and one checkpoint per minute.
                        if s.needsRestore~=original.needsRestore or s.pausedUntil~=original.pausedUntil or s.wasUnlocked~=original.wasUnlocked
                            or os.time()-(original.checkpoint or 0)>=60 then
                            s.checkpoint=os.time()
                            save(s)
                        else sessions[plate]=s end
                    end
                end
            end
        end)
    end
end)
CreateThread(function()
    while true do
        Wait(30000)
        if ready and GetResourceState('Renewed-Banking') == 'started' then
            for _, row in ipairs(pr_lib.database.query('SELECT * FROM forge_garage_meter_fines WHERE active=1 LIMIT 250') or {}) do
                createBankInvoice(row)
            end
        end
    end
end)

AddEventHandler('Renewed-Banking:server:invoicePaid', function(invoice)
    if type(invoice) ~= 'table' or invoice.issuerResource ~= 'forge-garage' then return end
    local metadata = invoice.metadata
    if type(metadata) ~= 'table' or metadata.kind ~= 'parking' or not metadata.debtId then return end
    pr_lib.database.update('UPDATE forge_garage_meter_fines SET active=0,reference=? WHERE id=? AND active=1',
        { 'bank-invoice:' .. tostring(invoice.id), tostring(metadata.debtId) })
end)
CreateThread(function()
    while true do
        Wait(10000)
        if ready and debtHandler then
            local ok,err=pcall(function()
                for _,row in ipairs(pr_lib.database.query('SELECT * FROM forge_garage_meter_fines WHERE delivered=0 AND active=1 LIMIT 50') or {}) do dispatch(row) end
            end)
            if not ok then print('[forge-garage][parking] MDT dispatch: '..tostring(err)) end
        end
    end
end)

function Parking.validateConfig(all)
    for name,g in pairs(all) do
        if type(g)=='table' and g.persistenceCooldownSeconds~=nil then
            local n=g.persistenceCooldownSeconds
            if type(n)~='number' or n~=n or n%1~=0 or n<10 or n>86400 then
                return false,'Prazo de persistencia invalido (10 a 86400 segundos).'
            end
        end
        local p=type(g)=='table' and g.parking
        if p and p.enabled then
            if not g.persist or g.impound then return false,'Parquimetros exigem garagem persistente sem apreensao.' end
            local bays=spots(g)
            if #bays==0 or type(p.meters)~='table' or #p.meters>100 then
                return false,'Configure as vagas do estacionamento: '..tostring(name)
            end
            if p.unit~='hour' and p.unit~='day' then return false,'Selecione hora ou dia.' end
            for _,field in ipairs({'ratePerGameHour','ratePerGameDay'}) do
                local n=tonumber(p[field])
                if not n or n~=n or n<1 or n>1000000 then return false,'Valor invalido: '..field end
            end
            if p.meterMode and p.meterMode~='existing' and p.meterMode~='placed' then return false,'Modo de parquimetro invalido.' end
            local cooldown=p.exitCooldownSeconds or 120
            if type(cooldown)~='number' or cooldown~=cooldown or cooldown%1~=0 or cooldown<10 or cooldown>86400 then
                return false,'Prazo de saida invalido (10 a 86400 segundos).'
            end
            local ids={}
            for _,m in ipairs(p.meters) do
                if type(m)~='table' or type(m.id)~='string' or #m.id>80 or ids[m.id]
                    or (m.model~='prop_parknmeter_01' and m.model~='prop_parknmeter_02') then return false,'Vinculo de parquimetro invalido.' end
                if type(m.coords)~='table' then return false,'Posicao invalida.' end
                for _,axis in ipairs({'x','y','z'}) do
                    local v=m.coords[axis]
                    if type(v)~='number' or v~=v or math.abs(v)>10000 then return false,'Coordenada invalida.' end
                end
                for _,other in ipairs(p.meters) do
                    if other~=m and type(other.coords)=='table' and distance(m.coords,other.coords)<0.5 then return false,'Parquimetros sobrepostos.' end
                end
                ids[m.id]=true
            end
        end
    end
    return true
end
GarageBridge.callback.register('forge_garage:cb_server:beginMeterParking',function(src,data)
    if type(data)~='table' or type(data.garage)~='string' then return false end
    if not config(data.garage) then return true end
    return Parking.onVehicleStored(src,data)
end)
