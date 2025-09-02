-- ReplicatedStorage/Modules/Enemy/EnemyCatalog.lua
local function cloneDeep(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = (type(v) == "table") and cloneDeep(v) or v
    end
    return out
end

local Catalog = {
    Basic = {
        templatePath = "ServerStorage/EnemyTemplate",
        archetype    = "melee",
        base   = { hp = 90, dmg = 8, speed = 12, range = 6.0, cd = 1.2 },
        growth = { hp = 1.10, dmg = 1.05 },
        hipHeightOverride = 0.0,
    },

    Runner = {
        templatePath = "ServerStorage/EnemyTemplate",
        archetype    = "runner",
        base   = { hp = 75, dmg = 7, speed = 18, range = 6.5, cd = 1.1 },
        growth = { hp = 1.08, dmg = 1.00 },
        hipHeightOverride = 0.0,
    },

    Archer = {
        templatePath = "ServerStorage/EnemyTemplate",
        archetype    = "ranged",
        base   = { hp = 70, dmg = 10, speed = 10, range = 20.0, cd = 2.0 },
        projectile = { speed = 90, life = 2.5 }, -- tweak to taste
        growth = { hp = 1.08, dmg = 1.05 },
        hipHeightOverride = 0.1,
    },

    -- Example variant that inherits from Basic and multiplies stats
    MiniBasic = { ref = "Basic", hpMul = 4.0, dmgMul = 1.3, rank = "MiniBoss" },
}

local function resolve(id)
    local def = Catalog[id]
    if not def then return cloneDeep(Catalog.Basic) end

    if def.ref then
        local base = resolve(def.ref)
        -- merge tables shallowly
        local out = cloneDeep(base)
        for k, v in pairs(def) do
            if k ~= "ref" then
                if type(v) == "table" and type(out[k]) == "table" then
                    for kk, vv in pairs(v) do out[k][kk] = vv end
                else
                    out[k] = v
                end
            end
        end
        if out.base then
            if def.hpMul  then out.base.hp  = math.floor((out.base.hp  or 0) * def.hpMul)  end
            if def.dmgMul then out.base.dmg = math.floor((out.base.dmg or 0) * def.dmgMul) end
        end
        return out
    end

    return cloneDeep(def)
end

local M = {}
function M.get(kind)  -- EnemyFactory calls this
    return resolve(kind or "Basic")
end

return M
