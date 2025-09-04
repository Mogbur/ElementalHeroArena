-- ServerScriptService/RojoServer/Systems/WeaponStands.server.lua
-- Finds weapon stands in plots, shows display weapons, and equips styles for the plot owner.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local PLOTS_CONTAINER = workspace:WaitForChild("Plots")
local WeaponsFolder   = ReplicatedStorage:WaitForChild("Weapons")
local SSS = game:GetService("ServerScriptService")
local WeaponVisuals = require(SSS.RojoServer.Modules.WeaponVisuals)

-- ========= helpers =========

local function firstBasePartIn(model: Instance): BasePart?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function ensurePrimaryPart(m: Model): BasePart?
	if not m.PrimaryPart then
		local p = firstBasePartIn(m)
		if p then m.PrimaryPart = p end
	end
	return m.PrimaryPart
end

local function setAnchoredNoCollide(inst: Instance, anchored: boolean)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
			d.CanCollide = false
		end
	end
end

local function within(node: Instance, ancestor: Instance): boolean
	local cur = node
	while cur do
		if cur == ancestor then return true end
		cur = cur.Parent
	end
	return false
end

local function findPlot(model: Instance): Model?
	local cur = model
	while cur do
		if cur:IsA("Model") and cur:GetAttribute("OwnerUserId") ~= nil then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function getHero(plot: Model): Model?
	return plot and plot:FindFirstChild("Hero", true)
end

local function styleFromStandName(name: string): string
	local n = name:lower()
	if n:find("bow")  then return "Bow" end
	if n:find("mace") then return "Mace" end
	return "SwordShield"
end

local function currentStyleId(hero: Model?): string
	if not hero then return "SwordShield" end
	local main = (hero:GetAttribute("WeaponMain") or "Sword"):lower()
	local off  = (hero:GetAttribute("WeaponOff")  or ""):lower()
	if main == "bow" then return "Bow" end
	if main == "mace" then return "Mace" end
	if main == "sword" and off == "shield" then return "SwordShield" end
	return "SwordShield"
end

-- small posing helpers
local OFFSETS = {
	-- for StandSwordShield
	SwordShield_Sword  = CFrame.Angles(math.rad(180), 0, math.rad(0)), -- tip down + slight roll
	SwordShield_Shield = CFrame.Angles(0, math.rad(180), 0),            -- face outward
	-- for single-weapon stands
	Bow  = CFrame.Angles(0, math.rad(90), 0),
	Mace = CFrame.Angles(math.rad(180), 0, 0),
}

local function placeDisplay(modelToClone: Model, pivot: BasePart, offset: CFrame?, parent: Instance)
	local clone = modelToClone:Clone()
	ensurePrimaryPart(clone)
	if not clone.PrimaryPart then
		warn("[WeaponStands] Model has no BasePart:", modelToClone:GetFullName())
		clone:Destroy()
		return nil
	end
	setAnchoredNoCollide(clone, true)
	clone:PivotTo(pivot.CFrame * (offset or CFrame.new()))
	clone.Parent = parent
	return clone
end

local function clearFolder(folder: Instance)
	for _, c in ipairs(folder:GetChildren()) do c:Destroy() end
end

-- ========= display refresh =========

local function refreshStandDisplay(stand: Model)
	local plot = findPlot(stand)
	local hero = getHero(plot)
	local style = styleFromStandName(stand.Name)
	local equipped = currentStyleId(hero)

	local display = stand:FindFirstChild("Display")
	if not display then
		display = Instance.new("Folder")
		display.Name = "Display"
		display.Parent = stand
	end

	clearFolder(display)
	if style == equipped then
		-- Equipped set lives on the hero; keep the stand empty.
		return
	end

	if style == "SwordShield" then
		local swordM  = WeaponsFolder:FindFirstChild("W_Sword")
		local shieldM = WeaponsFolder:FindFirstChild("W_Shield")
		local swordPivot  = stand:FindFirstChild("SwordPivot")
		local shieldPivot = stand:FindFirstChild("ShieldPivot")
		if swordM and swordPivot and swordPivot:IsA("BasePart") then
			placeDisplay(swordM,  swordPivot,  OFFSETS.SwordShield_Sword,  display)
		end
		if shieldM and shieldPivot and shieldPivot:IsA("BasePart") then
			placeDisplay(shieldM, shieldPivot, OFFSETS.SwordShield_Shield, display)
		end
	elseif style == "Bow" then
		local bowM = WeaponsFolder:FindFirstChild("W_Bow")
		local pivot = stand:FindFirstChild("WeaponPivot")
		if bowM and pivot and pivot:IsA("BasePart") then
			placeDisplay(bowM, pivot, OFFSETS.Bow, display)
		end
	elseif style == "Mace" then
		local maceM = WeaponsFolder:FindFirstChild("W_Mace")
		local pivot = stand:FindFirstChild("WeaponPivot")
		if maceM and pivot and pivot:IsA("BasePart") then
			placeDisplay(maceM, pivot, OFFSETS.Mace, display)
		end
	end
