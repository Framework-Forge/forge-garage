-- Capabilities verified against the installed bob74_ipl definitions. No dependency on it.
GarageVisual = { catalogs = {} }
local function numbered(prefix, count, label, suffix)
    local options = {}
    for i = 1, count do options[i] = { label = label .. i, set = ('%s%02d%s'):format(prefix, i, suffix or '') } end
    return options
end
local ceo = {
    { key = 'style', label = 'Acabamento', options = {
        { label = 'Concreto', set = 'garage_decor_01' }, { label = 'Liso', set = 'garage_decor_02' },
        { label = 'Mármore', set = 'garage_decor_03' }, { label = 'Madeira', set = 'garage_decor_04' },
    } },
    { key = 'lighting', label = 'Iluminação', options = numbered('lighting_option', 9, 'Iluminação ') },
    { key = 'numbering', label = 'Numeração', options = numbered('numbering_style', 9, 'Estilo ', '_n1') },
}
for model, defaults in pairs(Config.GarageIplDefaults) do
    GarageVisual.catalogs[model] = { interiorId = defaults.interiorId, fields = ceo }
end
GarageVisual.catalogs.xm3_garage_fix = {
    interiorId = 290561,
    fields = {
        { key = 'style', label = 'Acabamento', options = {
            { label = 'Impecável', set = 'entity_set_shell_01' }, { label = 'Industrial', set = 'entity_set_shell_02' },
            { label = 'Luxuoso', set = 'entity_set_shell_03' },
        } },
        { key = 'numbering', label = 'Numeração', options = numbered('entity_set_numbers_', 5, 'Andar ') },
        { key = 'color', label = 'Cor', options = {} },
    }
}
for i, label in ipairs({ 'Branco', 'Cinza', 'Preto', 'Roxo', 'Laranja', 'Amarelo', 'Azul', 'Vermelho', 'Verde', 'Azul claro', 'Vermelho claro', 'Verde claro' }) do
    GarageVisual.catalogs.xm3_garage_fix.fields[3].options[i] = { label = label, set = 'entity_set_tint_01', color = i }
end
-- Include this interior in the existing loading/readiness and cleanup lifecycle.
Config.GarageIplDefaults.xm3_garage_fix = {
    interiorId = 290561, entitySets = { 'entity_set_shell_01', 'entity_set_numbers_01', 'entity_set_tint_01' }
}
function GarageVisual.catalog(ipl)
    return ipl and type(ipl.model) == 'string' and GarageVisual.catalogs[ipl.model] or nil
end
function GarageVisual.normalize(ipl, values, strict)
    local catalog = GarageVisual.catalog(ipl)
    if not catalog or type(values) ~= 'table' then return nil end
    local result, known = {}, {}
    for _, field in ipairs(catalog.fields) do
        known[field.key] = true
        local value = values[field.key]
        if value == nil and not strict then value = 1 end
        if type(value) ~= 'number' or value % 1 ~= 0 or not field.options[value] then
            if strict then return nil end
            value = 1
        end
        result[field.key] = value
    end
    if strict then for key in pairs(values) do if not known[key] then return nil end end end
    return result
end
function GarageVisual.point(value)
    if type(value) ~= 'table' then return nil end
    local result = {}
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        local n = value[axis]
        if type(n) ~= 'number' or n ~= n or math.abs(n) > 20000 then return nil end
        result[axis] = n
    end
    return result
end
function GarageVisual.manager(value)
    if type(value) ~= 'table' then return nil end
    local coords = GarageVisual.point(value.coords)
    if not coords or type(value.radius) ~= 'number' or value.radius ~= value.radius or value.radius < 1 or value.radius > 3 then return nil end
    if value.access ~= 'public' and value.access ~= 'residential' then return nil end
    local propertyId
    if value.access == 'residential' then
        propertyId = type(value.propertyId) == 'string' and value.propertyId:match('^%s*(.-)%s*$')
        if not propertyId or propertyId == '' or #propertyId > 80 then return nil end
    end
    -- Older sphere points keep their position until the administrator repositions the NPC.
    local model = value.model or 'a_m_m_business_01'
    local heading = value.heading or value.coords.w or 0.0
    if type(model) ~= 'string' or #model > 64 or not model:match('^[%w_]+$') then return nil end
    if type(heading) ~= 'number' or heading ~= heading or math.abs(heading) == math.huge then return nil end
    return { coords = coords, radius = value.radius, access = value.access, propertyId = propertyId, model = model, heading = heading % 360 }
end

-- DevTools returns placement coordinates (flat x/y/z). Reapply with its ped transform (noOffset=false).
function GarageVisual.pedPlacement(placement, access, propertyId, radius)
    if type(placement) ~= 'table' or type(placement.model) ~= 'string' then return nil end
    return GarageVisual.manager({
        coords = placement.coords or placement,
        heading = placement.heading,
        model = placement.model,
        radius = radius or 2.0,
        access = access,
        propertyId = propertyId,
    })
end
