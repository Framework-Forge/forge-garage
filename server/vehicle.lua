if GetCurrentResourceName() ~= "forge-garage" then return end

vehFuncS = {}

--- Get Vehicle Out By Plate
---@param plate any
---@return table | boolean
function vehFuncS.govbp(plate)
    local veh = GetAllVehicles()
    for i=1, #veh do
        local entity = veh[i]
        local Plate = utils.getPlate(entity)
        if Plate == utils.string.trim(plate) then
            return {
                exist = DoesEntityExist(entity),
                coords = GetEntityCoords(entity)
            }
        end
    end
    return false
end

GarageBridge.callback.register('forge_garage:cb_server:GetPlayerVehiclesForPhone', function(source)
    return GarageDB.gvfp(source)
end)

GarageBridge.callback.register('forge_garage:cb_server:getoutsideVehicleCoords', function(_, plate, garage)
    local vehicle = vehFuncS.govbp(plate)
    local coords = vehicle and vehicle.exist and vehicle.coords or nil
    if not coords and garage then
        local gz = GarageZone[garage]
        if gz and GarageZone[garage].impound then return end
        local gp = gz and gz.zones and gz.zones.points and #gz.zones.points
        local gc = gp and gz.zones.points[gp] or gz and gz.ipl and gz.ipl.entry
        coords = gc and vec(gc.x, gc.y, gc.z) or nil
        
        if not coords then
            local hg = Config.HouseGarages
            for _, v in pairs(hg) do
                if v.label == garage then
                    local tl = v.takeVehicle
                    coords = vec(tl.x, tl.y, tl.z)
                end
            end
        end
    end
    return coords
end)
