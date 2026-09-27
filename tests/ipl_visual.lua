-- Lua 5.4: lua ipl_visual.lua <forge-garage root>
local root = assert(arg[1])
local function copy(t)
    if type(t) ~= 'table' then return t end
    local result = {}; for k,v in pairs(t) do result[k] = copy(v) end; return result
end
local registered, broadcasts, disk = {}, {}, nil
local isAdmin, isResident, housing, diskOK = false, false, 'started', true
local bucket, pos = 81, { x=10, y=20, z=30 }
local env = setmetatable({
    Config = { GarageIplDefaults = { ceo = { interiorId = 253441 } } },
    GarageBridge = { callback = { register = function(name, fn) registered[name] = fn end } },
    pr_lib = { framework = {
        HasPermission = function() return isAdmin end,
        GetPlayer = function() return { PlayerData = { job={name='police',grade={level=2}} } } end,
    }, database = {
        query = function() return {{property_id=42,street='Test street'}} end,
        scalar = function(_,params) return params[1]=='42' and 42 or nil end,
    } },
    exports = { ['ps-housing'] = { IsOwner = function(_,src,id) return src==1 and id=='42' and isResident end } },
    IsPlayerAceAllowed = function() return false end,
    GetPlayerPed = function() return 101 end,
    GetPlayerRoutingBucket = function() return bucket end,
    GetEntityCoords = function() return pos end,
    GetResourceState = function() return housing end,
    GetCurrentResourceName = function() return 'forge-garage' end,
    json = { encode=copy, decode=copy },
    SaveResourceFile = function(_,path,value) assert(path=='data/garages.json'); if diskOK then disk=copy(value) end; return diskOK end,
    TriggerClientEvent = function(...) broadcasts[#broadcasts+1]={...} end,
}, {__index=_G})
assert(loadfile(root..'/shared/ipl_visual.lua','t',env))()
local visual=env.GarageVisual
local function base()
    return { ipl={enabled=true,model='ceo',bucket=81,manager={coords={x=10,y=20,z=30},radius=2,access='public'} } }
end
env.GarageZone={public=base(),residential=base(),another=base()}
env.GarageZone.residential.ipl.manager.access='residential'
env.GarageZone.residential.ipl.manager.propertyId='42'
assert(loadfile(root..'/server/ipl_visual.lua','t',env))()
local function call(action,...) return registered['forge_garage:visual:'..action](1,...) end
local choices={style=3,lighting=4,numbering=2}
assert(call('open','public').success)
assert(not call('open','residential').success)
isResident=true;assert(call('open','residential').success)
housing='stopped';assert(not call('open','residential').success);housing='started'
bucket=82;assert(not call('save','public',choices,0).success);bucket=81
pos.x=100;assert(not call('save','public',choices,0).success);pos.x=10
assert(not call('save','public',{style=0,lighting=1,numbering=1},0).success)
assert(not call('save','public',{style=1.5,lighting=1,numbering=1},0).success)
assert(not call('save','public',{style=1,lighting=1,numbering=1,model='bad'},0).success)
assert(not call('save','public',{style=1,lighting=1},0).success)
assert(call('save','public',choices,0).success)
assert(disk.public.ipl.visual.style==3 and env.GarageZone.public.ipl.visualRevision==1)
assert(env.GarageZone.another.ipl.visual==nil)
assert(not call('save','public',choices,0).success) -- stale editor
local eventCount=#broadcasts
diskOK=false;assert(not call('save','public',{style=2,lighting=2,numbering=2},1).success)
assert(env.GarageZone.public.ipl.visual.style==3 and #broadcasts==eventCount);diskOK=true
env.GarageZone.public.job={ambulance=0};assert(not call('open','public').success);env.GarageZone.public.job=nil
assert(not call('configure','public',false).success)
assert(#call('properties')==0)
isAdmin=true
assert(#call('properties')==1)
assert(call('configure','public',{coords={x=11,y=21,z=31},radius=1.5,access='residential',propertyId='42'}).success)
assert(disk.public.ipl.manager.propertyId=='42')
assert(not call('configure','public',{coords={x=0/0,y=1,z=2},radius=1,access='public'}).success)
assert(not call('configure','public',{coords={x=1,y=1,z=2},radius=1,access='residential',propertyId='999'}).success)
assert(call('configure','public',false).success and disk.public.ipl.manager==nil)
assert(env.GarageZone.public.ipl.visual.style==3)
print('PASS IPL server: public/resident/admin permissions, bucket, distance, invalid choices, conflicts, disk failure, isolated persistence, manager CRUD')
-- Model capabilities: Eclipse has tint, CEO has no arbitrary colors.
local eclipse={model='xm3_garage_fix'}
assert(visual.normalize(eclipse,{style=3,numbering=5,color=12},true).color==12)
assert(not visual.normalize(eclipse,{style=3,numbering=5,color=13},true))
assert(not visual.catalog({model='unsupported'}))
assert(visual.normalize({model='ceo'},{style=100}).style==1)
print('PASS IPL capabilities: supported presets, tint bounds, unsupported models, default recovery')
-- Exercise real client menu callbacks, including PR Bridge calling onExit before onSelect.
local activeSets, colors, lastMenu, events, notices = {}, {}, nil, {}, {}
local currentInput
local client=setmetatable({
    GarageVisual=visual, GarageZone={public=base()}, gzf={activeGarage='public'},
    IsInteriorReady=function() return true end,
    ActivateInteriorEntitySet=function(id,set) activeSets[set]=true end,
    DeactivateInteriorEntitySet=function(id,set) activeSets[set]=nil end,
    SetInteriorEntitySetColor=function(id,set,color) colors[set]=color end,
    RefreshInterior=function() end,
    PlayerPedId=function() return 1 end, GetEntityCoords=function() return pos end,
    CreateThread=function() end, AddEventHandler=function() end,
    RegisterNetEvent=function(name,fn) events[name]=fn end,
    utils={createMenu=function(menu) lastMenu=menu end,notify=function(msg) notices[#notices+1]=msg end},
    pr_lib={ inputDialog=function() return currentInput end, hideContext=function() end,showContext=function(id) lastMenu={id=id} end },
    GarageBridge={callback={await=function(_,_,name)
        return {success=true,model='ceo',visual={style=1,lighting=1,numbering=1},revision=0}
    end}},
}, {__index=_G})
pos={x=10,y=20,z=30}
assert(loadfile(root..'/client/ipl_visual.lua','t',client))()
local cv=client.GarageVisualClient
cv.open('public','admin-parent')
assert(lastMenu.menu=='admin-parent' and activeSets.garage_decor_01)
local selectStyle=lastMenu.options[1].onSelect
lastMenu.onExit();currentInput={3};selectStyle()
assert(activeSets.garage_decor_03 and not activeSets.garage_decor_01)
lastMenu.onExit()
assert(activeSets.garage_decor_01 and not activeSets.garage_decor_03) -- ESC/cancel
cv.open('public','admin-parent')
selectStyle=lastMenu.options[1].onSelect;lastMenu.onExit();currentInput={4};selectStyle()
events['forge_garage:client:iplVisual']('public',{style=2,lighting=5,numbering=3},2)
assert(activeSets.garage_decor_02 and not activeSets.garage_decor_04)
assert(client.GarageZone.public.ipl.visualRevision==2)
cv.reset('public');assert(activeSets.garage_decor_01)
client.GarageZone.eclipse={ipl={model='xm3_garage_fix',visual={style=3,numbering=4,color=12}}}
cv.apply('eclipse');assert(activeSets.entity_set_shell_03 and colors.entity_set_tint_01==12)
cv.reset('eclipse');assert(activeSets.entity_set_shell_01 and not activeSets.entity_set_shell_03 and colors.entity_set_tint_01==1)
client.gzf.activeGarage='another'
events['forge_garage:client:iplVisual']('public',{style=4,lighting=1,numbering=1},3)
assert(activeSets.garage_decor_01) -- another instance must not change
print('PASS IPL client: native entity sets, mutually exclusive styles, preview cancellation, parent menu, authoritative update, instance isolation')
-- Preserve DevTools placement values in storage; spawn must use the same native ped-height adjustment.
local placement={x=-191.17,y=-579.23,z=135.87,heading=217.25,model='s_m_m_autoshop_01'}
local placed=assert(visual.pedPlacement(placement,'public',nil,2.0))
assert(placed.coords.z==135.87 and placed.heading==217.25 and placed.model==placement.model)
assert(call('configure','public',placed).success)
assert(disk.public.ipl.manager.coords.x==placement.x and disk.public.ipl.manager.coords.y==placement.y)
assert(disk.public.ipl.manager.coords.z==placement.z and disk.public.ipl.manager.heading==placement.heading)
assert(disk.public.ipl.manager.model==placement.model)
assert(not visual.pedPlacement({x=1,y=2,z=3},'public'))
assert(not visual.manager({coords={x=1,y=2,z=3},model={},radius=2,access='public'}))
assert(not visual.manager({coords={x=1,y=2,z=3},heading=math.huge,radius=2,access='public'}))
local legacy=assert(visual.manager({coords={x=1,y=2,z=3},radius=2,access='public'}))
assert(legacy.model=='a_m_m_business_01' and legacy.heading==0 and legacy.coords.z==3)
-- Real NPC creation lifecycle, queued model loading and target callbacks.
local queue,entities,removed={}, {}, {}
local spawned,registeredTarget,removedTarget,exactCoords=0,nil,nil,nil
client.CreateThread=function(fn) queue[#queue+1]=fn end
client.joaat=function(model) return model end
client.IsModelInCdimage=function() return true end
client.IsModelAPed=function() return true end
client.HasModelLoaded=function() return true end
client.GarageBridge.requestModel=function() end
client.SetModelAsNoLongerNeeded=function() end
client.CreatePed=function(kind,hash,x,y,z,heading,networked)
    assert(not networked and hash==placement.model and z==placement.z and heading==placement.heading)
    spawned=spawned+1;entities[900+spawned]=true;return 900+spawned
end
client.DoesEntityExist=function(id) return entities[id] end
client.DeleteEntity=function(id) assert(entities[id]);entities[id]=nil;removed[#removed+1]=id end
local coordsCalls, noOffsetCalls = 0, 0
client.SetEntityCoords=function(id,x,y,z)
    coordsCalls=coordsCalls+1;exactCoords={x=x,y=y,z=z};assert(z==placement.z)
end
client.SetEntityCoordsNoOffset=function() noOffsetCalls=noOffsetCalls+1 end
-- Exercise the actual bridge helper used by DevTools, not a duplicate implementation.
client.pr_lib.fivem={streaming=assert(loadfile(root..'/../pr_bridge/bridge/fivem/streaming/client.lua','t',client))()}
client.SetEntityHeading=function(_,heading) assert(heading==placement.heading) end
client.FreezeEntityPosition=function() end
client.SetEntityInvincible=function() end
client.SetBlockingOfNonTemporaryEvents=function() end
client.SetPedCanRagdoll=function() end
client.SetEntityAsMissionEntity=function() end
local clock=0
client.GetGameTimer=function() return clock end
client.IsPedInAnyVehicle=function() return false end
client.pr_lib.target={
    addLocalEntity=function(id,options) registeredTarget={id=id,option=options[1]} end,
    removeLocalEntity=function(id,name) removedTarget={id=id,name=name} end,
}
client.GarageZone.public.ipl.manager=placed
client.gzf.activeGarage='public'
cv.syncNpc();cv.syncNpc();assert(#queue==1)
table.remove(queue,1)()
assert(spawned==1 and exactCoords.x==placement.x and exactCoords.y==placement.y)
assert(coordsCalls==1 and noOffsetCalls==0) -- same native as the non-animated DevTools ped preview
assert(registeredTarget.option.canInteract())
local opened
local originalOpen=cv.open;cv.open=function(name) opened=name end
registeredTarget.option.onSelect();assert(opened=='public');cv.open=originalOpen
cv.syncNpc();assert(#queue==0 and spawned==1)
cv.editNpc(true);assert(#removed==1 and removedTarget.id==901)
cv.editNpc(false);assert(#queue==1);table.remove(queue,1)();assert(spawned==2)
client.gzf.activeGarage=nil;cv.syncNpc();assert(#removed==2)
client.gzf.activeGarage='public';cv.syncNpc()
cv.clearNpc();table.remove(queue,1)();assert(spawned==2) -- cancelled while loading
print('PASS layout NPC: exact XYZ/heading/model persistence, legacy migration, native target, no duplicates, edit/exit cleanup, cancelled model load')

client.IsInteriorReady=function() return false end
cv.syncNpc();table.remove(queue,1)();assert(spawned==3) -- does not depend on decor readiness
entities[903]=nil
cv.syncNpc();table.remove(queue,1)();assert(spawned==4) -- recover externally removed ped
cv.clearNpc()
client.HasModelLoaded=function() return false end
cv.syncNpc();table.remove(queue,1)();assert(spawned==4)
cv.syncNpc();assert(#queue==0) -- timeout backoff, no queue flood
clock=5001;client.HasModelLoaded=function() return true end
cv.syncNpc();table.remove(queue,1)();assert(spawned==5)
local create=client.CreatePed
cv.clearNpc();client.CreatePed=function() return 0 end
cv.syncNpc();table.remove(queue,1)();assert(spawned==5)
clock=10002;client.CreatePed=create
cv.syncNpc();table.remove(queue,1)();assert(spawned==6)
print('PASS NPC recovery: interior not ready, disappeared entity, model timeout retry, CreatePed failure retry')
-- Every configured interior teleport explicitly carries the garage key.
local creator=assert(io.open(root..'/client/creator.lua')):read('*a')
assert(creator:find('args = { garage = self.k, coords = spot.coords',1,true))
assert(creator:find('args = { garage = self.k, coords = floor.coords',1,true))
assert(creator:find('gzf.setVisualGarage(self.garage)',1,true))
