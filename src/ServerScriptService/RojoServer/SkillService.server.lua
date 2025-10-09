-- ServerScriptService/SkillService.server.lua
-- Buy/Upgrade + Equip with level-cap. Mirrors equips to Hero and keeps plot element.
-- Accepts legacy ids (aquaburst/quake) and writes BOTH old & new attribute names.

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local SSS        = game:GetService("ServerScriptService")
local PlayerData = require(SSS.RojoServer.Data.PlayerData)
local Tuning     = require(RS.Modules.SkillTuning)

local Remotes  = RS:WaitForChild("Remotes")
local RE_Buy   = Remotes:WaitForChild("SkillPurchaseRequest")
local RE_Equip = Remotes:WaitForChild("SkillEquipRequest")

-- ===================== tuning =====================
local MAX_LEVEL       = 5
local STARTING_MONEY  = 100000

-- Canonical ids and aliases we accept from UI.
local CANON = { firebolt = true, aquabarrier = true, quakepulse = true }
local ALIAS = {
	-- fire
	fire       = "firebolt", bolt       = "firebolt", firebolt   = "firebolt",
	-- water
	aquaburst  = "aquabarrier", aquabarrier = "aquabarrier", barrier = "aquabarrier",
	-- earth
	quake      = "quakepulse", quakepulse  = "quakepulse", pulse = "quakepulse",
}

local function norm(id : string)
	id = string.lower(tostring(id or "")):gsub("%s+", "")
	return ALIAS[id]
end

-- Optional external SkillConfig (merged)
local SkillConfig = require(RS.Modules.SkillConfig)
local CFG = {
	firebolt    = { baseCost = 25, costMul = 1.35 },
	aquabarrier = { baseCost = 25, costMul = 1.35 },
	quakepulse  = { baseCost = 25, costMul = 1.35 },
}

-- If you decide to add baseCost/costMul inside SkillConfig entries,
-- this loop will pick them up automatically.
for k, v in pairs(SkillConfig or {}) do
	local key = norm(k)
	if key and type(v) == "table" then
		local cur = CFG[key] or {}
		CFG[key] = {
			baseCost = tonumber(v.baseCost) or cur.baseCost or 25,
			costMul  = tonumber(v.costMul)  or cur.costMul  or 1.35,
		}
	end
end


local ElemFromSkill = {
	firebolt    = "Fire",
	aquabarrier = "Water",
	quakepulse  = "Earth",
}

-- ===================== helpers =====================
local function lvlAttr(id) return "Skill_" .. id end

local function getMoney(plr : Player)
	local ls = plr:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Money")
end

local function heroFor(plr : Player)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _, m in ipairs(plots:GetChildren()) do
		if m:IsA("Model") and (m:GetAttribute("OwnerUserId") == plr.UserId) then
			local h = m:FindFirstChild("Hero", true)
			if h and h:IsA("Model") then return h, m end
		end
	end
end

local function essenceCostFor(skillId, nextLevel)
    -- returns fluxCost:number, essTbl:{[Elem]=amt}
    local entry = (Tuning.Costs and Tuning.Costs[skillId] and Tuning.Costs[skillId][nextLevel]) or {}
    local flux = tonumber(entry.flux) or 0
    local ess  = {}
    local src  = entry.essence or entry.ess
    if type(src) == "table" then
        for k,v in pairs(src) do ess[k] = math.max(0, math.floor(tonumber(v) or 0)) end
    end
    return flux, ess
end

-- Write BOTH canonical and legacy attribute names (so any UI reads it).
local function setLevelAttrs(instance : Instance, canonId : string, level : number)
	instance:SetAttribute(lvlAttr(canonId), level)
	if canonId == "aquabarrier" then
		instance:SetAttribute(lvlAttr("aquaburst"), level)  -- legacy
	elseif canonId == "quakepulse" then
		instance:SetAttribute(lvlAttr("quake"), level)       -- legacy
	end
end

