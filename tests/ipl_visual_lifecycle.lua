-- Lua 5.4: lua ipl_visual_lifecycle.lua <forge-garage root>
local root = assert(arg[1])
local threads, events, sets = {}, {}, {}
local interior, ready, refreshes, writes = 10, true, 0, 0
local env = setmetatable({
    Config = { GarageIplDefaults = { ceo = { interiorId = 10 } } },
    gzf = { activeGarage = 'a' },
    GarageZone = { a = { ipl = { model = 'ceo', visual = { style=1, lighting=1, numbering=1 } } } },
    CreateThread = function(fn) threads[#threads+1] = coroutine.create(fn) end,
    Wait = coroutine.yield,
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    AddEventHandler = function() end,
    PlayerPedId = function() return 1 end,
    GetInteriorFromEntity = function() return interior end,
    IsInteriorReady = function() return ready end,
    IsInteriorEntitySetActive = function(_, name) return sets[name] == true end,
    ActivateInteriorEntitySet = function(_, name) sets[name]=true; writes=writes+1 end,
    DeactivateInteriorEntitySet = function(_, name) sets[name]=nil; writes=writes+1 end,
    SetInteriorEntitySetColor = function() writes=writes+1 end,
    RefreshInterior = function() refreshes=refreshes+1 end,
}, { __index = _G })
assert(loadfile(root..'/shared/ipl_visual.lua', 't', env))()
assert(loadfile(root..'/client/ipl_visual.lua', 't', env))()
local function tick(n)
    for i=1,n do assert(coroutine.resume(threads[1])) end
end
tick(2)
assert(refreshes==1 and writes==3, 'entry must apply once')
-- A native reporting an inactive set must not trigger periodic repairs/reloads.
sets.numbering_style01_n1=nil
local before=writes
tick(120)
assert(refreshes==1 and writes==before, 'idle must never reapply the IPL')
sets.numbering_style01_n1=true
events['forge_garage:client:iplVisual']('a', {style=2,lighting=1,numbering=1}, 1)
assert(refreshes==2 and writes==before+2, 'save must change only the selected style')
assert(sets.garage_decor_02 and not sets.garage_decor_01)
events['forge_garage:client:iplVisual']('a', {style=2,lighting=1,numbering=1}, 1)
assert(refreshes==2, 'duplicate delivery must not refresh unchanged decor')
tick(120); assert(refreshes==2)
interior=0; tick(1)
events['forge_garage:client:iplVisual']('a', {style=3,lighting=1,numbering=1}, 2)
-- Direct entry action may already select the next garage outside the IPL.
interior=10; sets={}; ready=false; tick(3)
local pending=refreshes
ready=true; tick(1)
assert(refreshes==pending+1 and sets.garage_decor_03, 'entry must wait for readiness')
env.gzf.activeGarage=nil
interior=0; tick(1); interior=10; tick(1)
events['forge_garage:client:iplVisual']('a', {style=4,lighting=1,numbering=1}, 3)
assert(sets.garage_decor_04, 'passengers must receive saved changes')
local stable=refreshes; tick(120); assert(refreshes==stable)
print('PASS IPL lifecycle: one-time entry, no periodic writes, differential save, duplicate event, readiness, passenger update')
