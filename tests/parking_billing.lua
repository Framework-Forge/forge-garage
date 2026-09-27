-- Runs the production billing helpers; no FiveM or database mutations.
local file=assert(io.open(arg[1], 'r'))
local source=file:read('*a'); file:close()
local helpers=assert(source:match('(local function advance%(.+)local function nearMeter'))
local advance,due=assert(load(helpers..'\nreturn advance,due'))()
local s={metered=true,billingClock='game',elapsedGameMinutes=0,lastGameMinute=60,lastTick=1000,rate=100,unitMinutes=60,unit='hour'}
advance(s,1060,89); assert(s.elapsedGameMinutes==29 and due(s)==100)
s.pausedUntil=1180
advance(s,1179,119); assert(s.elapsedGameMinutes==29 and due(s)==100)
advance(s,1180,120); assert(not s.pausedUntil and s.needsRestore and s.elapsedGameMinutes==30)
s.needsRestore=nil
advance(s,1241,151); assert(s.elapsedGameMinutes==61 and due(s)==200)
s.pausedUntil=1361; s.paid=true;s.elapsedGameMinutes=0
advance(s,1300,180); assert(due(s)==0 and s.elapsedGameMinutes==0)
advance(s,1361,181);assert(not s.paid and due(s)==100)
local day={metered=true,billingClock='game',elapsedGameMinutes=0,lastGameMinute=0,lastTick=0,rate=1800,unitMinutes=1440,unit='day'}
for minute=60,1440,60 do advance(day,minute,minute%1440) end
assert(due(day)==1800)
advance(day,1500,1);assert(due(day)==3600)
local adjusted={metered=true,billingClock='game',elapsedGameMinutes=10,lastGameMinute=600,lastTick=0,rate=100,unitMinutes=60,unit='hour'}
advance(adjusted,1,1200);assert(adjusted.elapsedGameMinutes==10 and adjusted.lastGameMinute==1200)
local legacy={metered=true,elapsed=60,unitSeconds=120,lastTick=0,rate=100,unit='hour'}
advance(legacy,1,300);assert(legacy.billingClock=='game' and legacy.elapsedGameMinutes==30 and due(legacy)==100)
print('PASS: game clock billing, pause, day rollover, admin time jump and legacy migration')
