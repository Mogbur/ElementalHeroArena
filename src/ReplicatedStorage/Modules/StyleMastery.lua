local thresholds = {0, 100, 300, 700, 1500, 3000} -- Lvl1..Lvl5 gates are indices 1..5; last is cap
local M = {}

function M.thresholds() return thresholds end
function M.max() return thresholds[#thresholds] end

-- Returns display level 1..5 (Lvl.1 at 0 XP)
function M.level(xp: number): number
	xp = tonumber(xp) or 0
	local lvl = 1
	for i = 2, #thresholds do
		if xp >= thresholds[i] then
			lvl = i
		else
			break
		end
	end
	if lvl > 5 then lvl = 5 end
	return lvl
end

-- Bounds for the current level (low = current gate, high = next gate)
function M.bounds(xp: number): (number, number, number)
	local lvl = M.level(xp)                   -- 1..5
	local low  = thresholds[lvl]             -- e.g., 0 for lvl1
	local high = thresholds[lvl + 1] or thresholds[#thresholds]
	return lvl, low, high
end

-- Progress within the current level
--  returns: lvl(1..5), into (xp since low), span (needed to next), isMax(true at lvl5)
function M.progress(xp: number): (number, number, number, boolean)
	local lvl, low, high = M.bounds(xp)
	if lvl >= 5 then
		local span = high - low
		return lvl, span, span, true
	end
	local span = math.max(1, high - low)
	local into = math.clamp(xp - low, 0, span)
	return lvl, into, span, false
end

-- Backwards-compat alias
function M.rank(xp) return M.level(xp) end

-- Live bonuses by level (lvl 1..5)
function M.bonuses(styleId: string, xp: number)
	local lvl = M.level(xp) -- 1..5
	if styleId == "SwordShield" then
		return { drFlat = 0.03 * lvl }                 -- +3..+15% DR
	elseif styleId == "Bow" then
		return { critDmgMul = 1.0 + 0.02 * lvl }      -- +2% per level
	elseif styleId == "Mace" then
		local map = {0.03, 0.06, 0.08, 0.10, 0.15}
		return { stunChance = map[lvl] or 0.10 }       -- 3/6/8/10/15%
	end
	return {}
end

return M
