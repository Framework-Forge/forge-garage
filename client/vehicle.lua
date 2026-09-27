vehFunc = {}

--- Get Vehicle Info By Plate
---@param plate string
function vehFunc.gvibp(plate)
    local vehInfo = GarageBridge.callback.await('forge_garage:cb_server:getVehicleInfoByPlate', false, plate)
    return vehInfo and next(vehInfo) and vehInfo or false 
end

--- Get Outside Vehicle By Plate
---@param plate any
---@return integer | boolean
function vehFunc.govbp(plate)
    if type(plate) ~= 'string' then return false end
    plate = plate:gsub('%s+', ''):upper()
    local Vehicles = GetGamePool("CVehicle")
    for i=1, #Vehicles do
        local entity = Vehicles[i]
        local Exist = DoesEntityExist(entity)
        local Dead = IsEntityDead(entity)

        if Exist and not Dead then
            local vP = utils.getPlate(entity)
            local identity = Entity(entity).state.garageVehicleIdentity
            local original = type(identity) == 'table' and identity.originalPlate
            if vP == plate or original == plate then
                return entity
            end
        end
    end
    return false
end


RegisterNetEvent('forge_garage:client:recoverOutsideVehicle', function(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return end

    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    NetworkRequestControlOfEntity(vehicle)
    local timeout = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(vehicle)
    end

    FreezeEntityPosition(vehicle, false)
    SetEntityCollision(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
end)

--- Track Vehicle By Plate
---@param plate any
---@param garage string
function vehFunc.tvbp(plate, garage, setPoint)
    local coords = GarageBridge.callback.await("forge_garage:cb_server:getoutsideVehicleCoords", false, plate, garage)
    if not coords then return false end
    if setPoint then
        SetNewWaypoint(coords.x, coords.y)
    end
    return true
end

--- Get Players Vehicle For Phone
---@return table
function vehFunc.gpvfp()
    return GarageBridge.callback.await('forge_garage:cb_server:GetPlayerVehiclesForPhone')
end

--- Get Vehicle Properties
---@param vehicle string | integer
function vehFunc.gvp(vehicle)
    return GarageBridge.getVehicleProperties(vehicle)
end

---@param vehicle string | integer
---@param props table
function vehFunc.svp(vehicle, props)
    return GarageBridge.setVehicleProperties(vehicle, props)
end

--- exports
exports('trackveh', vehFunc.tvbp)
exports('getvehForPhone', vehFunc.gpvfp)
