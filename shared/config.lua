Config = {}

-- Load garage and vehicle data from JSON files
GarageZone = GarageBridge.loadJson('data.garages') ---@type table<string, GarageData>
CNV = GarageBridge.loadJson('data.vehiclesname') ---@type table<string, CustomName>

Config.Target = 'ox'           -- ox / qb
Config.RadialMenu = 'native'   --- interação local; não depende de bibliotecas externas
Config.FuelScript = 'cdn-fuel' --- forge_fuel / ox_fuel / LegacyFuel / ps-fuel / cdn-fuel
Config.changeNamePrice = 15000 --- price for changing the name of the vehicle in the garage
Config.SpawnInVehicle = false  --- change this to true if you want the player to immediately enter the vehicle when the vehicle is taken out of the garage
Config.VehiclesInAllGarages = false --- Opção ZAP: deixe true para todos os veículos do player aparecerem em todas as garagens
Config.DisableVehicleCamera = false --- Desativa a movimentação de câmera ao puxar o veículo
Config.LocateVehicleOutGarage = true --- Opção ZAP: encontrar veículos fora da garagem
Config.PersistentDistance = 120.0 --- Distância para veículo persistente aparecer/sumir no bucket

-- Criador de garagens publicas para integracoes imobiliarias.
-- O export client-side `createPropertyGarage` tambem valida o emprego no servidor.
Config.PropertyGarageCreator = {
    enabled = true,
    jobs = {
        realestate = 0,
    },
    ace = "forge-garage.property.create",
    cooldown = 5000,
    maxZonePoints = 32,
    maxSpawnPoints = 64,
}
-- Cada grupo abaixo representa variantes que ocupam o mesmo interior.
-- Somente um IPL de cada grupo pode permanecer ativo no cliente.
Config.ExclusiveGarageIplGroups = {
    { "imp_dt1_02_cargarage_a", "imp_dt1_02_cargarage_b", "imp_dt1_02_cargarage_c" },
    { "imp_dt1_11_cargarage_a", "imp_dt1_11_cargarage_b", "imp_dt1_11_cargarage_c" },
    { "imp_sm_13_cargarage_a", "imp_sm_13_cargarage_b", "imp_sm_13_cargarage_c" },
    { "imp_sm_15_cargarage_a", "imp_sm_15_cargarage_b", "imp_sm_15_cargarage_c" }
}

-- IPLs auxiliares que o bob74_ipl carregava junto das garagens CEO.
-- Eles nunca devem permanecer ativos durante uma instancia do forge-garage.
Config.GarageIplCleanup = {
    "imp_dt1_02_modgarage",
    "imp_dt1_11_modgarage",
    "imp_sm_13_modgarage",
    "imp_sm_15_modgarage"
}

-- Entity sets padrao exigidos pelas garagens CEO do DLC Import/Export.
-- Sem garage_decor_01 o casco carrega, mas pisos, escadas e acabamentos ficam ausentes.
Config.GarageIplDefaults = {
    ["imp_dt1_02_cargarage_a"] = { interiorId = 253441, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_dt1_02_cargarage_b"] = { interiorId = 253697, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_dt1_02_cargarage_c"] = { interiorId = 253953, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_dt1_11_cargarage_a"] = { interiorId = 254465, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_dt1_11_cargarage_b"] = { interiorId = 254721, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_dt1_11_cargarage_c"] = { interiorId = 254977, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_sm_13_cargarage_a"] = { interiorId = 255489, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_sm_13_cargarage_b"] = { interiorId = 255745, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_sm_13_cargarage_c"] = { interiorId = 256001, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_sm_15_cargarage_a"] = { interiorId = 256513, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_sm_15_cargarage_b"] = { interiorId = 256769, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } },
    ["imp_sm_15_cargarage_c"] = { interiorId = 257025, entitySets = { "garage_decor_01", "lighting_option01", "numbering_style01_n1" } }
}

