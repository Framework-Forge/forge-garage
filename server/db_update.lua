local UPDATE_SQL = {
    ADD_COLUMN_BALANCE = 'ALTER TABLE player_vehicles ADD balance int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_PAYMENTAMOUNT = 'ALTER TABLE player_vehicles ADD paymentamount int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_PAYMENTSLEFT = 'ALTER TABLE player_vehicles ADD paymentsleft int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_FINANCETIME = 'ALTER TABLE player_vehicles ADD financetime int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_VEHICLE_NAME = 'ALTER TABLE player_vehicles ADD vehicle_name longtext DEFAULT NULL;',
    ADD_COLUMN_DEFORMATION = 'ALTER TABLE player_vehicles ADD deformation longtext DEFAULT NULL;',
    ADD_COLUMN_FAKEPLATE = 'ALTER TABLE player_vehicles ADD fakeplate varchar(50) DEFAULT NULL;',
    ADD_COLUMN_PARKING_COORDS = 'ALTER TABLE player_vehicles ADD parking_coords varchar(255) DEFAULT NULL;',
}

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        local results = {}
        for k, v in pairs(UPDATE_SQL) do
            local status, err = pcall(function()
                MySQL.Sync.execute(v, {})
            end)
            if not status and not string.find(string.lower(err), 'duplicate') then
                results[#results + 1] = {
                    script = k,
                    error = err
                }
            end
        end
        if #results > 0 then
            print(string.format('^1Errors: %s^0', json.encode(results)))
        end
    end
end)
