local UPDATE_SQL = {
    ADD_COLUMN_BALANCE = 'ALTER TABLE player_vehicles ADD balance int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_PAYMENTAMOUNT = 'ALTER TABLE player_vehicles ADD paymentamount int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_PAYMENTSLEFT = 'ALTER TABLE player_vehicles ADD paymentsleft int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_FINANCETIME = 'ALTER TABLE player_vehicles ADD financetime int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_VEHICLE_NAME = 'ALTER TABLE player_vehicles ADD vehicle_name longtext DEFAULT NULL;',
    ADD_COLUMN_DEFORMATION = 'ALTER TABLE player_vehicles ADD deformation longtext DEFAULT NULL;',
    ADD_COLUMN_FAKEPLATE = 'ALTER TABLE player_vehicles ADD fakeplate varchar(50) DEFAULT NULL;',
    ADD_COLUMN_PARKING_COORDS = 'ALTER TABLE player_vehicles ADD parking_coords varchar(255) DEFAULT NULL;',
    ADD_POLICE_IMPOUND_REASON = 'ALTER TABLE police_impound ADD reason varchar(100) DEFAULT NULL;',
    ADD_POLICE_IMPOUND_NOTES = 'ALTER TABLE police_impound ADD notes text DEFAULT NULL;',
    ADD_POLICE_IMPOUND_DEFORMATION = 'ALTER TABLE police_impound ADD deformation longtext DEFAULT NULL;',
    ADD_POLICE_IMPOUND_BANK_INVOICE = 'ALTER TABLE police_impound ADD bank_invoice_id varchar(120) DEFAULT NULL;',
    CREATE_PARKING_SESSIONS = [[CREATE TABLE IF NOT EXISTS forge_garage_parking_sessions (
        plate varchar(50) NOT NULL,
        garage varchar(120) NOT NULL,
        meter_id varchar(80) DEFAULT NULL,
        parked_at bigint NOT NULL,
        paid_until bigint DEFAULT NULL,
        updated_at bigint NOT NULL,
        PRIMARY KEY (plate),
        KEY garage (garage)
    );]],
    CREATE_PARKING_DEBTS = [[CREATE TABLE IF NOT EXISTS forge_garage_parking_debts (
        plate varchar(50) NOT NULL,
        garage varchar(120) DEFAULT NULL,
        meter_id varchar(80) DEFAULT NULL,
        amount int NOT NULL DEFAULT 0,
        active tinyint NOT NULL DEFAULT 1,
        session_parked_at bigint DEFAULT NULL,
        session_charged_at bigint DEFAULT NULL,
        reported_at bigint DEFAULT NULL,
        report_reference varchar(120) DEFAULT NULL,
        updated_at bigint NOT NULL,
        PRIMARY KEY (plate),
        KEY active (active)
    );]],
}

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        while not pr_lib.database.isReady() do Wait(100) end
        local results = {}
        for k, v in pairs(UPDATE_SQL) do
            local status, err = pcall(function()
                -- Avoid duplicate-column errors: legacy drivers may not invoke callbacks on SQL errors.
                local tableName, columnName = v:match('^ALTER TABLE ([%w_]+) ADD ([%w_]+)')
                if tableName then
                    local exists = pr_lib.database.scalar(
                        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
                        { tableName, columnName }
                    )
                    assert(exists ~= nil, 'Could not inspect schema for ' .. tableName)
                    if tonumber(exists) > 0 then return end
                end
                assert(pr_lib.database.execute(v, {}) ~= nil, 'Database returned no result')
            end)
            local errorText = string.lower(tostring(err))
            if not status and not string.find(errorText, 'duplicate', 1, true) then
                results[#results + 1] = {
                    script = k,
                    error = tostring(err)
                }
            end
        end
        if #results > 0 then
            print(string.format('^1Errors: %s^0', json.encode(results)))
        end
    end
end)
