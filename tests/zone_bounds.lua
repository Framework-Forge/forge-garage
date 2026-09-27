local file=assert(io.open(arg[1],'r'))
local source=file:read('*a'); file:close()
local helper=assert(source:match('(local function buildGarageZone%(.+)local function returnToContext'))
local env={type=type,tonumber=tonumber,math=math}
env.vec3=function(x,y,z) return {x=x,y=y,z=z} end
local build=assert(load(helper..'\nreturn buildGarageZone','zone-builder','t',env))()

local points={{x=0,y=0,z=50},{x=10,y=0,z=47},{x=10,y=10,z=44}}
local explicit=assert(build(points,{minZ=40,maxZ=55,thickness=15}))
assert(explicit.minZ==40 and explicit.maxZ==55 and explicit.thickness==15)
assert(explicit.points[2].z==47 and explicit.points[3].z==44)

local legacy=assert(build(points))
assert(legacy.minZ==42 and legacy.maxZ==52 and legacy.thickness==10)
assert(not build({points[1],points[2]}))
print('PASS: explicit sloped PolyZone floor/ceiling preserved; legacy bounds remain compatible')
