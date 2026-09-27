if GetCurrentResourceName() ~= "forge-garage" then return end

vehFuncS = {}

--- Get Vehicle Out By Plate
---@param plate any
---@return table | boolean
function vehFuncS.govbp(plate)
    plate = GarageVehicleIdentity.resolve(plate)
    if not plate then return false end
    local veh = GetAllVehicles()
    for i=1, #veh do
        local entity = veh[i]
        local Plate = utils.getPlate(entity)
        if GarageVehicleIdentity.resolve(Plate) == plate then
            return {
                exist = DoesEntityExist(entity),
                coords = GetEntityCoords(entity),
                entity = entity,
                netId = NetworkGetNetworkIdFromEntity(entity),
                bucket = GetEntityRoutingBucket(entity),
            }
        end
    end
    return false
end

GarageBridge.callback.register('forge_garage:cb_server:GetPlayerVehiclesForPhone', function(source)
    return GaragePhoneList(source)
end)

GarageBridge.callback.register('forge_garage:cb_server:getoutsideVehicleCoords', function(source, plate)
    local vehicle = vehFuncS.govbp(plate)
    if not vehicle or not vehicle.exist then return nil end

    local playerBucket = GetPlayerRoutingBucket(source)
    if (vehicle.bucket ~= playerBucket or vehicle.coords.z < -20.0) and GarageRecoverOutsideVehicle then
        local recovered = GarageRecoverOutsideVehicle(source, plate)
        if recovered and DoesEntityExist(recovered) then
            vehicle.coords = GetEntityCoords(recovered)
            vehicle.bucket = GetEntityRoutingBucket(recovered)
        end
    end

    -- Do not use the garage coordinates as a fake outside-vehicle result.
    if vehicle.bucket ~= playerBucket then return nil end
    return vehicle.coords
end)

-- Availability differs from police custody: state 0 without an entity is recovery.
exports('GetVehicleAvailability',function(plate)
    local row=pr_lib.database.single('SELECT state, engine, body FROM player_vehicles WHERE plate = ?', {plate})
    if not row then return nil end
    local state=tonumber(row.state)
    if state==2 then return 'Apreendido' end
    if state==1 then return 'Na garagem' end
    local live=vehFuncS.govbp(plate)
    if live and live.exist then return 'Em circulacao' end
    if (tonumber(row.engine) or 1000)<=0 or (tonumber(row.body) or 1000)<=0 then return 'Danificado — recuperar no seguro' end
    return 'Fora do mundo — recuperar no seguro'
end)
