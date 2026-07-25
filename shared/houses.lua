local psHousing = GetResourceState("ps-housing") ~= "missing"
local qbHousing = GetResourceState("qb-houses") ~= "missing"
local qsHousing = GetResourceState("qs-housing") ~= "missing"
local isServer = IsDuplicityVersion()

local lasthouse = nil
local houseZone = {}
local isOwner = false

--- for qb-houses or ps-housing
if qbHousing or psHousing or qsHousing then
    if not isServer then
        RegisterNetEvent('qb-garages:client:setHouseGarage', function(house, hasKey)
            local HG = Config.HouseGarages[house]
            if not HG then return end
            
            if lasthouse == house then return end
            
            if lasthouse then
                houseZone[lasthouse]:remove()
            end
            
            if hasKey and HG.takeVehicle and HG.takeVehicle.x then
                local coords = HG.takeVehicle
                local label = HG.label
                local spawnloc = vec4(coords.x, coords.y, coords.z, coords.w)
                houseZone[house] = GarageBridge.zones.sphere({
                    coords = spawnloc.xyz,
                    radius = 4,
                    inside = function ()
                        if IsControlJustPressed(0, 38) and isOwner then
        
                            ---@class GarageVehicleData
                            local args = {
                                garage = label,
                                type = {'car', 'motorcycle', 'cycles'},
                                spawnpoint = spawnloc,
                                ignoreDist = true
                            }
        
                            if GarageBridge.cache.vehicle then
                                return exports['forge-garage']:storeVehicle(args)
                            end
        
                            exports['forge-garage']:openMenu(args)
                        end
                    end,
                    onEnter = function ()
                        isOwner = GarageBridge.callback.await('forge_garage:cb_server:getOwnedHouse', false, house)
                        if not isOwner then return end
                        local dl = ('[E] - %s'):format(label)
                        utils.drawtext('show', dl:upper(), 'warehouse')
                    end,
                    onExit = function ()
                        isOwner = false
                        utils.drawtext('hide')
                    end
                })
                lasthouse = house
            end
        end)
        
        RegisterNetEvent('qb-garages:client:houseGarageConfig', function(garageConfig)
            Config.HouseGarages = garageConfig
            TriggerServerEvent('forge_garage:server:houseGarageConfig', Config.HouseGarages)
        end)
        
        RegisterNetEvent('qb-garages:client:addHouseGarage', function(house, garageInfo)
            Config.HouseGarages[house] = garageInfo
            TriggerServerEvent('forge_garage:server:addHouseGarage', house, garageInfo)
        end)
        
        if psHousing or qsHousing then
            RegisterNetEvent('qb-garages:client:removeHouseGarage', function(house)
                Config.HouseGarages[house] = nil
            end)
        end
    else
        --- check house owner
        GarageBridge.callback.register('forge_garage:cb_server:getOwnedHouse', function(src, house)
            local key = false
            local player = pr_lib.framework.GetPlayer(src)
            if not player then return false end
            
            local license = player.PlayerData and player.PlayerData.license or player.license or ""
            local cid = player.PlayerData and player.PlayerData.citizenid or player.citizenid or ""
            local houseKey = false
            
            if GetResourceState("qb-houses") ~= "missing" then
                houseKey = exports['ps-housing']:IsOwner(src, house)
            elseif GetResourceState("ps-housing") ~= "missing" then
                houseKey = exports['ps-housing']:IsOwner(src, house)
            end
        
            if houseKey then key = not key end
            return key
        end)
        
        --- Call from qb-phone
        RegisterNetEvent('forge_garage:server:houseGarageConfig', function(data)
            Config.HouseGarages = data
        end)
        
        RegisterNetEvent('forge_garage:server:addHouseGarage', function(house, garageInfo)
            Config.HouseGarages[house] = garageInfo
        end)
    end
end
