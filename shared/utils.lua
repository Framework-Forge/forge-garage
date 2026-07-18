utils = {}
utils.string = {}

local server = IsDuplicityVersion()

---@param rot vector3
local RotationToDirection = function(rot)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosOfRotX = math.abs(math.cos(rotX))
    return vector3(-math.sin(rotZ) * cosOfRotX, math.cos(rotZ) * cosOfRotX, math.sin(rotX))
end

function utils.string.trim(s)
    if not s or type(s) ~= 'string' then return end
    local trimmed = s:gsub('^%s*(.-)%s*$', '%1')
    return trimmed
end

function utils.string.isEmpty(s)
    return s:match("^%s*$")
end

function utils.raycastCam(distance)
    local camRot = GetGameplayCamRot()
    local camPos = GetGameplayCamCoord()
    local dir = RotationToDirection(camRot)
    local dest = camPos + (dir * distance)
    local ray = StartShapeTestRay(camPos, dest, 17, -1, 0)
    local _, hit, endPos = GetShapeTestResult(ray)
    if hit == 0 then endPos = dest end
    local inwater, watercoords = TestProbeAgainstWater(camPos.x, camPos.y, camPos.z, endPos.x, endPos.y, endPos.z)
    return hit, endPos, inwater, watercoords
end

function utils.notify(msg, type, duration)
    lib.notify({
        description = msg,
        type = type,
        duration = duration or 5000
    })
end

function utils.drawtext (type, text, icon)
    if type == 'show' then
        lib.showTextUI(text,{
            position = "right-center",
            icon = icon or '',
            style = {
                borderRadius= 5,
            }
        })
    elseif type == 'hide' then
        lib.hideTextUI()
    end
end

function utils.createMenu( data )
    lib.registerContext(data)
    lib.showContext(data.id)
end

utils.previewCam = nil
local isCamActive = false

function utils.createPreviewCam(vehicle)
    if not DoesEntityExist(vehicle) then return end

    if not Config.DisableVehicleCamera then
        isCamActive = true
        local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        utils.previewCam = cam
        RenderScriptCams(true, true, 1000, true, true)

        local angle = 0.0
        local distance = 6.0
        local height = 1.2

        CreateThread(function()
            while isCamActive and utils.previewCam == cam and DoesEntityExist(vehicle) do
                -- Disable movement controls (A/D/W/S etc) so player doesn't walk away
                DisableControlAction(0, 30, true) -- MOVE_LR
                DisableControlAction(0, 31, true) -- MOVE_UD
                DisableControlAction(0, 32, true) -- MOVE_UP
                DisableControlAction(0, 33, true) -- MOVE_DOWN
                DisableControlAction(0, 34, true) -- MOVE_LEFT
                DisableControlAction(0, 35, true) -- MOVE_RIGHT

                -- Check A / D or Arrow Keys input
                local left = IsDisabledControlPressed(0, 34) or GetDisabledControlNormal(0, 30) < -0.1 or IsDisabledControlPressed(0, 189)
                local right = IsDisabledControlPressed(0, 35) or GetDisabledControlNormal(0, 30) > 0.1 or IsDisabledControlPressed(0, 190)

                if left then
                    angle = angle + 2.0
                elseif right then
                    angle = angle - 2.0
                end

                local vehCoords = GetEntityCoords(vehicle)
                local rad = math.rad(angle)
                local x = vehCoords.x + distance * math.sin(rad)
                local y = vehCoords.y + distance * math.cos(rad)
                local z = vehCoords.z + height

                SetCamCoord(cam, x, y, z)
                PointCamAtCoord(cam, vehCoords.x, vehCoords.y, vehCoords.z + 0.2)
                Wait(0)
            end
        end)
    end
end

function utils.destroyPreviewCam(vehicle, enterVehicle)
    isCamActive = false
    if not DoesEntityExist(vehicle) then return end

    if utils.previewCam then
        if enterVehicle then
            DoScreenFadeOut(500)
            Wait(1000)
            DoScreenFadeIn(500)
        end

        RenderScriptCams(false, true, 1000, true, true)
        Wait(1000) -- Wait for transition to complete smoothly
        DestroyCam(utils.previewCam, true)
        utils.previewCam = nil
    end
end

