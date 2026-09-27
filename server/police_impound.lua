if not Config.UsePoliceImpound then return end

local function cleanText(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    return value:sub(1, maxLength)
end

local function cleanPlate(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('%s+', ''):upper()
    return value ~= '' and value:sub(1, 50) or nil
end

local function decodeJson(value)
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function isTruthy(value)
    return value == true or value == 1 or value == '1'
end

local function callForgePolice(exportName, ...)
    if GetResourceState('forge-police') ~= 'started' then return true, nil end
    local args = { ... }
    local ok, result = pcall(function()
        if exportName == 'register' then
            return exports['forge-police']:RegisterGarageImpound(table.unpack(args))
        elseif exportName == 'rollback' then
            return exports['forge-police']:RollbackGarageImpound(table.unpack(args))
        elseif exportName == 'paid' then
            return exports['forge-police']:SetGarageImpoundPaid(table.unpack(args))
        elseif exportName == 'release' then
            return exports['forge-police']:ReleaseGarageImpound(table.unpack(args))
        end
    end)
    if not ok then
        print(('[forge-garage][impound] forge-police export %s failed: %s'):format(exportName, tostring(result)))
        return false, result
    end
    return true, result
end

local function createImpoundInvoice(data)
    if GetResourceState('Renewed-Banking') ~= 'started' or type(data) ~= 'table' or not data.externalId then return false end
    local ok, result = pcall(function()
        return exports['Renewed-Banking']:CreateInvoice({
            externalId=data.externalId, recipient=data.citizenid,
            issuer='Departamento de Polícia', receiverAccount='police',
            title='Apreensão de veículo',
            description=('Placa: %s. Motivo: %s. Local: %s.%s'):format(
                tostring(data.plate), tostring(data.reason), tostring(data.garage),
                data.notes and (' Observações: ' .. data.notes) or ''),
            amount=data.fine, dueAt=data.holdUntil,
            metadata={kind='impound',impoundId=data.impoundId,plate=data.plate,garage=data.garage}
        })
    end)
    if not ok or type(result) ~= 'table' or result.success ~= true then
        print(('[forge-garage][impound] Banking invoice %s failed: %s'):format(tostring(data.externalId), tostring(result)))
        return false
    end
    return true
end

GarageBridge.callback.register("forge_garage:cb_server:policeImpound.getVehicle", function (_, garage)
    local dataToSend = {}
    local result = pr_lib.database.query("SELECT * FROM police_impound WHERE garage = ?", {garage})
    if result and next(result) then
        for k, v in pairs(result) do
            dataToSend[#dataToSend+1] = {
                citizenid = v.citizenid,
                props = decodeJson(v.props),
                deformation = decodeJson(v.deformation),
                plate = v.plate,
                vehicle = v.vehicle,
                owner = v.owner,
                officer = v.officer,
                fine = v.fine,
                paid = v.paid,
                date = v.date,
                reason = v.reason,
                notes = v.notes,
            }
        end
    end
    return dataToSend
end)

GarageBridge.callback.register("forge_garage:cb_server:policeImpound.impoundveh", function (source, impoundData)
    if type(impoundData) ~= 'table' then return false end

    local plateKey = cleanPlate(impoundData.plate)
    local reason = cleanText(impoundData.reason, 100)
    local notes = cleanText(impoundData.notes, 500)
    local garage = cleanText(impoundData.garage, 120)
    local fine = math.floor(tonumber(impoundData.fine) or -1)
    local holdUntil = math.floor(tonumber(impoundData.date) or 0)
    if not plateKey or not reason or #reason < 3 or not garage or fine < 0 or fine > 1000000 or holdUntil <= 0 then
        return false
    end

    local vehicle = pr_lib.database.single([[
        SELECT id, citizenid, plate, vehicle, vehicle_name
        FROM player_vehicles
        WHERE UPPER(REPLACE(plate, ' ', '')) = ? OR UPPER(REPLACE(fakeplate, ' ', '')) = ?
        LIMIT 1
    ]], { plateKey, plateKey })
    if not vehicle then return false end

    local policeResult
    local policeOk, policeResponse = callForgePolice('register', source, {
        plate = vehicle.plate,
        reason = reason,
        notes = notes,
        fee = fine,
        garage = garage,
        holdUntil = holdUntil,
    })
    if not policeOk or (policeResponse and policeResponse.success == false) then
        print(('[forge-garage][impound] forge-police rejected %s: %s'):format(
            plateKey, tostring(policeResponse and policeResponse.message or policeResponse)))
        return false
    end
    policeResult = policeResponse
    local invoiceExternal = policeResult and policeResult.impoundId and ('impound:' .. tostring(policeResult.impoundId)) or nil

    local dbOk, success = pcall(function()
        return pr_lib.database.transaction({
            {
                query = "DELETE FROM police_impound WHERE UPPER(REPLACE(plate, ' ', '')) = ?",
                values = { plateKey },
            },
            {
                query = [[INSERT INTO police_impound
                    (citizenid, plate, vehicle, props, owner, officer, reason, notes, deformation, date, fine, garage, bank_invoice_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                values = {
                    vehicle.citizenid, vehicle.plate,
                    cleanText(impoundData.vehicle, 255) or vehicle.vehicle_name or vehicle.vehicle,
                    json.encode(type(impoundData.prop) == 'table' and impoundData.prop or {}),
                    cleanText(impoundData.owner, 255) or vehicle.citizenid,
                    cleanText(impoundData.officer, 255) or GetPlayerName(source) or 'Desconhecido',
                    reason, notes,
                    json.encode(type(impoundData.deformation) == 'table' and impoundData.deformation or {}),
                    os.date('%d/%m/%Y', holdUntil), fine, garage, invoiceExternal,
                },
            },
            {
                query = 'UPDATE player_vehicles SET state = 2 WHERE id = ?',
                values = { vehicle.id },
            },
        })
    end)

    if not dbOk or success ~= true then
        if not dbOk then
            print(('[forge-garage][impound] database transaction failed for %s: %s'):format(plateKey, tostring(success)))
        end
        if policeResult and policeResult.impoundId then
            callForgePolice('rollback', policeResult.impoundId, vehicle.plate)
        end
        return false
    end
    if invoiceExternal then
        createImpoundInvoice({externalId=invoiceExternal,citizenid=vehicle.citizenid,plate=vehicle.plate,
            reason=reason,notes=notes,garage=garage,fine=fine,holdUntil=holdUntil,impoundId=policeResult.impoundId})
    end
    return true
end)

GarageBridge.callback.register("forge_garage:cb_server:policeImpound.cekDate", function (_, date )
    if type(date) ~= 'string' then return false, 0 end
    local d, m, y = date:match("(%d+)/(%d+)/(%d+)")
    if not d or not m or not y then return false, 0 end
    local targetTime = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    local secondsLeft = targetTime - os.time()
    return secondsLeft <= 0, math.max(0, math.ceil(secondsLeft / 86400))
end)

--- events
RegisterNetEvent('forge_garage:server:removeFromPoliceImpound', function( plate )
    if GetInvokingResource() then return end
    local src = source
    local plateKey = cleanPlate(plate)
    if not plateKey then return end
    local row = pr_lib.database.single([[
        SELECT citizenid, plate, paid FROM police_impound
        WHERE UPPER(REPLACE(plate, ' ', '')) = ? LIMIT 1
    ]], { plateKey })
    if not row or pr_lib.framework.GetIdentifier(src) ~= row.citizenid or not isTruthy(row.paid) then return end
    local policeOk = callForgePolice('release', row.plate)
    if not policeOk then return end
    GarageDB.uvspi(row.plate, 0)
end)

RegisterNetEvent('forge_garage:server:policeImpound.sendBill', function( citizenid, fine, plate )
    if GetInvokingResource() then return end
    local src = source
    local plateKey = cleanPlate(plate)
    if not plateKey then return end
    local row = pr_lib.database.single([[
        SELECT citizenid, plate, fine, paid FROM police_impound
        WHERE UPPER(REPLACE(plate, ' ', '')) = ? LIMIT 1
    ]], { plateKey })
    if not row or pr_lib.framework.GetIdentifier(src) ~= row.citizenid or isTruthy(row.paid) then return end
    local Player = pr_lib.framework.GetPlayerFromIdentifier(row.citizenid)
    if not Player then return end
    local playerSource = Player.PlayerData and Player.PlayerData.source or Player.source
    if tonumber(playerSource) ~= tonumber(src) then return end
    local paid = GarageBridge.callback.await("forge_garage:cb_client:sendFine", playerSource, tonumber(row.fine) or 0)
    if paid then
        pr_lib.database.update("UPDATE police_impound SET paid = 1 WHERE plate = ?", { row.plate })
        callForgePolice('paid', row.plate)
        local externalId = pr_lib.database.scalar('SELECT bank_invoice_id FROM police_impound WHERE plate=? LIMIT 1', {row.plate})
        if externalId and GetResourceState('Renewed-Banking') == 'started' then
            pcall(function() exports['Renewed-Banking']:ResolveInvoice(externalId, 'paid') end)
        end
    end
end)

AddEventHandler('Renewed-Banking:server:invoicePaid', function(invoice)
    if type(invoice) ~= 'table' or invoice.issuerResource ~= 'forge-garage' then return end
    local metadata = invoice.metadata
    if type(metadata) ~= 'table' or metadata.kind ~= 'impound' or not metadata.plate then return end
    pr_lib.database.update('UPDATE police_impound SET paid=1 WHERE UPPER(REPLACE(plate,\' \',\'\'))=?', {cleanPlate(metadata.plate)})
    callForgePolice('paid', metadata.plate)
end)

CreateThread(function()
    while true do
        Wait(30000)
        if GetResourceState('Renewed-Banking') == 'started' then
            local rows = pr_lib.database.query([[SELECT p.*,m.id AS impound_id,m.hold_until FROM police_impound p
                LEFT JOIN mdt_impound m ON m.plate=p.plate AND m.status='active'
                WHERE p.paid=0 AND p.fine>0 LIMIT 250]]) or {}
            for _, row in ipairs(rows) do
                local externalId = row.bank_invoice_id or (row.impound_id and ('impound:' .. tostring(row.impound_id)))
                if externalId then
                    if not row.bank_invoice_id then
                        pr_lib.database.update('UPDATE police_impound SET bank_invoice_id=? WHERE plate=? AND bank_invoice_id IS NULL',
                            {externalId,row.plate})
                    end
                    createImpoundInvoice({externalId=externalId,citizenid=row.citizenid,plate=row.plate,
                        reason=row.reason,notes=row.notes,garage=row.garage,fine=row.fine,
                        holdUntil=tonumber(row.hold_until) or os.time(),impoundId=row.impound_id})
                end
            end
        end
    end
end)
