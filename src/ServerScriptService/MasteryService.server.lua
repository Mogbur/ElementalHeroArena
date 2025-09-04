-- MasteryService.server.lua
-- Provides GetWeaponMastery(styleId) -> {xp, max} for the LOCAL player.
-- Stores XP as Player attributes (swap to DataStore later).

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

-- Remotes folder
local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder", RS)
Remotes.Name = "Remotes"

local GetWeaponMastery = Remotes:FindFirstChild("GetWeaponMastery") or Instance.new("RemoteFunction", Remotes)
GetWeaponMastery.Name = "GetWeaponMastery"

-- Bring in your mastery thresholds to compute MAX. If you can, add a function
--   function M.max() return thresholds[#thresholds] end
-- to StyleMastery and use it here. Otherwise, set the last threshold manually.
local StyleMastery = require(RS:WaitForChild("Modules"):WaitForChild("StyleMastery"))
local MAX_XP = (StyleMastery.max and StyleMastery.max()) or 3000 -- <- keep in sync with your module

local STYLES = { "SwordShield", "Bow", "Mace" }

Players.PlayerAdded:Connect(function(plr)
	-- Seed attributes if missing
	for _, s in ipairs(STYLES) do
		if plr:GetAttribute("StyleXP_"..s) == nil then
			plr:SetAttribute("StyleXP_"..s, 0)
		end
	end
end)

-- Let the client ask for its current mastery numbers
GetWeaponMastery.OnServerInvoke = function(plr, styleId: string)
	local xp = plr:GetAttribute("StyleXP_"..tostring(styleId)) or 0
	return { xp = xp, max = MAX_XP }
end

-- OPTIONAL: helper you can call from combat code to add XP:
--   game.ReplicatedStorage.Remotes:WaitForChild("AddStyleXP"):Fire(plr, "Bow", 5)
local AddStyleXP = Remotes:FindFirstChild("AddStyleXP") or Instance.new("RemoteEvent", Remotes)
AddStyleXP.Name = "AddStyleXP"
AddStyleXP.OnServerEvent:Connect(function(plr, styleId: string, delta: number)
	local key = "StyleXP_"..tostring(styleId)
	local cur = plr:GetAttribute(key) or 0
	plr:SetAttribute(key, math.max(0, cur + (delta or 0)))
end)
