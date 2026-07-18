storage = {}

--- Save garage data
---@param garageData table<string, GarageData>
function storage.SaveGarage(garageData)
    GarageZone = garageData
    TriggerClientEvent('forge_garage:client:syncConfig', -1, GarageZone)
    SaveResourceFile(GetCurrentResourceName(), 'data/garages.json', json.encode(GarageZone), -1)
end

--- Save custom vehicle name data
---@param dataName table<string, CustomName>
function storage.SaveVehicleName(dataName)
    CNV = dataName
    SaveResourceFile(GetCurrentResourceName(), 'data/vehiclesname.json', json.encode(CNV), -1)
end

if Config.GarageIplMigrationApplied then
    CreateThread(function()
        Wait(0)
        storage.SaveGarage(GarageZone)
        print('[forge-garage] migrated legacy overlapping CEO garage IPL models')
    end)
end
