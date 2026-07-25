GarageDB = {}

local function sanitize(plate)
    return plate:gsub("%s+", ""):upper()
end

local function normalizePlate(plate)
    if not plate then return nil end
    return tostring(plate):gsub("%s+", ""):upper()
end

local QBShared = nil
local function getQBShared()
    if not QBShared then
        local QBCore = exports['qb-core']:GetCoreObject()
        if QBCore then
            QBShared = QBCore.Shared
        end
    end
    return QBShared
end

--- Get Player Vehicles By Garage
function GarageDB.gpvbg(src, garage, filter)
    local Identifier = pr_lib.framework.GetIdentifier(src)
    if not Identifier then return {} end

    local keys = {}
    local success, err = pcall(function()
        return exports['pr_carkeys']:GetKeys(src)
    end)
    if success and err then
        keys = err
    end

    if not keys or #keys == 0 then
        return {}
    end

    local format, value

    if Config.VehiclesInAllGarages then
        format = [[
            SELECT pv.vehicle, pv.vehicle_name, pv.mods, pv.state, pv.depotprice, pv.plate, pv.fakeplate, pv.fuel, pv.engine, pv.body, pv.deformation
            FROM player_vehicles pv WHERE pv.plate IN (?)
        ]]
        value = {keys}
    else
        format = [[
            SELECT pv.vehicle, pv.vehicle_name, pv.mods, pv.state, pv.depotprice, pv.plate, pv.fakeplate, pv.fuel, pv.engine, pv.body, pv.deformation
            FROM player_vehicles pv WHERE pv.plate IN (?) AND pv.garage = ? AND pv.state = ?
        ]]
        value = {keys, garage, 1}
    end

    if filter and not Config.VehiclesInAllGarages then
        if not filter.impound then
            if filter.shared then
                format = [[
                    SELECT
                        pv.vehicle, pv.vehicle_name, pv.mods, pv.state, pv.depotprice, pv.plate, pv.fakeplate, pv.fuel, pv.engine, pv.body, pv.deformation, p.charinfo
                    FROM player_vehicles pv LEFT JOIN players p ON p.citizenid = pv.citizenid WHERE pv.plate IN (?) AND pv.garage = ? AND pv.state = ?
                ]]
                value = {keys, garage, 1}
            end
        else
            format = [[
                SELECT pv.vehicle, pv.vehicle_name, pv.mods, pv.state, pv.depotprice, pv.plate, pv.fakeplate, pv.fuel, pv.engine, pv.body, pv.deformation
                FROM player_vehicles pv WHERE pv.plate IN (?) AND pv.state = 0
            ]]
            value = {keys}
        end
    end

    local vehicles = {}
    local results = MySQL.query.await(format, value)

    if results and #results > 0 then
        for i=1, #results do
            local data = results[i]
            local mods = json.decode(data.mods)
            local deformation = json.decode(data.deformation)
            local state = data.state
            local model = data.vehicle
            local plate = data.plate
            local depotprice = data.depotprice
            local fakeplate = data.fakeplate

            vehicles[#vehicles+1] = {
                vehicle = mods,
                vehicle_name = data.vehicle_name,
                fuel = data.fuel or 100,
                engine = data.engine,
                body = data.body,
                state = state,
                model = model,
                plate = plate,
                fakeplate = fakeplate,
                depotprice = depotprice,
                deformation = deformation
            }

            if filter and filter.shared and data.charinfo then
                local charinfo = json.decode(data.charinfo)
                if charinfo then
                    local ownername = ("%s %s"):format(charinfo.firstname, charinfo.lastname)
                    vehicles[#vehicles].owner = ownername
                end
            end
        end
    end

    return vehicles
end

--- Get Player Vehicle By Plate
function GarageDB.gpvbp(plate)
    local result = MySQL.single.await([[
        SELECT 
            pv.citizenid,
            pv.vehicle,
            pv.vehicle_name,
            pv.mods,
            pv.plate,
            pv.fakeplate,
            pv.garage,
            pv.fuel,
            pv.engine,
            pv.body,
            pv.state,
            pv.depotprice,
            pv.balance,
            p.charinfo
        FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid WHERE pv.plate = ? OR pv.fakeplate = ?
    ]], {plate, plate})
    if not result then return false end

    local charinfo = result.charinfo and json.decode(result.charinfo)
    local ownername = charinfo and ("%s %s"):format(charinfo.firstname, charinfo.lastname) or "Unknown Owner"

    return {
        owner = {
            name = ownername,
            citizenid = result.citizenid,
        },
        vehicle = json.decode(result.mods),
        vehicle_name = result.vehicle_name,
        mods = json.decode(result.mods),
        model = joaat(result.vehicle),
        fuel = result.fuel or 100,
        engine = result.engine,
        body = result.body,
        state = result.state,
        plate = result.plate,
        fakeplate = result.fakeplate,
        garage = result.garage,
        depotprice = result.depotprice,
        balance = result.balance,
        deformation = json.decode(result.deformation)
    }
end

--- Update Vehicle State
function GarageDB.uvs(plate, state, garage, parking_coords)
    if state ~= 1 then
        parking_coords = nil
    end
    local normalizedPlate = normalizePlate(plate)
    local Update = MySQL.update.await([[
        UPDATE player_vehicles
        SET state = ?, garage = ?, parking_coords = ?
        WHERE plate = ? OR fakeplate = ?
            OR REPLACE(UPPER(plate), ' ', '') = ?
            OR REPLACE(UPPER(fakeplate), ' ', '') = ?
    ]], {state, garage, parking_coords, plate, plate, normalizedPlate, normalizedPlate})
    return Update > 0
end

--- Update Vehicle State Police Impound
function GarageDB.uvspi(plate, state)
    local update = MySQL.update.await("UPDATE player_vehicles SET state = ? WHERE plate = ? OR fakeplate = ?", {state, plate, plate})
    return update > 0
end

--- Swap Vehicle Garage
function GarageDB.svg(newgarage, plate)
    local update = MySQL.update.await("UPDATE player_vehicles SET garage = ? WHERE plate = ? OR fakeplate = ?", {newgarage, plate, plate})
    return update > 0
end

--- Update Vehicle Owner (Transfer)
function GarageDB.uvo(oldOwnerId, newOwnerId, plate)
    local mp = pr_lib.framework.GetPlayer(oldOwnerId)
    local tp = pr_lib.framework.GetPlayer(newOwnerId)
    if not mp then return false end
    if not tp then return false, GarageBridge.locale("notify.error.player_offline", newOwnerId) end

    local tpLicense = (tp.PlayerData and tp.PlayerData.license) or tp.license
    local tpCitizenid = (tp.PlayerData and tp.PlayerData.citizenid) or tp.citizenid
    local mpCitizenid = (mp.PlayerData and mp.PlayerData.citizenid) or mp.citizenid

    local update = MySQL.update.await("UPDATE player_vehicles SET license = ?, citizenid = ? WHERE citizenid = ? AND (plate = ? OR fakeplate = ?)", {
        tpLicense,
        tpCitizenid,
        mpCitizenid,
        plate,
        plate
    })
    return update > 0
end

--- Get Vehicle Owner By Plate
function GarageDB.gvobp(src, plate, filter, pleaseUpdate)
    local identifier = pr_lib.framework.GetIdentifier(src)
    if not identifier then return false end

    local format = [[
        SELECT
            pv.vehicle, p.charinfo
        FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid
            WHERE
                pv.plate = ? OR pv.fakeplate = ?
    ]]
    local value = {plate, plate}

    if filter and filter.onlyOwner then
        format = [[
            SELECT
                pv.vehicle, p.charinfo
            FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid
                WHERE
                    (pv.plate = ? OR pv.fakeplate = ?) AND pv.citizenid = ?
        ]]
        value = {plate, plate, identifier}
    end

    local results = MySQL.single.await(format, value)
    if not results then return false end
    local charinfo = json.decode(results.charinfo)
    local ownername = charinfo and ("%s %s"):format(charinfo.firstname, charinfo.lastname) or "Unknown Owner"

    if pleaseUpdate then
        MySQL.update([[
            UPDATE
                player_vehicles
                    SET
                vehicle_name = ?, mods = ?, fuel = ?, engine = ?, body = ?, deformation = ? WHERE plate = ? OR fakeplate = ?
        ]], {
            pleaseUpdate.vehicle_name,
            json.encode(pleaseUpdate.mods),
            math.floor(pleaseUpdate.fuel),
            math.floor(pleaseUpdate.engine),
            math.floor(pleaseUpdate.body),
            json.encode(pleaseUpdate.deformation),
            plate,
            plate
        })
    end

    return {
        vehmodel = results.vehicle,
        ownername = ownername
    }
end

--- Get Vehicles For Phone
function GarageDB.gvfp(src)
    local citizenid = pr_lib.framework.GetIdentifier(src)
    if not citizenid then return {} end

    local results = MySQL.query.await([[
            SELECT
                vehicle,
                plate,
                garage,
                fuel,
                engine,
                body,
                state,
                paymentsleft
            FROM player_vehicles WHERE citizenid = ?
    ]], {citizenid})

    local vehicles = {}
    if results and results[1] then
        local sharedData = getQBShared()
        for i=1, #results do
            local v = results[i]
            local plate = utils.string.trim(v.plate)
            local vd = sharedData and sharedData.Vehicles[v.vehicle]
            local brand = vd and vd.brand
            local name = vd and vd.name
            local defaultname = brand and ("%s %s"):format(brand, name)
            local customName = CNV[plate] and CNV[plate].name
            local vehname = customName or defaultname

            local stateText = GarageBridge.locale('status.in')

            if v.state == 0 then
                stateText = vehFuncS.govbp(plate) and GarageBridge.locale('status.out') or GarageBridge.locale('status.insurance')
            elseif v.state == 2 then
                stateText = GarageBridge.locale('status.confiscated')
            end

            local inInsurance = v.state == 0
            local inPoliceImpound = v.state == 2

            local engine = v.engine > 1000 and 1000 or v.engine
            local body = v.body > 1000 and 1000 or v.body

            vehicles[#vehicles+1] = {
                fullname = vehname,
                brand = brand or '',
                model = name or '',
                plate = plate,
                garage = v.garage,
                state = stateText,
                fuel = v.fuel,
                engine = engine,
                body = body,
                paymentsleft = v.paymentsleft,
                disableTracking = inInsurance or inPoliceImpound,
            }
        end
    end
    return vehicles
end

--- Insert new vehicle to database
function GarageDB.inv(vehicle)
    MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        vehicle.license,
        vehicle.citizenid,
        vehicle.model,
        joaat(vehicle.model),
        json.encode(vehicle.props),
        vehicle.plate,
        0
    })
