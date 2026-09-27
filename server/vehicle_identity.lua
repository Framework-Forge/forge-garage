-- Persistent registration is the key identity; the visible plate may be temporary.
GarageVehicleIdentity = {}
local registrations, aliases = {}, {}

local function clean(value)
    if type(value) ~= 'string' then return nil end
    value = value:upper():gsub('%s+', '')
    return value ~= '' and value or nil
end

function GarageVehicleIdentity.remember(row)
    local original = clean(row.plate)
    if not original then return end
    local previous = registrations[original]
    if previous and previous.fakePlate then aliases[previous.fakePlate] = nil end
    local fake = clean(row.fakeplate)
    if fake == original then fake = nil end
    registrations[original] = {
        originalPlate = original, fakePlate = fake,
        vehicleId = tonumber(row.id) or (previous and previous.vehicleId),
    }
    if fake then aliases[fake] = original end
end

function GarageVehicleIdentity.resolve(plate)
    plate = clean(plate)
    return aliases[plate] or plate
end

function GarageVehicleIdentity.sync(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return false end
    local displayed = clean(GetVehicleNumberPlateText(vehicle))
    local record = registrations[GarageVehicleIdentity.resolve(displayed)]
    if not record then return false end
    local state = Entity(vehicle).state
    local old = state.garageVehicleIdentity
    if type(old) == 'table' and old.originalPlate == record.originalPlate
        and old.fakePlate == record.fakePlate and old.vehicleId == record.vehicleId then return true end
    state:set('garageVehicleIdentity', record, true)
    state:set('originalPlate', record.originalPlate, true)
    state:set('fakePlate', record.fakePlate, true)
    return true
end

-- Trusted server resources call this after registration changes, never on lock/unlock.
exports('RefreshVehicleIdentity', function(plate, netId)
    plate = clean(plate)
    if not plate then return false end
    local row = pr_lib.database.single([[SELECT id,plate,fakeplate FROM player_vehicles
        WHERE REPLACE(UPPER(plate),' ','')=? OR REPLACE(UPPER(fakeplate),' ','')=? LIMIT 1]], {plate,plate})
    if not row then return false end
    GarageVehicleIdentity.remember(row)
    if netId then GarageVehicleIdentity.sync(NetworkGetEntityFromNetworkId(tonumber(netId))) end
    return true
end)

exports('ResolveVehicleKeyPlate', GarageVehicleIdentity.resolve)

local function syncSoon(vehicle)
    CreateThread(function()
        for _ = 1, 20 do
            Wait(500)
            if not DoesEntityExist(vehicle) then return end
            if GetEntityType(vehicle) ~= 2 then return end
            if GarageVehicleIdentity.sync(vehicle) then return end
        end
    end)
end

AddEventHandler('entityCreated', syncSoon)
AddStateBagChangeHandler('plate', nil, function(bagName)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle ~= 0 then syncSoon(vehicle) end
end)

pr_lib.database.ready(function()
    local rows = pr_lib.database.query('SELECT id,plate,fakeplate FROM player_vehicles') or {}
    for _, row in ipairs(rows) do
        if not registrations[clean(row.plate)] then GarageVehicleIdentity.remember(row) end
    end
    for _, vehicle in ipairs(GetAllVehicles()) do GarageVehicleIdentity.sync(vehicle) end
end)
