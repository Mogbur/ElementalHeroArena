local thresholds = {0, 100, 300, 700, 1500, 3000} -- XP for ranks 0..5
local M = {}

function M.rank(xp)
  for i = #thresholds, 1, -1 do
    if xp >= thresholds[i] then return i end
  end
  return 0
end

function M.bonuses(styleId, xp)
  local r = M.rank(xp)
  if styleId == "SwordShield" then
    return { drFlat = 0.01 * r } -- +1% damage reduction per rank (0..5%)
  elseif styleId == "Bow" then
    return { critDmgMul = 1.0 + 0.015 * r } -- +1.5% basic-crit damage per rank
  elseif styleId == "Mace" then
    local chance = ({0.01,0.03,0.05,0.07,0.10})[math.clamp(r,1,5)] or 0
    return { stunChance = chance }
  end
  return {}
end

return M
