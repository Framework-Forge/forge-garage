radFunc = {}
local radaial = {}

if Config.RadialMenu == "ox" then
    ---@param data RadialData
    function radFunc.create(data)
        lib.addRadialItem({
            {
                id = data.id,
                label = data.label,
                icon = data.icon,
                onSelect = function ()
                    if data.id == "open_garage" and not cache.vehicle then
                        exports['forge-garage']:openMenu(data.args)
                    elseif data.id == "store_veh" then
                        exports['forge-garage']:storeVehicle(data.args)
                    elseif data.id == "open_garage_pi" then
                        exports['forge-garage']:openpoliceImpound(data.args)
                    end
                end
            },
        })
    end

    ---@param id string
    function radFunc.remove(id)
        lib.removeRadialItem(id)
    end

elseif Config.RadialMenu == "qb" then
    ---@param data RadialData
    function radFunc.create(data)
        local id = data.id:gsub("%s+", "")
        radaial[id] = exports['qb-radialmenu']:AddOption({
            id = id,
            title = data.label,
            icon = data.icon == "parking" and "square-parking" or data.icon,
            type = 'client',
            event = data.event,
            garage = data.args,
            shouldClose = true
        }, radaial[id])
        return radaial[id]
    end

    ---@param id string
    function radFunc.remove(id)
        if radaial[id] then
            exports['qb-radialmenu']:RemoveOption(radaial[id])
        end
    end

    RegisterNetEvent("forge_garage:radial:open", function (self)
        if not cache.vehicle then
            exports['forge-garage']:openMenu(self.garage)
        end
    end)

    RegisterNetEvent("forge_garage:radial:store", function (self)
        exports['forge-garage']:storeVehicle(self.garage)
    end)

    RegisterNetEvent('forge_garage:radial:open_policeimpound', function(self)
        if not cache.vehicle then
            exports['forge-garage']:openpoliceImpound(self.garage)
        end
    end)

elseif Config.RadialMenu == "rhd" then
    ---@param data RadialData
    function radFunc.create(data)
        exports.forge_radialmenu:addRadialItem({
            id = data.id,
            label = data.label,
            icon = data.icon,
            action = function ()
                if data.id == "open_garage" and not cache.vehicle then
                    exports['forge-garage']:openMenu(data.args)
                elseif data.id == "store_veh" then
                    exports['forge-garage']:storeVehicle(data.args)
                elseif data.id == "open_garage_pi" then
                    exports['forge-garage']:openpoliceImpound(data.args)
                end
            end
        })
    end

    ---@param id string
    function radFunc.remove(id)
        exports.forge_radialmenu:removeRadialItem(id)
    end
end
