-- ServerScriptService/RojoServer/Data/PlayerData.lua
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local store = DSS:GetDataStore("EHA_Player_v1")

local DEFAULT = {
  Money = 0, Flux = 0, Level = 1, XP = 0,
  Core = { id="ATK", tier=0 },
  Mastery = { SwordShield=0, Bow=0, Mace=0 },
  OwnedStyles = {},
  WeaponMain = "Sword", WeaponOff = "Shield",
  Essence = { Fire = 0, Water = 0, Earth = 0 },

  -- NEW: tiers (0/1 shows no badge, 2="II", 3="III")
  EssenceTier = { Fire = 1, Water = 1, Earth = 1 },
}

local Sessions = {}

-- add once, near DEFAULT
local function deepMerge(dst, src)
  for k,v in pairs(src) do
    if type(v) == "table" then
      dst[k] = type(dst[k]) == "table" and dst[k] or {}
      deepMerge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

local function loadAsync(uid)
  local ok, data = pcall(function() return store:GetAsync(("u:%d"):format(uid)) end)
  if ok and data then return data end
end

local function saveAsync(uid, data)
  pcall(function()
    store:UpdateAsync(("u:%d"):format(uid), function(old)
      old = type(old)=="table" and old or {}
      return data
    end)
  end)
end

local function ensureSession(plr)
  local d = Sessions[plr]
  if d then return d end
  d = loadAsync(plr.UserId) or {}
  deepMerge(d, DEFAULT)             -- ← fills missing keys (Flux, Essence table, etc.)
  Sessions[plr] = d
  return d
end

local function mirrorToLeaderstats(plr, d)
  local ls = plr:FindFirstChild("leaderstats")
  if ls then
    if ls:FindFirstChild("Money") then ls.Money.Value = d.Money or 0 end
    if ls:FindFirstChild("Level") then ls.Level.Value = d.Level or 1 end
    if ls:FindFirstChild("XP")    then ls.XP.Value    = d.XP    or 0 end
  end
  -- attributes that other systems read
  plr:SetAttribute("StyleXP_SwordShield", d.Mastery.SwordShield or 0)
  plr:SetAttribute("StyleXP_Bow",         d.Mastery.Bow or 0)
  plr:SetAttribute("StyleXP_Mace",        d.Mastery.Mace or 0)
  -- Don't clobber live style choices set by WeaponStands / PlayerStyleStore.
  -- Only set defaults if the attributes don't exist yet.
  if plr:GetAttribute("WeaponMain") == nil then
    plr:SetAttribute("WeaponMain", d.WeaponMain or "Sword")
  end
  if plr:GetAttribute("WeaponOff") == nil then
    plr:SetAttribute("WeaponOff", d.WeaponOff or "Shield")
  end
  plr:SetAttribute("Level",      d.Level or 1)
  plr:SetAttribute("Flux",       d.Flux or 0)
  plr:SetAttribute("Essence_Fire",   (d.Essence and d.Essence.Fire)   or 0)
  plr:SetAttribute("Essence_Water",  (d.Essence and d.Essence.Water)  or 0)
  plr:SetAttribute("Essence_Earth",  (d.Essence and d.Essence.Earth)  or 0)
    -- NEW: UI reads these to show "II"/"III" badges
  plr:SetAttribute("EssenceTier_Fire",  (d.EssenceTier and d.EssenceTier.Fire)  or 1)
  plr:SetAttribute("EssenceTier_Water", (d.EssenceTier and d.EssenceTier.Water) or 1)
  plr:SetAttribute("EssenceTier_Earth", (d.EssenceTier and d.EssenceTier.Earth) or 1)
end

Players.PlayerAdded:Connect(function(plr)
  local d = ensureSession(plr)
  mirrorToLeaderstats(plr, d) -- if leaderstats already exists in Studio, reflect now
end)

Players.PlayerRemoving:Connect(function(plr)
  local d = Sessions[plr]
  if d then saveAsync(plr.UserId, d) end
  Sessions[plr] = nil
end)

local M = {}

function M.Get(plr) return Sessions[plr] end
function M.EnsureLoaded(plr)
  local d = ensureSession(plr)
  mirrorToLeaderstats(plr, d)
  return d
end
function M.SaveNow(plr) local d=Sessions[plr]; if d then saveAsync(plr.UserId, d) end end

function M.SetMoney(plr, amt)
  local d = ensureSession(plr)
  d.Money = math.max(0, math.floor(tonumber(amt) or 0))
  mirrorToLeaderstats(plr, d)
end

function M.AddXP(plr, amt)
  local d = ensureSession(plr)
  d.XP = math.max(0, (d.XP or 0) + (tonumber(amt) or 0))
  d.Level = math.max(1, 1 + math.floor(d.XP/100)) -- simple curve
  mirrorToLeaderstats(plr, d)
end

function M.AddStyleXP(plr, styleId, delta)
  local d = ensureSession(plr)
  styleId = ({SwordShield=true,Bow=true,Mace=true})[styleId] and styleId or "SwordShield"
  d.Mastery[styleId] = math.max(0, (d.Mastery[styleId] or 0) + (tonumber(delta) or 0))
  mirrorToLeaderstats(plr, d)
end

local function canonElem(s)
  s = tostring(s or "Water")
  if s == "Fire" or s == "Water" or s == "Earth" then return s end
  return "Water"
end

function M.AddEssence(plr, elem, amount)
  local d = ensureSession(plr)
  elem = canonElem(elem)
  d.Essence = d.Essence or {Fire=0,Water=0,Earth=0}
  d.Essence[elem] = math.max(0, (d.Essence[elem] or 0) + math.floor(amount or 0))
  mirrorToLeaderstats(plr, d)
end

function M.SpendEssence(plr, elem, amount)
  local d = ensureSession(plr)
  elem = canonElem(elem)
  amount = math.max(0, math.floor(amount or 0))
  local pool = d.Essence or {Fire=0,Water=0,Earth=0}
  if (pool[elem] or 0) < amount then return false end
  pool[elem] = pool[elem] - amount
  mirrorToLeaderstats(plr, d)
  return true
end

function M.AddFlux(plr, amt)
  local d = ensureSession(plr)
  d.Flux = math.max(0, (d.Flux or 0) + math.floor(tonumber(amt) or 0))
  mirrorToLeaderstats(plr, d)
end

function M.SpendFlux(plr, amt)
  local d = ensureSession(plr)
  amt = math.max(0, math.floor(tonumber(amt) or 0))
  if (d.Flux or 0) < amt then return false end
  d.Flux -= amt
  mirrorToLeaderstats(plr, d)
  return true
end
function M.SetEssenceTier(plr, elem, tier)
  local d = ensureSession(plr)
  elem = tostring(elem)
  if elem ~= "Fire" and elem ~= "Water" and elem ~= "Earth" then elem = "Water" end
  d.EssenceTier = d.EssenceTier or { Fire=1, Water=1, Earth=1 }
  tier = math.clamp(tonumber(tier) or 1, 1, 3) -- 1=none, 2="II", 3="III"
  d.EssenceTier[elem] = tier
  mirrorToLeaderstats(plr, d)
end
return M
