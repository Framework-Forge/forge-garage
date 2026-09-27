local registered = {}
GarageParkingEditor = {}
local function point(spot) return spot.coords or spot end
local function spots(g) return g.ipl and g.ipl.enabled and g.ipl.parkingSpots or g.spawnPoint or {} end
local function distance(a,b) return #(vec3(a.x,a.y,a.z)-vec3(b.x,b.y,b.z)) end
local function clear(id)
    local r=registered[id]
    if not r then return end
    if DoesEntityExist(r.entity) then
        pr_lib.target.removeLocalEntity(r.entity,r.name)
        if r.created then DeleteEntity(r.entity) end
    end
    registered[id]=nil
end
local function pay(garage,meter)
    local r=GarageBridge.callback.await('forge_garage:cb_server:getParkingVehicles',false,garage,meter.id)
    local vehicle=r and r.success and r.vehicles and r.vehicles[1]
    if not vehicle then return utils.notify('Nenhum veiculo seu neste estacionamento.', 'error') end
    if #r.vehicles > 1 then
        local options={}
        for i,v in ipairs(r.vehicles) do options[#options+1]={value=i,label=v.label..' ['..v.plate..'] - $'..v.debt} end
        local choice=pr_lib.inputDialog('Pagar estacionamento',{{type='select',label='Veiculo',required=true,options=options}})
        if not choice then return end
        vehicle=r.vehicles[tonumber(choice[1])]
        if not vehicle then return end
    end
    if not vehicle.canPay then return utils.notify('Destranque o veiculo para pausar a cobranca e pagar. Se ja pagou, retire dentro do prazo.', 'info',8000) end
    if pr_lib.alertDialog({header='Pagar estacionamento',
        content=('%s [%s]\nTotal: $%s\nPrazo restante: %ss'):format(vehicle.label,vehicle.plate,vehicle.debt,vehicle.remaining),
        cancel=true,centered=true})~='confirm' then return end
    local result=GarageBridge.callback.await('forge_garage:cb_server:payParking',false,garage,meter.id,vehicle.plate)
    if result and result.success then
        utils.notify(('Pago: $%s. Retire o veiculo em ate %ss.'):format(result.amount,result.remaining),'success',8000)
    else utils.notify('Pagamento nao concluido. Confira saldo, proximidade e prazo de desbloqueio.','error',8000) end
end
local function setup()
    local ids={}
    for id in pairs(registered) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do clear(id) end
end
exports('setupParkingMeters',setup)
AddEventHandler('onResourceStop',function(resource) if resource==GetCurrentResourceName() then setup() end end)
-- Map props are streamed: retry attachment when nearby instead of searching once at startup.
CreateThread(function()
    while true do
        Wait(1000)
        local pos=GetEntityCoords(PlayerPedId())
        local wanted={}
        for name,g in pairs(GarageZone or {}) do
            local p=g.persist and g.parking
            if p and p.enabled then
                for _,m in ipairs(p.meters or {}) do
                    local id=name..':'..m.id
                    if m.coords and distance(pos,m.coords)<100 then
                        wanted[id]=true
                        if registered[id] and not DoesEntityExist(registered[id].entity) then clear(id) end
                        if not registered[id] then
                            local hash=joaat(m.model)
                            local entity=0
                            if m.useExisting then
                                entity=GetClosestObjectOfType(m.coords.x,m.coords.y,m.coords.z,1.0,hash,false,false,false)
                            else
                                local loaded=GarageBridge.requestModel(hash,3000)
                                if loaded then
                                    entity=CreateObjectNoOffset(hash,m.coords.x,m.coords.y,m.coords.z,false,false,false)
                                    SetEntityHeading(entity,m.coords.w or 0)
                                    FreezeEntityPosition(entity,true)
                                    SetModelAsNoLongerNeeded(hash)
                                end
                            end
                            if entity~=0 then
                                local target='forge_garage:meter:'..id
                                pr_lib.target.addLocalEntity(entity,{{name=target,label='Pagar estacionamento',
                                    icon='bi bi-p-square',distance=2,onSelect=function() pay(name,m) end}})
                                registered[id]={entity=entity,created=not m.useExisting,name=target}
                            end
                        end
                    end
                end
            end
        end
        local obsolete={}
        for id in pairs(registered) do if not wanted[id] then obsolete[#obsolete+1]=id end end
        for _,id in ipairs(obsolete) do clear(id) end
    end
end)
-- Existing map meters are payment terminals, not mandatory bay assignments.
local function nearbyMapGarage(entity)
    if not entity or not DoesEntityExist(entity) then return end
    local pos=GetEntityCoords(entity)
    local selected,best
    for name,g in pairs(GarageZone or {}) do
        if g.persist and g.parking and g.parking.enabled and g.parking.meterMode=='existing' then
            for _,bay in ipairs(spots(g)) do
                local d=distance(pos,point(bay))
                if d<=30 and (not best or d<best) then selected,best=name,d end
            end
        end
    end
    return selected
end
CreateThread(function()
    pr_lib.target.addModel({'prop_parknmeter_01','prop_parknmeter_02'},{
        {name='forge_garage:mapMeter',label='Pagar estacionamento',icon='bi bi-p-square',distance=2,
            canInteract=function(entity) return nearbyMapGarage(entity)~=nil end,
            onSelect=function(data)
                local name=nearbyMapGarage(data.entity)
                if name then pay(name,{id='map'}) end
            end}
    })
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then
        pr_lib.target.removeModel({'prop_parknmeter_01','prop_parknmeter_02'},'forge_garage:mapMeter')
    end
end)
function GarageParkingEditor.configure(name)
    local g=GarageZone[name]
    if not g or not g.persist then
        utils.notify('Ative a persistencia para usar parquimetros.','error')
        return false
    end
    local old=g.parking or {}
    local input=pr_lib.inputDialog('Parquimetros: '..name,{
        {type='checkbox',label='Ativar cobranca de estacionamento',checked=old.enabled==true or old.requested==true},
        {type='select',label='Cobranca por',required=true,default=old.unit or 'hour',options={
            {value='hour',label='Hora do jogo (ou fracao)'},{value='day',label='Dia do jogo (ou fracao)'}}},
        {type='number',label='Valor por hora',required=true,min=1,max=1000000,default=old.ratePerGameHour or 100},
        {type='number',label='Valor por dia',required=true,min=1,max=1000000,default=old.ratePerGameDay or 1800},
        {type='select',label='Pagamento',required=true,default=old.paymentAccount or 'bank',options={
            {value='bank',label='Banco'},{value='cash',label='Dinheiro'}}},
        {type='number',label='Prazo apos destrancar (segundos)',description='Sem sair da vaga, volta a estacionado e retoma a cobranca.',required=true,min=10,max=86400,default=g.persistenceCooldownSeconds or old.exitCooldownSeconds or 120},
        {type='select',label='Parquimetros para pagamento',required=true,default=old.meterMode or 'existing',options={
            {value='existing',label='Usar os existentes no mapa'},{value='placed',label='Posicionar parquimetros pelo editor'}}}
    })
    if not input then return false end
    if not input[1] then
        g.parking={enabled=false,requested=false,meters={}}
        return true
    end
    local meters={}
    if input[7]=='existing' then
        utils.notify('Aviso: sem um parquimetro do mapa a ate 30m das vagas, o jogador nao conseguira pagar o estacionamento. Nenhum objeto sera exigido ou criado.','warning',15000)
    else
        local quantity=pr_lib.inputDialog('Pontos de pagamento',{
            {type='number',label='Quantidade de parquimetros',description='Independente da quantidade de vagas; cada terminal atende todo o estacionamento.',required=true,min=0,max=100,default=#(old.meters or {})}
        })
        if not quantity then return false end
        local count=tonumber(quantity[1])
        if not count or count%1~=0 then return false end
        if count==0 then utils.notify('Sem pontos de pagamento, o jogador nao conseguira pagar o estacionamento.','warning',12000) end
        for i=1,count do
            local previous=old.meters and old.meters[i]
            local options=pr_lib.inputDialog(('Ponto de pagamento %d'):format(i),{
                {type='select',label='Modelo',required=true,default=previous and previous.model or 'prop_parknmeter_01',options={
                    {value='prop_parknmeter_01',label='prop_parknmeter_01'},{value='prop_parknmeter_02',label='prop_parknmeter_02'}}},
                {type='checkbox',label='Manter posicao atual (se cadastrada)',checked=previous~=nil}
            })
            if not options then return false end
            local coords
            if previous and options[2] then coords=previous.coords
            else
                local resultPromise=promise.new()
                local started=pr_lib.devtools.placeObject(options[1],1,function(result) resultPromise:resolve(result or false) end)
                if not started then return false end
                local result=Citizen.Await(resultPromise)
                if not result then return false end
                coords={x=result.x,y=result.y,z=result.z,w=result.heading or 0}
            end
            meters[#meters+1]={id='terminal_'..i,model=options[1],useExisting=false,coords=coords,label='Pagamento'}
        end
    end
    g.persistenceCooldownSeconds=input[6]
    g.parking={enabled=true,requested=true,unit=input[2],ratePerGameHour=input[3],ratePerGameDay=input[4],
        paymentAccount=input[5],exitCooldownSeconds=input[6],meterMode=input[7],meters=meters}
    return true
end
function GarageParkingEditor.afterSpots(name)
    local g=GarageZone[name]
    if g.parking and g.parking.requested and not g.parking.enabled then
        GarageParkingEditor.configure(name)
    end
end
