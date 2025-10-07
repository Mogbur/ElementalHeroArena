-- ServerScriptService/RojoServer/Data/PlayerData.server.lua
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local store = DSS:GetDataStore("EHA_Player_v1")

local DEFAULT = {
  Money = 0, Level = 1, XP = 0,
  Core = { id="ATK", tier=0 },
  Mastery = { SwordShield=0, Bow=0, Mace=0 },
  OwnedStyles = {},
  WeaponMain = "Sword", WeaponOff = "Shield",
}

local Sessions = {}

local function loadAsync(uid)
  local ok, data = pcall(function() return store:GetAsync(("u:%d"):format(uid)) end)
  if ok and data then return data end
end

local function saveAsync(uid, data)
  pcall(function() store:SetAsync(("u:%d"):format(uid), data) end)
end

local function ensureSession(plr)
  local d = Sessions[plr]
  if d then return d end
  d = loadAsync(plr.UserId) or table.clone(DEFAULT)
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
  plr:SetAttribute("WeaponMain", d.WeaponMain or "Sword")
  plr:SetAttribute("WeaponOff",  d.WeaponOff  or "Shield")
  plr:SetAttribute("Level",      d.Level or 1)
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

return M
