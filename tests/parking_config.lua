-- Pure regression tests: load only actual production helpers, no FiveM side effects.
local f=assert(io.open(arg[1],'r'))
local source=f:read('*a'); f:close()
local code=assert(source:match('(local function advance%(.+)local function nearMeter'))
local advance,due=assert(load(code..'\nreturn advance,due'))()
for _,duration in ipairs({10,15,120,900}) do
    local s={metered=false,lastTick=100,pausedUntil=100+duration,rate=0}
    advance(s,99+duration)
    assert(not s.needsRestore)
    advance(s,100+duration)
    assert(s.needsRestore and not s.pausedUntil)
    advance(s,110+duration)
    assert(s.needsRestore and due(s)==0)
end
local env={Parking={},GarageBridge={callback={register=function() end}},pairs=pairs,ipairs=ipairs,
    type=type,tonumber=tonumber,tostring=tostring,math=math,
    spots=function(g) return g.spawnPoint end,
    distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end}
local validate=assert(source:match('(function Parking.validateConfig%(.+)GarageBridge.callback.register'))
assert(load(validate,'validation','t',env))()
local garage={persist=true,spawnPoint={{x=0,y=0,z=0},{x=3,y=0,z=0}},
    parking={enabled=true,unit='hour',ratePerGameHour=100,ratePerGameDay=1800,
    exitCooldownSeconds=15,meterMode='existing',meters={}}}
assert(env.Parking.validateConfig({test=garage}))
garage.parking.meterMode='placed'
assert(env.Parking.validateConfig({test=garage})) -- no mandatory terminal
garage.parking.meters={{id='terminal_1',model='prop_parknmeter_02',coords={x=0,y=1,z=0}}}
assert(env.Parking.validateConfig({test=garage})) -- one terminal, two bays, no assignment
garage.parking.exitCooldownSeconds=0
assert(not env.Parking.validateConfig({test=garage}))
garage.parking.exitCooldownSeconds=120
garage.parking.meters[1].model='invalid'
assert(not env.Parking.validateConfig({test=garage}))
print('PASS: configurable grace, persistent restore marker, existing/zero/shared terminals, invalid config rejection')

-- Exercise the actual server restore hook with isolated state/database doubles.
local mainFile=assert(io.open(arg[1]:gsub('parking.lua$','main.lua'),'r'))
local main=mainFile:read('*a'); mainFile:close()
local restore=assert(main:match('(function GarageRestoreMeterParking%(.+)local function removeTrackedPersistentVehicle'))
local speed,offset=0,0
local function vector(x,y,z)
    return setmetatable({x=x,y=y,z=z},{__sub=function(a,b) return vector(a.x-b.x,a.y-b.y,a.z-b.z) end,
        __len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end})
end
local state={plate='ABC'}
function state:set(k,v) self[k]=v end
local calls={}
local restoreEnv={
    DoesEntityExist=function() return true end,normalizePlate=function(p) return p end,
    Entity=function() return {state=state} end,GetVehicleNumberPlateText=function() return 'ABC' end,
    GetEntityCoords=function() return vector(offset,0,0) end,vector3=vector,GetEntitySpeed=function() return speed end,
    GetEntityHeading=function() return 90 end,
    json={encode=function(v) return v end},
    GarageDB={uvs=function(plate,status,garage,coords)
        calls.db={plate,status,garage,coords}; return true
    end},
    exports={['pr_carkeys']={SetLockState=function(_,entity,lock) calls.lock=lock;state.doorslockstate=lock end}},
    FreezeEntityPosition=function(_,frozen) calls.frozen=frozen end,
    activeGarages={},
    trackPersistentVehicle=function(...) calls.tracked={...} end,
    TriggerClientEvent=function(...) calls.event={...} end
}
assert(load(restore,'restore','t',restoreEnv))()
local session={plate='ABC',garage='test',netId=10,origin={x=0,y=0,z=0}}
assert(restoreEnv.GarageRestoreMeterParking(session,1))
assert(calls.db[2]==1 and calls.db[3]=='test' and calls.lock==2 and calls.frozen)
assert(state.isPersistent and state.garageName=='test' and calls.tracked[2]=='ABC')
assert(calls.event[1]=='forge_garage:client:restoreMeterParking')
speed=2;assert(not restoreEnv.GarageRestoreMeterParking(session,1))
speed=0;offset=7;assert(not restoreEnv.GarageRestoreMeterParking(session,1))
print('PASS: actual restore hook updates stored state, locks, freezes, tracks and synchronizes; moving/departed cars excluded')

-- Free persistent garages must register without bays/meters and never accrue money.
local tracking=assert(source:match('(function Parking.trackPersistentEntity%(.+)function Parking.onVehicleStored'))
local configuration=assert(source:match('(local function config%(.+)local function spots'))
local plateHelper=assert(source:match('(local function key%(.+)local function copy'))
local trackingEnv={Parking={},GarageZone={
    free={persist=true,persistenceCooldownSeconds=15},
    impound={persist=true,impound=true},
    ordinary={persist=false},
    paid={persist=true,parking={enabled=true}}
},tonumber=tonumber,type=type,os={time=function() return 100 end},
    GetGameTimer=function() return 1 end,
    DoesEntityExist=function() return true end,
    Entity=function() return {state={plate='ABC'}} end,
    GetVehicleNumberPlateText=function() return 'ABC' end,
    GetEntityCoords=function() return {x=1,y=2,z=3} end,
    NetworkGetNetworkIdFromEntity=function() return 10 end,
    GetEntityRoutingBucket=function() return 0 end}
local tracked=assert(load('local ready=true; local sessions={}\n'..plateHelper..configuration..tracking..'\nreturn sessions','tracking','t',trackingEnv))()
trackingEnv.Parking.trackPersistentEntity('free','ABC',1)
local free=assert(tracked.ABC)
assert(free.metered==false and free.rate==0 and free.exitCooldownSeconds==15)
assert(free.origin.x==1 and free.origin.y==2)
trackingEnv.Parking.trackPersistentEntity('free','ABC',1)
assert(tracked.ABC==free) -- registration does not reset an existing grace window
free.pausedUntil=115
advance(free,115)
assert(free.needsRestore and due(free)==0)
advance(free,999999)
assert(due(free)==0)
tracked.ABC=nil
trackingEnv.Parking.trackPersistentEntity('ordinary','ABC',1)
assert(not tracked.ABC)
trackingEnv.Parking.trackPersistentEntity('paid','ABC',1)
assert(not tracked.ABC) -- dedicated paid registration remains unchanged
trackingEnv.Parking.trackPersistentEntity('impound','ABC',1)
assert(tracked.ABC and tracked.ABC.metered==false)
garage.parking.enabled=false
garage.persistenceCooldownSeconds=-1
assert(not env.Parking.validateConfig({test=garage}))
garage.persistenceCooldownSeconds=15
assert(env.Parking.validateConfig({test=garage}))
print('PASS: free/impound persistence, custom cooldown, no duplicate session, zero debt, ordinary garages excluded')
