-- ServerScriptService/RojoServer/Data/PlayerData.server.lua (new)
local DSS = game:GetService("DataStoreService")
local store = DSS:GetDataStore("EHA_Player_v1")

local DEFAULT = {
  Money = 0,
  Level = 1,
  XP = 0,
  Core = { id="ATK", tier=0 },
  Mastery = { Sword=0, Bow=0, Staff=0 },
  OwnedStyles = {}, -- if you ever sell styles, migrate away from PlayerStyleStore or unify
}

local Sessions = {}

local function loadAsync(uid)
  local ok, data = pcall(function() return store:GetAsync(("u:%d"):format(uid)) end)
  return ok and data or nil
end

local function saveAsync(uid, data)
  pcall(function() store:SetAsync(("u:%d"):format(uid), data) end)
end

game.Players.PlayerAdded:Connect(function(plr)
  local data = loadAsync(plr.UserId) or table.clone(DEFAULT)
  Sessions[plr] = data

  -- reflect to leaderstats/attributes
  -- (money/level/xp)
  -- (core id/tier to attributes if your Forge UI/HUD wants to read it)
end)

game.Players.PlayerRemoving:Connect(function(plr)
  local data = Sessions[plr]
  if data then saveAsync(plr.UserId, data) end
  Sessions[plr] = nil
end)

return {
  Get = function(plr) return Sessions[plr] end,
  SaveNow = function(plr) local d=Sessions[plr]; if d then saveAsync(plr.UserId, d) end end,
}
