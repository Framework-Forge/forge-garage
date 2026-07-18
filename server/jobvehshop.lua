RegisterNetEvent('forge_garage:server:buyVehicle', function(vehData)
    if GetInvokingResource() then return end
    local citizenid = pr_lib.framework.GetIdentifier(source)
    local Player = pr_lib.framework.GetPlayer(source)
    local license = Player and (Player.PlayerData?.license or Player.license) or ""
    vehData.citizenid = citizenid
    vehData.license = license
    if pr_lib.framework.RemovePlayerAccountBalance(source, 'bank', vehData.price, "Job vehicle purchase") then
        GarageDB.inv(vehData)
        utils.notify(source, locale('notify.success.vehicleshop.buyVehicle', vehData.label, vehData.price), 'success', 8000)
    end
end)