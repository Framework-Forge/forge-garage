gb = {}

local GarageBlip = {} ---@type table<string, integer>

local function tableKeys(source)
    local keys = {}
    if type(source) ~= "table" then return keys end

    local lastKey = nil
    while true do
        local ok, key = pcall(next, source, lastKey)
        if not ok or key == nil then break end
        keys[#keys + 1] = key
        lastKey = key
    end

    return keys
end

--- Refresh Blip
---@param data table <string, GarageData>
function gb.refresh ( data )
    data = data or GarageZone
    if not data or type(data) ~= "table" then return end
    local blipKeys = tableKeys(GarageBlip)
    for i = 1, #blipKeys do
        local k = blipKeys[i]
        local v = GarageBlip[k]
        if DoesBlipExist(v) then
            RemoveBlip(v)
        end
    end

    GarageBlip = {}
    local garageKeys = tableKeys(data)
    for i = 1, #garageKeys do
        local k = garageKeys[i]
        local v = data[k]
        if v.blip then
            local location ---@as vector3
            local points = v.zones and v.zones.points or nil
           
            if type(points) == 'table' then
                for i=1, #points do
                    location = points[i]
                end
            elseif v.ipl and v.ipl.entries and v.ipl.entries[1] and v.ipl.entries[1].coords then
                location = v.ipl.entries[1].coords
            elseif v.ipl and v.ipl.entry then
                location = v.ipl.entry
            end

            if location then
                GarageBlip[k] = AddBlipForCoord(location.x, location.y, location.z)
                SetBlipSprite(GarageBlip[k], v.blip.type)
                SetBlipScale(GarageBlip[k], 0.9)
                SetBlipColour(GarageBlip[k], v.blip.color)
                SetBlipDisplay(GarageBlip[k], 4)
                SetBlipAsShortRange(GarageBlip[k], true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(v.blip.label or k)
                EndTextCommandSetBlipName(GarageBlip[k])
            end
        end
    end
end
