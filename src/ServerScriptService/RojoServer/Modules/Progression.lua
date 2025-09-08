-- ServerScriptService/RojoServer/Modules/Progression.lua
local Progression = {}

local STARTING_MONEY = 100000

local function ensureLeaderstats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end

	local money = stats:FindFirstChild("Money")
	if not money then
		money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = 0
		money.Parent = stats
	end

	local level = stats:FindFirstChild("Level")
	if not level then
		level = Instance.new("IntValue")
		level.Name = "Level"
		level.Value = player:GetAttribute("HeroLevel") or 1
		level.Parent = stats
	end

	local xp = stats:FindFirstChild("XP")
	if not xp then
		xp = Instance.new("IntValue")
		xp.Name = "XP"
		xp.Value = 0
		xp.Parent = stats
	end

	return stats, money, level, xp
end

function Progression.InitPlayer(player: Player)
	local _, money, level, _ = ensureLeaderstats(player)

	-- make sure the attribute exists and mirrors the Level stat
	if player:GetAttribute("HeroLevel") == nil then
		player:SetAttribute("HeroLevel", level.Value)
	end

	-- starter cash (only tops up if below)
	if money.Value < STARTING_MONEY then
		money.Value = STARTING_MONEY
	end

	-- optional Essence setup

end

-- simple ladder: 50, 100, 150, ...
local function xpNeededForLevel(lvl: number)
	return 50 + (lvl - 1) * 50
end

function Progression.AddXP(player: Player, amount: number)
	if not player or type(amount) ~= "number" or amount <= 0 then return end
	local _, _, level, xp = ensureLeaderstats(player)

	xp.Value += amount
	local lvl = level.Value
	while xp.Value >= xpNeededForLevel(lvl) do
		xp.Value -= xpNeededForLevel(lvl)
		lvl += 1
	end

	if lvl ~= level.Value then
		level.Value = lvl
		player:SetAttribute("HeroLevel", lvl)
	end
end

return Progression