end

-- ========= equip action =========

local function setStyleOnHero(hero: Model, style: string)
	if style == "SwordShield" then
		hero:SetAttribute("WeaponMain", "Sword")
		hero:SetAttribute("WeaponOff",  "Shield")
	elseif style == "Bow" then
		hero:SetAttribute("WeaponMain", "Bow")
		hero:SetAttribute("WeaponOff",  "")
	elseif style == "Mace" then
		hero:SetAttribute("WeaponMain", "Mace")
		hero:SetAttribute("WeaponOff",  "")
	end
end

local function onStandTriggered(stand: Model, player: Player)
	local plot = findPlot(stand); if not plot then return end
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	if ownerId ~= 0 and player.UserId ~= ownerId then
		return -- only owner can change their hero
	end

	local hero = getHero(plot); if not hero then return end
	local style = styleFromStandName(stand.Name)

	setStyleOnHero(hero, style)
	player:SetAttribute("WeaponMain", hero:GetAttribute("WeaponMain"))
	player:SetAttribute("WeaponOff",  hero:GetAttribute("WeaponOff"))
    pcall(function() WeaponVisuals.apply(hero) end)

	-- Refresh all stands in this plot
	for _, s in ipairs(plot:GetDescendants()) do
		if s:IsA("Model") and s:FindFirstChild("StandRoot") then
			task.defer(refreshStandDisplay, s)
		end
	end
end

-- ========= bootstrap =========

local function isWeaponStandModel(m: Instance): boolean
	if not m:IsA("Model") then return false end
	-- either explicit names or presence of StandRoot + a known pivot
	local n = m.Name:lower()
	if n == "standswordshield" or n == "standbow" or n == "standmace" then return true end
	if m:FindFirstChild("StandRoot") then
		if m:FindFirstChild("SwordPivot") or m:FindFirstChild("ShieldPivot") or m:FindFirstChild("WeaponPivot") then
			return true
		end
	end
	return false
end

local function wireStand(stand: Model)
	-- must be under workspace.Plots (ignore shops)
	if not within(stand, PLOTS_CONTAINER) then return end

	local root = stand:FindFirstChild("StandRoot")
	if not (root and root:IsA("BasePart")) then
		-- Quietly ignore non-stand models; no spammy warns.
		return
	end
	stand.PrimaryPart = root

	local prompt = stand:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = root -- attach to the root so UI hovers near the stand base
	end

	local style = styleFromStandName(stand.Name)
	prompt.ObjectText = "Weapon Stand"
	if style == "SwordShield" then
		prompt.ActionText = "Equip Sword & Shield"
	elseif style == "Bow" then
		prompt.ActionText = "Equip Bow"
	else
		prompt.ActionText = "Equip Mace"
	end

	prompt.Triggered:Connect(function(plr) onStandTriggered(stand, plr) end)

	refreshStandDisplay(stand)
end

local function scanAndWire(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if isWeaponStandModel(d) then wireStand(d) end
	end
end

-- Wire stands that already exist (plots only)
scanAndWire(PLOTS_CONTAINER)

-- If you drop new stands during runtime
workspace.DescendantAdded:Connect(function(d)
	if isWeaponStandModel(d) and within(d, PLOTS_CONTAINER) then
		task.defer(wireStand, d)
	end
end)

-- Keep visuals in sync when the owner's hero spawns
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		task.wait(0.2)
		for _, plot in ipairs(PLOTS_CONTAINER:GetChildren()) do
			if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == plr.UserId then
				for _, s in ipairs(plot:GetDescendants()) do
					if s:IsA("Model") and s:FindFirstChild("StandRoot") then
						task.defer(refreshStandDisplay, s)
					end
				end
			end
		end
	end)
end)
