local function showCopyKeysMenu()
    local keys = GarageBridge.callback.await('forge_garage:cb_server:getPlayerKeyItems', false)
    if not keys or #keys == 0 then
        return utils.notify("Você não possui chaves físicas no seu inventário.", "error")
    end

    local options = {}
    for i = 1, #keys do
        local key = keys[i]
        options[#options + 1] = {
            title = ("Modelo: %s"):format(key.modelo),
            description = ("Placa: %s | Serial: %s"):format(key.plate, key.barcode),
            icon = 'key',
            onSelect = function()
                local confirm = pr_lib.alertDialog({
                    header = 'Tirar Cópia da Chave',
                    content = ('Deseja fazer uma cópia da chave do veículo %s por R$%s?'):format(key.plate, Config.GiveKeys.price),
                    centered = true,
                    cancel = true
                }) == "confirm"

                if confirm then
                    if pr_lib.framework.GetMoney('cash') < Config.GiveKeys.price then
                        return utils.notify('Você não possui dinheiro suficiente na carteira.', 'error')
                    end

                    local success, reason = GarageBridge.callback.await('forge_garage:cb_server:copyInventoryKey', false, key.barcode)
                    if success then
                        utils.notify('Cópia da chave criada com sucesso!', 'success')
                    else
                        utils.notify(('Falha ao criar cópia: %s'):format(reason or 'erro desconhecido'), 'error')
                    end
                end
            end
        }
    end

    pr_lib.registerContext({
        id = 'forge_garage:key_manager_copy_list',
        title = 'Tirar Cópia de Chave',
        menu = 'forge_garage:key_manager_main',
        options = options
    })
    pr_lib.showContext('forge_garage:key_manager_copy_list')
end

local function showLostKeysMenu()
    local vehicles = GarageBridge.callback.await('forge_garage:cb_server:getOwnedVehiclesForKeys', false)
    if not vehicles or #vehicles == 0 then
        return utils.notify("Você não possui nenhum veículo registrado em seu nome.", "error")
    end

    local options = {}
    for i = 1, #vehicles do
        local veh = vehicles[i]
        options[#options + 1] = {
            title = veh.vehicle_name,
            description = ("Placa: %s"):format(veh.plate),
            icon = 'car',
            onSelect = function()
                local confirm = pr_lib.alertDialog({
                    header = 'Nova Chave Original',
                    content = ('Deseja comprar uma nova chave original para o veículo %s por R$%s?'):format(veh.plate, Config.LostKeyPrice),
                    centered = true,
                    cancel = true
                }) == "confirm"

                if confirm then
                    if pr_lib.framework.GetMoney('cash') < Config.LostKeyPrice then
                        return utils.notify('Você não possui dinheiro suficiente na carteira.', 'error')
                    end

                    local success, reason = GarageBridge.callback.await('forge_garage:cb_server:buyOriginalKeyForPlate', false, veh.plate)
                    if success then
                        utils.notify('Nova chave original criada com sucesso!', 'success')
                    else
                        utils.notify(('Falha ao criar chave: %s'):format(reason or 'erro desconhecido'), 'error')
                    end
                end
            end
        }
    end

    pr_lib.registerContext({
        id = 'forge_garage:key_manager_lost_list',
        title = 'Perdi Minha Chave',
        menu = 'forge_garage:key_manager_main',
        options = options
    })
    pr_lib.showContext('forge_garage:key_manager_lost_list')
end

local function showTransferMethodMenu(veh)
    pr_lib.registerContext({
        id = 'forge_garage:key_manager_transfer_method',
        title = ('Transferir: %s'):format(veh.plate),
        menu = 'forge_garage:key_manager_transfer_list',
        options = {
            {
                title = 'Jogador Próximo',
                description = 'Transfere o veículo para a pessoa mais próxima de você',
                icon = 'user-friends',
                onSelect = function()
                    local closestPlayer = GarageBridge.getClosestPlayer(GetEntityCoords(GarageBridge.cache.ped), 3.0, false)
                    if not closestPlayer then
                        return utils.notify('Nenhum jogador próximo encontrado.', 'error')
                    end

                    local serverId = GetPlayerServerId(closestPlayer)
                    
                    local inputPrice = pr_lib.inputDialog('Definir Preço de Venda', {
                        {type = 'number', label = 'Valor de Venda (R$)', required = true, min = 0, default = 0},
                    })
                    
                    if not inputPrice or not inputPrice[1] then return end
                    local salePrice = tonumber(inputPrice[1])

                    local confirm = pr_lib.alertDialog({
                        header = 'Vender Veículo',
                        content = ('Deseja vender/transferir o veículo %s para o jogador ID %d pelo valor de R$%s?'):format(veh.plate, serverId, salePrice),
                        centered = true,
                        cancel = true
                    }) == "confirm"

                    if confirm then
                        local clData = {
                            targetSrc = serverId,
                            plate = veh.plate,
                            price = salePrice
                        }
                        GarageBridge.callback('forge_garage:cb_server:transferVehicle', false, function(success, information)
                            if not success then
                                return utils.notify(information or 'Erro ao transferir.', "error")
                            end
                            utils.notify(information, "success")
                        end, clData)
                    end
                end
            },
            {
                title = 'Por CitizenID',
                description = 'Transfere o veículo inserindo o CitizenID (mesmo offline)',
                icon = 'id-card',
                onSelect = function()
                    local input = pr_lib.inputDialog('Vender Veículo', {
                        {type = 'input', label = 'CitizenID do Destinatário', required = true, placeholder = 'ABC12345'},
                        {type = 'number', label = 'Valor de Venda (R$)', required = true, min = 0, default = 0},
                    })

                    if input and input[1] then
                        local targetCitizenId = input[1]:gsub("%s+", ""):upper()
                        local salePrice = tonumber(input[2] or 0)
                        
                        local confirm = pr_lib.alertDialog({
                            header = 'Confirmar Transferência',
                            content = ('Deseja vender/transferir o veículo %s para o CitizenID %s pelo valor de R$%s?'):format(veh.plate, targetCitizenId, salePrice),
                            centered = true,
                            cancel = true
                        }) == "confirm"

                        if confirm then
                            local clData = {
                                targetCitizenId = targetCitizenId,
                                plate = veh.plate,
                                price = salePrice
                            }
                            GarageBridge.callback('forge_garage:cb_server:transferVehicleByCitizenId', false, function(success, information)
                                if not success then
                                    return utils.notify(information or 'Erro ao transferir.', "error")
                                end
                                utils.notify(information, "success")
                            end, clData)
                        end
                    end
                end
            }
        }
    })
    pr_lib.showContext('forge_garage:key_manager_transfer_method')
