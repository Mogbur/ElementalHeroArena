-- ServerScriptService/RojoServer/Data/PlayerData.lua  (ModuleScript)
local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local store = DSS:GetDataStore("EHA_Player_v1")

local DEFAULT = {
  Money = 0,
  Level = 1,
  XP    = 0,
  Core  = { id = "ATK", tier = 0 },
  Mastery = { SwordShield = 0, Bow = 0, Mace = 0 },
  OwnedStyles = {},
}

-- ===== persistence helpers =====
local function loadAsync(uid)
  local ok, data = pcall(function()
    return store:GetAsync(("u:%d"):format(uid))
  end)
  return (ok and data) or nil
end

local function saveAsync(uid, data)
  pcall(function()
    store:SetAsync(("u:%d"):format(uid), data)
  end)
end

-- ===== session state =====
local Sessions = {}  -- [Player] = table

-- ===== public helpers =====
local function SetMoney(plr, amt)
  local d = Sessions[plr]; if not d then return end
  d.Money = math.max(0, math.floor(amt or 0))
  local ls = plr:FindFirstChild("leaderstats")
  if ls and ls:FindFirstChild("Money") then ls.Money.Value = d.Money end
end

local function AddXP(plr, amt)
  local d = Sessions[plr]; if not d then return end
  d.XP = math.max(0, (d.XP or 0) + (amt or 0))
  d.Level = math.max(1, 1 + math.floor(d.XP / 100)) -- tune curve later
  local ls = plr:FindFirstChild("leaderstats")
  if ls then
    local xp = ls:FindFirstChild("XP");    if xp then xp.Value = d.XP end
    local lv = ls:FindFirstChild("Level"); if lv then lv.Value = d.Level end
  end
end

-- ===== lifecycle (runs once when module is first required) =====
Players.PlayerAdded:Connect(function(plr)
  local data = loadAsync(plr.UserId) or table.clone(DEFAULT)
  Sessions[plr] = data

  -- leaderstats
  local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = plr
  local money = Instance.new("IntValue"); money.Name = "Money"; money.Value = data.Money or 0; money.Parent = ls
  local level = Instance.new("IntValue"); level.Name = "Level"; level.Value = data.Level or 1; level.Parent = ls
  local xp    = Instance.new("IntValue"); xp.Name    = "XP";    xp.Value    = data.XP    or 0; xp.Parent    = ls

  -- style mastery attributes expected by Combat/StyleMastery
  plr:SetAttribute("StyleXP_SwordShield", data.Mastery.SwordShield or 0)
  plr:SetAttribute("StyleXP_Bow",         data.Mastery.Bow         or 0)
  plr:SetAttribute("StyleXP_Mace",        data.Mastery.Mace        or 0)

  -- optional: weapon equips for HUDs
  plr:SetAttribute("WeaponMain", data.WeaponMain or "Sword")
  plr:SetAttribute("WeaponOff",  data.WeaponOff  or "Shield")
end)

Players.PlayerRemoving:Connect(function(plr)
  local data = Sessions[plr]
  if data then saveAsync(plr.UserId, data) end
  Sessions[plr] = nil
end)

-- ===== module API =====
return {
  Get      = function(plr) return Sessions[plr] end,
  SaveNow  = function(plr) local d = Sessions[plr]; if d then saveAsync(plr.UserId, d) end end,
  SetMoney = SetMoney,
  AddXP    = AddXP,
}