-- ===================== Buy / Upgrade =====================
RE_Buy.OnServerEvent:Connect(function(plr : Player, rawId)
    local id = norm(rawId)
    if not (id and CANON[id]) then return end

    local cur = tonumber(plr:GetAttribute(lvlAttr(id))) or 0
    if cur >= MAX_LEVEL then return end

    local nextLevel = cur + 1
    local fluxCost, ess = essenceCostFor(id, nextLevel)

    -- 1) Spend Flux (optional – will be 0 with your current Costs)
    if fluxCost > 0 and not PlayerData.SpendFlux(plr, fluxCost) then
        return -- not enough flux
    end

    -- 2) Spend Essence (all-or-nothing)
    local spent = {}
    for elem, amt in pairs(ess) do
        if amt > 0 then
            if not PlayerData.SpendEssence(plr, elem, amt) then
                -- refund any Flux we took
                if fluxCost > 0 then PlayerData.AddFlux(plr, fluxCost) end
                -- refund any partial Essence (shouldn’t happen due to early bail, but safe)
                for e,a in pairs(spent) do PlayerData.AddEssence(plr, e, a) end
                return
            end
            spent[elem] = amt
        end
    end

    -- 3) Apply level
    setLevelAttrs(plr, id, nextLevel)
    local hero = heroFor(plr)
    if hero then setLevelAttrs(hero, id, nextLevel) end
    pcall(function() require(SSS.RojoServer.Data.PlayerData).SaveNow(plr) end)
end)

-- ===================== Equip =====================
RE_Equip.OnServerEvent:Connect(function(plr : Player, payload)
	local hero, plot = heroFor(plr)

	local function setEquip(which, rawId)
		if rawId == nil then
			plr:SetAttribute(which, nil)
			if hero then hero:SetAttribute(which, nil) end
			return
		end
		local id = norm(rawId); if not id then return end
		plr:SetAttribute(which, id)
		if hero then hero:SetAttribute(which, id) end
		if which == "Equip_Primary" and plot then
			local elem = ElemFromSkill[id]
			if elem then plot:SetAttribute("LastElement", elem) end
		end
	end

	if typeof(payload) == "table" then
		if payload.primary ~= nil then setEquip("Equip_Primary", payload.primary) end
		if payload.utility ~= nil then
			setEquip("Equip_Utility", payload.utility)
			if payload.primary == nil then setEquip("Equip_Primary", payload.utility) end
		end
	elseif type(payload) == "string" then
		setEquip("Equip_Primary", payload)
	end
end)

-- ===================== Player defaults =====================
Players.PlayerAdded:Connect(function(plr : Player)
	local CANON = { firebolt = true, aquabarrier = true, quakepulse = true }
    local function lvlAttr(id) return "Skill_"..id end
	-- default levels for both canonical and legacy keys
	for id,_ in pairs(CANON) do
		if plr:GetAttribute(lvlAttr(id)) == nil then plr:SetAttribute(lvlAttr(id), 0) end
	end
	if plr:GetAttribute(lvlAttr("aquaburst")) == nil then plr:SetAttribute(lvlAttr("aquaburst"), 0) end
	if plr:GetAttribute(lvlAttr("quake"))     == nil then plr:SetAttribute(lvlAttr("quake"), 0) end

	-- >>> ensure Firebolt Lv1 and equip it on first join
	if (tonumber(plr:GetAttribute(lvlAttr("firebolt"))) or 0) < 1 then
		plr:SetAttribute(lvlAttr("firebolt"), 1)
		local hero = heroFor(plr)
		if hero then hero:SetAttribute(lvlAttr("firebolt"), 1) end
	end

	-- default primary = firebolt (mirror to hero as well)
	if plr:GetAttribute("Equip_Primary") == nil then
		plr:SetAttribute("Equip_Primary", "firebolt")
		local hero = heroFor(plr)
		if hero then hero:SetAttribute("Equip_Primary", "firebolt") end
	end
end)