-- Compatibilidade com garagens criadas antes da separacao dos modelos A/B/C.
-- Esses arrays antigos ativavam tres variantes sobrepostas e simulavam andares inexistentes.
Config.GarageIplMigrationApplied = false
for _, garage in pairs(GarageZone or {}) do
    local ipl = garage and garage.ipl
    if ipl and type(ipl.model) == "table" then
        local originalModels = ipl.model
        local normalizedModels = {}
        local selectedGroups = {}

        for modelIndex = 1, #originalModels do
            local modelName = originalModels[modelIndex]
            local exclusiveGroup = nil

            for groupIndex = 1, #Config.ExclusiveGarageIplGroups do
                local group = Config.ExclusiveGarageIplGroups[groupIndex]
                for memberIndex = 1, #group do
                    if group[memberIndex] == modelName then
                        exclusiveGroup = groupIndex
                        break
                    end
                end
                if exclusiveGroup then break end
            end

            if not exclusiveGroup or not selectedGroups[exclusiveGroup] then
                normalizedModels[#normalizedModels + 1] = modelName
                if exclusiveGroup then selectedGroups[exclusiveGroup] = true end
            end
        end

        if #normalizedModels < #originalModels then
            ipl.model = #normalizedModels == 1 and normalizedModels[1] or normalizedModels
            Config.GarageIplMigrationApplied = true

            if type(ipl.label) == "string" then
                ipl.label = ipl.label:gsub("3 Floors", "Modelo A")
            end

            if type(ipl.floors) == "table" and #ipl.floors == #originalModels then
                ipl.floors = { ipl.floors[1] }
                ipl.exit = ipl.floors[1] and (ipl.floors[1].coords or ipl.floors[1]) or ipl.exit
            end
        end
    end
end

Config.GarageIpls = {
    { label = "CEO Garage - Arcadius Modelo A", ipl = "imp_dt1_02_cargarage_a", preview = vec4(-191.0133, -579.1428, 135.0, 0.0) },
    { label = "CEO Garage - Arcadius Modelo B", ipl = "imp_dt1_02_cargarage_b", preview = vec4(-117.4989, -568.1132, 135.0, 0.0) },
    { label = "CEO Garage - Arcadius Modelo C", ipl = "imp_dt1_02_cargarage_c", preview = vec4(-136.0780, -630.1852, 135.0, 0.0) },
    { label = "CEO Garage - Maze Bank Modelo A", ipl = "imp_dt1_11_cargarage_a", preview = vec4(-84.2193, -823.0851, 221.0, 0.0) },
    { label = "CEO Garage - Maze Bank Modelo B", ipl = "imp_dt1_11_cargarage_b", preview = vec4(-69.8627, -824.7498, 221.0, 0.0) },
    { label = "CEO Garage - Maze Bank Modelo C", ipl = "imp_dt1_11_cargarage_c", preview = vec4(-80.4318, -813.2536, 221.0, 0.0) },
    { label = "CEO Garage - Lombank Modelo A", ipl = "imp_sm_13_cargarage_a", preview = vec4(-1581.1120, -567.2450, 85.5, 0.0) },
    { label = "CEO Garage - Lombank Modelo B", ipl = "imp_sm_13_cargarage_b", preview = vec4(-1568.7390, -562.0455, 85.5, 0.0) },
    { label = "CEO Garage - Lombank Modelo C", ipl = "imp_sm_13_cargarage_c", preview = vec4(-1563.5570, -574.4314, 85.5, 0.0) },
    { label = "CEO Garage - Maze Bank West Modelo A", ipl = "imp_sm_15_cargarage_a", preview = vec4(-1388.8400, -478.7402, 56.1, 0.0) },
    { label = "CEO Garage - Maze Bank West Modelo B", ipl = "imp_sm_15_cargarage_b", preview = vec4(-1388.8600, -478.7574, 48.1, 0.0) },
    { label = "CEO Garage - Maze Bank West Modelo C", ipl = "imp_sm_15_cargarage_c", preview = vec4(-1374.6820, -474.3586, 56.1, 0.0) },
    { label = "Import/Export Vehicle Warehouse - Upper", ipl = "imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_", preview = vec4(994.5925, -3002.5940, -39.64699, 0.0) },
    { label = "Import/Export Vehicle Warehouse - Lower", ipl = "imp_impexp_interior_placement_interior_3_impexp_int_02_milo_", preview = vec4(969.5376, -3000.4110, -48.64689, 0.0) },
    { label = "Criminal Enterprise Vehicle Warehouse", ipl = "reh_int_placement_sum2_interior_0_dlc_int_03_sum2_milo_" },
    { label = "Diamond Casino Loading Bay Garage", ipl = "vw_casino_garage", preview = vec4(2536.276, -278.98, -64.722, 0.0) },
    { label = "Diamond Casino Carpark", ipl = "vw_casino_carpark", preview = vec4(1380.0, 200.0, -50.0, 0.0) },
    { label = "Diamond Casino VIP Carpark", ipl = "vw_casino_carpark", preview = vec4(1295.0, 230.0, -50.0, 0.0) },
    { label = "Agency Garage", ipl = "sf_int_placement_sec_interior_2_dlc_garage_sec_milo_", preview = vec4(-1071.83, -77.96, -95.0, 0.0) },
    { label = "Tuner Garage", ipl = { "tr_tuner_shop_burton", "tr_tuner_shop_mesa", "tr_tuner_shop_mission", "tr_tuner_shop_rancho", "tr_tuner_shop_strawberry" } },
    { label = "Smuggler Hangar", ipl = "sm_smugdlc_interior_placement_interior_0_smugdlc_int_01_milo_", preview = vec4(-1267.0, -3013.135, -49.5, 0.0) },
    { label = "Eclipse Boulevard Garage", ipl = "xm3_garage_fix", preview = vec4(519.2477, -2618.788, -50.0, 0.0) },
    { label = "Freakshop Garage", ipl = { "xm3_warehouse", "xm3_warehouse_grnd" }, preview = vec4(570.9713, -420.0727, -70.0, 0.0) },
    { label = "Chop Shop Salvage Yard", ipl = { "m23_2_sp1_03_reds", "m23_2_sc1_03_reds", "m23_2_id2_04_reds", "m23_2_cs1_05_reds", "m23_2_cs4_11_reds" }, preview = vec4(1077.276, -2274.876, -50.0, 0.0) },
    { label = "Vinewood Garage", ipl = "m23_2_vinewood_garage" },
    { label = "Money Fronts Garage", ipl = "m25_1_garage" },
    { label = "Biker Clubhouse Garage 1", ipl = "bkr_biker_interior_placement_interior_0_biker_dlc_int_01_milo", preview = vec4(1107.04, -3157.399, -37.51859, 0.0) },
    { label = "Biker Clubhouse Garage 2", ipl = "bkr_biker_interior_placement_interior_1_biker_dlc_int_02_milo", preview = vec4(998.4809, -3164.711, -38.90733, 0.0) }
}

--- Additional: (Requires ox_target or qb-target resource)
Config.UseJobVechileShop = false --- Change this to false if you do not want to use the work vehicle shop system from rhd
Config.UsePoliceImpound = true  --- change it to false if you don't want to use the police impound system from rhd

Config.InDevelopment = true     --- Turn this off when you have finished setting up this garage

-- Vehicle transfer settings
Config.TransferVehicle = {
    enable = true,  --- Enable or disable vehicle transfer functionality
    price = 100     --- Price for transferring a vehicle
}

Config.TransferTax = {
    enable = true,
    society = "government",
    percent = 0.10 -- 10% descontado percentual para quem compra e quem vende
}

-- Garage swap settings
Config.SwapGarage = {
    enable = true,  --- Enable or disable garage swapping functionality
    price = 500     --- Price for swapping garages
}

Config.GiveKeys = {
    tempkeys = false, -- true se você quiser dar chaves temporárias quando spawnar o veículo
    enable = true,
    onspawn = true, --- Opção ZAP: deixe true para seu player ganhar do nada uma chave do carro quando spawnar o veículo e remover quando ele guardar (ao invés dele ter que ir comprar em um chaveiro uma cópia)
    price = 500
}

Config.LostKeyPrice = 1000

-- Icon animation settings
Config.IconAnimation = "fade" --- Animation type for icons

-- Icons for different vehicle types
Config.Icons = {
    [8] = "motorcycle",  --- Icon for motorcycles
    [13] = "bicycle",    --- Icon for bicycles
    [14] = "sailboat",   --- Icon for sailboats
    [15] = "helicopter", --- Icon for helicopters
    [16] = "plane",      --- Icon for planes
}

-- Prices for impounding different vehicle types
Config.ImpoundPrice = {
    [0] = 15000,  --- Price for compact cars
    [1] = 15000,  --- Price for sedans
    [2] = 15000,  --- Price for SUVs
    [3] = 15000,  --- Price for coupes
    [4] = 15000,  --- Price for muscle cars
    [5] = 15000,  --- Price for sports classics
    [6] = 15000,  --- Price for sports cars
    [7] = 15000,  --- Price for super cars
    [8] = 15000,  --- Price for motorcycles
    [9] = 15000,  --- Price for off-road vehicles
    [10] = 15000, --- Price for industrial vehicles
    [11] = 15000, --- Price for utility vehicles
    [12] = 15000, --- Price for vans
    [13] = 15000, --- Price for cycles
    [14] = 15000, --- Price for boats
    [15] = 15000, --- Price for helicopters
    [16] = 15000, --- Price for planes
    [17] = 15000, --- Price for service vehicles
    [18] = 0,     --- Price for emergency vehicles
    [19] = 15000, --- Price for military vehicles
    [20] = 15000, --- Price for commercial vehicles
    [21] = 0      --- Price for trains (not applicable)
}

-- Police impound settings
Config.PoliceImpound = {
    Target = {
        groups = {
            police = 0  --- Groups allowed to access police impound
        }
    },
    location = {
        [1] = {
            blip = {
                enable = true,       --- Enable or disable the blip on the map
                sprite = 473,        --- Sprite ID for the blip
                colour = 40          --- Colour ID for the blip
            },
            label = "Pátio do Detran",  --- Label for the police impound location
            zones = {
                points = {
                    vec3(824.69000244141, -1334.0200195312, 26.0),  --- Coordinates for the impound zone
                    vec3(831.70001220703, -1337.2700195312, 26.0),
                    vec3(831.73999023438, -1354.0300292969, 26.0),
                    vec3(832.10998535156, -1355.4799804688, 26.0),
                    vec3(824.72998046875, -1352.0400390625, 26.0),
                },
                thickness = 4.0,  --- Thickness of the zone boundaries
            },
        }
    }
}

-- Job vehicle shop settings
Config.JobVehicleShop = {
    {
        job = 'police',  --- Job associated with the vehicle shop
        label = 'Police Vehicle Shop',  --- Label for the vehicle shop
        ped = {
            model = 'csb_trafficwarden',  --- Pedestrian model for the shop
            coords = vec(457.9160, -1026.4635, 28.4376, 57.2678)  --- Coordinates for the shop
        },
        spawn = vec(443.9391, -1021.4270, 28.2857, 92.6928),  --- Coordinates where vehicles spawn
        vehicle = {
            police = {
                price = 500,  --- Price for the police vehicle
                label = 'Police 1',  --- Label for the vehicle
                prefixPlate = 'POL',  --- Prefix for the vehicle plate
                forRank = {
                    [0] = true,  --- Rank 0 can access this vehicle
                    [1] = true,  --- Rank 1 can access this vehicle
                    [2] = true   --- Rank 2 can access this vehicle
                }
            },
            police2 = {
                price = 500,  --- Price for the second police vehicle
                label = 'Police 2',  --- Label for the second vehicle
                prefixPlate = 'POL',  --- Prefix for the vehicle plate
                forRank = {
                    [0] = true,  --- Rank 0 can access this vehicle
                    [1] = true,  --- Rank 1 can access this vehicle
                    [2] = true   --- Rank 2 can access this vehicle
                }
            }
        },
    }
}

--- Do not modify this section
Config.HouseGarages = {}