end

local function showTransferListMenu()
    local vehicles = GarageBridge.callback.await('forge_garage:cb_server:getOwnedVehiclesForKeys', false)
    if not vehicles or #vehicles == 0 then
        return utils.notify("Você não possui nenhum veículo registrado em seu nome.", "error")
    end

    local options = {}
    for i = 1, #vehicles do
        local veh = vehicles[i]
        options[#options + 1] = {
            title = veh.vehicle_name,
            description = ("Placa: %s"):format(veh.plate),
            icon = 'car',
            onSelect = function()
                showTransferMethodMenu(veh)
            end
        }
    end

    pr_lib.registerContext({
        id = 'forge_garage:key_manager_transfer_list',
        title = 'Selecionar Veículo para Transferir',
        menu = 'forge_garage:key_manager_main',
        options = options
    })
    pr_lib.showContext('forge_garage:key_manager_transfer_list')
end

function openKeyManagerMenu()
    pr_lib.registerContext({
        id = 'forge_garage:key_manager_main',
        title = 'Gerenciamento de Chaves e Veículos',
        options = {
            {
                title = 'Tirar Cópia de Chave Permanente',
                description = 'Faz uma cópia de uma chave permanente que está no seu inventário',
                icon = 'key',
                onSelect = showCopyKeysMenu
            },
            {
                title = 'Perdi Minha Chave',
                description = 'Solicita uma nova chave original para um veículo de sua propriedade',
                icon = 'search-minus',
                onSelect = showLostKeysMenu
            },
            {
                title = 'Transferir Veículo',
                description = 'Transfere a propriedade de um veículo seu para outro jogador',
                icon = 'exchange-alt',
                onSelect = showTransferListMenu
            }
        }
    })
    pr_lib.showContext('forge_garage:key_manager_main')
end

exports('openKeyManagerMenu', openKeyManagerMenu)

-- Register a helper slash command to easily test/open it
RegisterCommand('keymanager', function()
    openKeyManagerMenu()
end, false)

-- Buyer payment callback
GarageBridge.callback.register('forge_garage:cb_client:requestPayment', function(sellerName, vehPlate, vehName, price, taxActive, taxAmount)
    local p = promise.new()
    local options = {}

    local details = ("Veículo: %s\nPlaca: %s\nValor do Vendedor: R$ %s"):format(vehName, vehPlate, price)
    if taxActive then
        details = details .. ("\nTaxa de Governo (10%%): R$ %s\nTotal a Pagar: R$ %s"):format(taxAmount, price + taxAmount)
    end

    options[#options + 1] = {
        title = 'Pagar com Dinheiro (Cash)',
        description = ('Valor total a debitar: R$ %s'):format(taxActive and (price + taxAmount) or price),
        icon = 'wallet',
        onSelect = function()
            p:resolve('cash')
        end
    }
    options[#options + 1] = {
        title = 'Pagar com Banco (Bank)',
        description = ('Valor total a debitar: R$ %s'):format(taxActive and (price + taxAmount) or price),
        icon = 'university',
        onSelect = function()
            p:resolve('bank')
        end
    }
    options[#options + 1] = {
        title = 'Pagar com Crypto',
        description = ('Valor total a debitar: R$ %s'):format(taxActive and (price + taxAmount) or price),
        icon = 'coins',
        onSelect = function()
            p:resolve('crypto')
        end
    }
    options[#options + 1] = {
        title = 'Recusar Compra',
        description = 'Cancela a negociação',
        icon = 'times-circle',
        onSelect = function()
            p:resolve('decline')
        end
    }

    pr_lib.registerContext({
        id = 'forge_garage:buyer_payment_menu',
        title = ('Proposta de Compra de %s'):format(sellerName),
        options = options,
        canClose = false
    })
    pr_lib.showContext('forge_garage:buyer_payment_menu')

    local choice = Citizen.Await(p)
    return choice
end)