end

--- Update Vehicle Owner By CitizenID (Transfer)
function GarageDB.uvoByCitizenId(oldOwnerId, newCitizenId, plate)
    local mp = pr_lib.framework.GetPlayer(oldOwnerId)
    if not mp then return false, "player_offline" end
    local mpCitizenid = (mp.PlayerData and mp.PlayerData.citizenid) or mp.citizenid

    local target = MySQL.single.await("SELECT citizenid, license, charinfo FROM players WHERE citizenid = ?", {newCitizenId})
    if not target then
        return false, "citizenid_not_found"
    end

    local tpLicense = target.license
    local charinfo = json.decode(target.charinfo)
    local newOwnerName = charinfo and ("%s %s"):format(charinfo.firstname, charinfo.lastname) or newCitizenId

    -- Check if target player is online to notify them
    local tp = pr_lib.framework.GetPlayerFromIdentifier(newCitizenId)

    local update = MySQL.update.await("UPDATE player_vehicles SET license = ?, citizenid = ? WHERE citizenid = ? AND (plate = ? OR fakeplate = ?)", {
        tpLicense,
        newCitizenId,
        mpCitizenid,
        plate,
        plate
    })

    if update > 0 then
        if tp then
            local tpSource = (tp.PlayerData and tp.PlayerData.source) or tp.source
            utils.notify(tpSource, GarageBridge.locale("notify.success.transferveh.target", pr_lib.framework.GetPlayerName(oldOwnerId), ""), "success")
        end
        return true, newOwnerName
    end
    return false, "db_error"
end

--- Get Persistent Vehicles In Garage
function GarageDB.getPersistentVehicles(garageName)
    local results = MySQL.query.await([[
        SELECT plate, vehicle, vehicle_name, mods, deformation, fuel, engine, body, parking_coords
        FROM player_vehicles
        WHERE garage = ? AND state = 1 AND parking_coords IS NOT NULL
    ]], {garageName})
    return results or {}
end
