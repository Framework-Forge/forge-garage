-- Run with Lua 5.4: lua bridge_migration.lua <forge-garage root>
local root=assert(arg[1])
local captured, affected = {}, 1
local db = {
    query=function(query, params) captured={query=query,params=params}; return {} end,
    update=function(query, params) captured={query=query,params=params}; return affected end,
}
local env=setmetatable({
    pr_lib={database=db,framework={GetIdentifier=function() return 'OWNER' end}},
    exports={pr_carkeys={GetKeys=function() return {'ORIGINAL','SECOND'} end}},
    Config={VehiclesInAllGarages=false},
}, {__index=_G})
assert(loadfile(root..'/server/db.lua','t',env))()
assert(#env.GarageDB.gpvbg(1,'Alta',{})==0)
assert(captured.query:find('IN (?,?)',1,true))
assert(captured.params[1]=='ORIGINAL' and captured.params[2]=='SECOND')
assert(captured.params[3]=='Alta' and captured.params[4]==1)
env.Config.VehiclesInAllGarages=true
env.GarageDB.gpvbg(1,'Alta',{})
assert(#captured.params==2)
for _, plate in ipairs({'ORIGINAL','FAKE'}) do
    assert(env.GarageDB.uvspi(plate,2))
    assert(captured.params[2]==plate and captured.params[3]==plate)
    assert(captured.query:find('plate = ? OR fakeplate = ?',1,true))
    assert(env.GarageDB.uvs(plate,1,'Alta','coords'))
    assert(captured.params[4]==plate and captured.params[5]==plate)
    affected=nil
    assert(env.GarageDB.uvs(plate,1,'Alta','coords')==false)
    assert(env.GarageDB.svg('Alta',plate)==false)
    affected=1
end
env.exports.pr_carkeys.GetKeys=function() return {} end
captured=nil
assert(#env.GarageDB.gpvbg(1,'Alta',{})==0 and captured==nil)
print('PASS garage SQL: scalar IN parameters, filters, original/fake plate routing, failed writes, empty key list')

local target, fuel, catalog = {}, {}, {}
local client=setmetatable({
    IsDuplicityVersion=function() return false end,
    pr_lib={
        target={
            addLocalEntity=function(entity,options) target={entity=entity,options=options} end,
            removeLocalEntity=function(entity,name) target.removed={entity,name} end,
        },
        fuel={SetFuel=function(entity,value) fuel={entity,value} end,GetFuel=function() return 45 end},
        framework={GetVehicleData=function(model) catalog.model=model; return {brand='Karin',name='Sultan'} end},
    },
    GarageBridge={requestModel=function() end},
    CreatePed=function() return 12 end,
    SetEntityInvincible=function() end,SetBlockingOfNonTemporaryEvents=function() end,
    FreezeEntityPosition=function() end,DoesEntityExist=function() return true end,DeleteEntity=function() end,
    joaat=function() return 100 end,GetMakeNameFromVehicleModel=function() return 'RAW' end,
    GetDisplayNameFromVehicleModel=function() return 'RAW' end,
}, {__index=_G})
assert(loadfile(root..'/shared/utils.lua','t',client))()
local selected=false
assert(client.utils.createTargetPed('model',{x=1,y=2,z=3,w=0},{
    {name='open',label='Abrir',groups={police=0},distance=2,action=function() selected=true end}
})==12)
assert(target.entity==12 and target.options[1].groups.police==0 and target.options[1].distance==2)
target.options[1].onSelect({entity=12}); assert(selected)
client.utils.removeTargetPed(12,'open'); assert(target.removed[2]=='open')
client.utils.setFuel(12,0); assert(fuel[2]==0)
assert(client.utils.getFuel(12)==45)
assert(client.utils.getVehicleLabel({model='sultan'})=='Karin Sultan' and catalog.model=='sultan')
print('PASS garage client: native target arguments/action/removal, fuel, framework vehicle labels')

-- Exercise the actual inventory callback without initializing server world loops.
local file=assert(io.open(root..'/server/main.lua','r'))
local source=file:read('*a'); file:close()
local first=assert(source:find("GarageBridge.callback.register('forge_garage:cb_server:getPlayerKeyItems'",1,true))
local last=assert(source:find("GarageBridge.callback.register('forge_garage:cb_server:getOwnedVehiclesForKeys'",first,true))
local keyCallback
local keyEnv=setmetatable({
    GarageBridge={callback={register=function(_,cb) keyCallback=cb end}},
    pr_lib={inventory={GetSlotsWithItem=function(player,item)
        assert(player==9)
        if item=='carkey_permanent' then
            return {{slot=1,metadata={plate='ORIGINAL',barcode='KEY-1',label='Minha chave'}},{slot=2,metadata={}}}
        end
        return {{slot=3,metadata={plate='SECOND',barcode='KEY-2'}}}
    end}},
}, {__index=_G})
assert(load(source:sub(first,last-1),'key-inventory','t',keyEnv))()
local keys=keyCallback(9)
assert(#keys==2 and keys[1].type=='original' and keys[1].plate=='ORIGINAL')
assert(keys[2].type=='copy' and keys[2].slot==3 and keys[2].barcode=='KEY-2')
keyEnv.pr_lib.inventory.GetSlotsWithItem=function() return nil end
assert(#keyCallback(9)==0)
print('PASS key inventory callback: original/copy metadata, invalid item rejection, empty inventory')