function utils.createTargetPed(model, coords, options)
    local newoptions = {}
    local qbtd = nil --- qb-target distance options
    
    lib.requestModel(model, 150000)
    local ped = CreatePed(0, model, coords.x, coords.y, coords.z - 1, coords.w, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    if type(options) == "table" and #options > 0 then
        for i=1, #options do
            local data = options[i]
            local opt = {
                name = data.name,
                label = data.label,
                icon = data.icon,
            }
            if Config.Target == "ox" then
                opt.groups = data.groups
                opt.distance = data.distance
                opt.onSelect = data.action
            elseif Config.Target == "qb" then
                opt.job = data.groups
                opt.gang = data.groups
                opt.action = data.action
            end
            qbtd = data.distance
            newoptions[#newoptions+1] = opt
        end
    end

    if #newoptions > 0 then
        if Config.Target == "ox" then
            exports.ox_target:addLocalEntity(ped, newoptions)
        elseif Config.Target == "qb" then
            local param = {
                options = newoptions,
                distance = qbtd
            }
            exports['qb-target']:AddTargetEntity(ped, param)
        end
    end

    return ped
end

function utils.removeTargetPed(entity, label)
    if DoesEntityExist(entity) then
        if Config.Target == "ox" then
            exports.ox_target:removeLocalEntity(entity, label)
            DeleteEntity(entity)
        elseif Config.Target == "qb" then
            exports['qb-target']:RemoveTargetEntity(entity, label)
            DeleteEntity(entity)
        end
    end
end

function utils.getColorLevel(level)
    if not level then return end
    return level < 25 and "red" or level >= 25 and level < 50 and  "#E86405" or level >= 50 and level < 75 and "#E8AC05" or level >= 75 and "green"
end

function utils.getPlate ( vehicle )
    if not DoesEntityExist(vehicle) then return end
    local vehPlate = GetVehicleNumberPlateText(vehicle)
    return utils.string.trim(vehPlate)
end

function utils.getCategoryByClass ( vehType )
    local class = {
        [8] = "motorcycle",
        [13] = "cycles",
        [14] = "boat",
        [15] = "helicopter",
        [16] = "planes",
    }
    return class[vehType] or "car"
end


function utils.setFuel(vehicle, fuel)
    Wait(100)
    if Config.FuelScript == "ox_fuel" then
        Entity(vehicle).state.fuel = fuel or 100
    else
        exports[Config.FuelScript]:SetFuel(vehicle, fuel or 100)
    end
end

function utils.getFuel(vehicle)
    local fuelLevel = 0
    if Config.FuelScript == "ox_fuel" then
        local state = Entity(vehicle).state
        fuelLevel = state and state.fuel or 100 
    else
        fuelLevel = exports[Config.FuelScript]:GetFuel(vehicle)
    end
    return fuelLevel
end

function utils.createPlyVeh ( model, coords, cb, network, props )
    network = network == nil and false or network
    lib.requestModel(model, 150000)
    local netid = lib.callback.await("forge_garage:server:spawnVehicle", false, model, coords, props)
    if not netid then 
        return lib.notify({description = "Você deve esperar um pouco para fazer essa ação novamente", type = "error", duration = 10000})    
    end
    local veh = NetworkGetEntityFromNetworkId(netid)
    local timeout = 0
    while (not veh or veh == 0 or not DoesEntityExist(veh)) and timeout < 100 do
        Wait(10)
        veh = NetworkGetEntityFromNetworkId(netid)
        timeout = timeout + 1
    end
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        SetVehicleHasBeenOwnedByPlayer(veh, true)
        SetVehicleNeedsToBeHotwired(veh, false)
        SetVehRadioStation(veh, 'OFF')
    end
    SetModelAsNoLongerNeeded(model)
    if cb then cb(veh) else return veh end
end

function utils.createPreviewVeh ( model, coords, cb, network )
    network = network == nil and true or network
    lib.requestModel(model, 150000)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, network, false)
    if network then
        local id = NetworkGetNetworkIdFromEntity(veh)
        SetNetworkIdCanMigrate(id, true)
        SetEntityAsMissionEntity(veh, true, true)
    end
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetModelAsNoLongerNeeded(model)
    if cb then cb(veh) else return veh end
end

function utils.garageType ( data )
    local result = ""
    for i=1, #data do
        local class = data[i]
        result = result .. ("%s%s"):format(class, data[i + 1] and ", " or "")
    end
    return result
end

function utils.GangCheck ( data )
    local configGang = data.gang
    local playerData = pr_lib.framework.GetPlayerData()
    local gang = playerData and playerData.gang
    if not gang then return false end
    local playergang = {
        name = gang.name,
        grade = type(gang.grade) == "table" and gang.grade.level or gang.grade or 0
    }
    local allowed = false
    if type(configGang) == 'table' then
        local grade = configGang[playergang.name]
        allowed = grade and playergang.grade >= grade
    elseif type(configGang) == 'string' then
        if playergang.name == configGang then
            allowed = true
        end
    end
    return allowed
end

function utils.JobCheck ( data )
    local configJob = data.job
    local playerData = pr_lib.framework.GetPlayerData()
    local job = playerData and playerData.job
    if not job then return false end
    local playerjob = {
        name = job.name,
        grade = type(job.grade) == "table" and job.grade.level or job.grade or 0
    }
    local allowed = false

    if type(configJob) == 'table' then
        local grade = configJob[playerjob.name]
        allowed = grade and playerjob.grade >= grade
    elseif type(configJob) == 'string' then
        if playerjob.name == configJob then
            allowed = true
        end
    end
    return allowed
end

local QBShared = nil
function utils.getVehicleLabel(model)
    if not QBShared then
        local QBCore = exports['qb-core']:GetCoreObject()
        if QBCore then
            QBShared = QBCore.Shared
        end
    end
    local vd = QBShared and QBShared.Vehicles[model]
    local makename = GetMakeNameFromVehicleModel(model)
    local displayname = GetDisplayNameFromVehicleModel(model)

    local vm = vd and vd.brand or makename
    local vn = vd and vd.name or displayname
    return ("%s %s"):format(vm, vn)
end

if server then
    function utils.notify(src, msg, type, duration)
        lib.notify(src, {
            description = msg,
            type = type,
            duration = duration or 5000
        })
    end
end