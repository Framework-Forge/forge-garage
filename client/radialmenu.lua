radFunc = {}

local activeActions = {}

local function executeAction(data)
    if not data then return end

    if data.id == "open_garage" then
        if not GarageBridge.cache.vehicle then
            exports["forge-garage"]:openMenu(data.args)
        end
    elseif data.id == "store_veh" then
        if GarageBridge.cache.vehicle then
            exports["forge-garage"]:storeVehicle(data.args)
        end
    elseif data.id == "open_garage_pi" then
        if not GarageBridge.cache.vehicle then
            exports["forge-garage"]:openpoliceImpound(data.args)
        end
    elseif type(data.action) == "function" then
        data.action(data.args)
    elseif data.event then
        TriggerEvent(data.event, { garage = data.args })
    end
end

---@param data RadialData
function radFunc.create(data)
    if type(data) ~= "table" or type(data.id) ~= "string" then return false end
    activeActions[data.id] = data
    return data.id
end

---@param id string
function radFunc.remove(id)
    activeActions[id] = nil
end

CreateThread(function()
    while true do
        if next(activeActions) then
            if IsControlJustPressed(0, 38) then
                local selected

                if GarageBridge.cache.vehicle then
                    selected = activeActions.store_veh
                else
                    selected = activeActions.open_garage_pi or activeActions.open_garage
                end

                if selected then executeAction(selected) end
            end

            Wait(0)
        else
            Wait(250)
        end
    end
end)

RegisterNetEvent("forge_garage:radial:open", function(data)
    if not GarageBridge.cache.vehicle then
        exports["forge-garage"]:openMenu(data.garage or data)
    end
end)

RegisterNetEvent("forge_garage:radial:store", function(data)
    exports["forge-garage"]:storeVehicle(data.garage or data)
end)

RegisterNetEvent("forge_garage:radial:open_policeimpound", function(data)
    if not GarageBridge.cache.vehicle then
        exports["forge-garage"]:openpoliceImpound(data.garage or data)
    end
end)
