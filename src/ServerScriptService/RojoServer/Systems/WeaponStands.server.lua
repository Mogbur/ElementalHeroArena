-- ServerScriptService/RojoServer/Systems/WeaponStands.server.lua
-- Finds weapon stands in plots, shows display weapons, and equips styles for the plot owner.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local PLOTS_CONTAINER = workspace:WaitForChild("Plots")
local WeaponsFolder   = ReplicatedStorage:WaitForChild("Weapons")
local SSS = game:GetService("ServerScriptService")
local WeaponVisuals do
    local ok, mod = pcall(function()
        return require(SSS.RojoServer.Modules.WeaponVisuals)
    end)
    if ok and mod then
        WeaponVisuals = mod
    else
        WeaponVisuals = require(SSS:WaitForChild("Modules"):WaitForChild("WeaponVisuals"))
    end
end
-- bring WeaponStyles so we can apply HP/ATK/SPD multipliers
local WeaponStyles = require(ReplicatedStorage.Modules.WeaponStyles)

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
			d.CanTouch   = false           -- <<< add
            d.CollisionGroup = "Effects"   -- <<< add
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
	SwordShield_Sword  = CFrame.Angles(math.rad(180), 0, math.rad(0)),
	SwordShield_Shield = CFrame.Angles(0, math.rad(180), 0),
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

-- apply base HP/ATK/SPD multipliers + CurrentStyle to player, and re-scale HP smoothly
local function applyBaseMults(player, hero, styleId)
    local S = WeaponStyles[styleId] or {}
    player:SetAttribute("CurrentStyle", styleId)
    player:SetAttribute("StyleAtkMul", S.atkMul or 1)
    player:SetAttribute("StyleSpdMul", S.spdMul or 1)
    player:SetAttribute("StyleHpMul",  S.hpMul  or 1)

    local hum = hero:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        hero:SetAttribute("GuardAllowDrop", 1)

        local lastMul = player:GetAttribute("LastHpMul") or 1
        local baseMax = hero:GetAttribute("BaseMaxHealth")
        if not baseMax or baseMax <= 0 then
            baseMax = hum.MaxHealth / math.max(0.01, lastMul)
        end
        baseMax = math.max(1, math.floor(baseMax + 0.5))

        local newMax  = math.max(1, baseMax * (S.hpMul or 1))
        local ratio   = hum.Health / math.max(1, hum.MaxHealth)

        hum.MaxHealth = newMax
        hum.Health = math.clamp(math.floor(newMax * ratio + 0.5), 1, newMax)
        player:SetAttribute("LastHpMul", S.hpMul or 1)

        task.delay(0.2, function()
            if hero and hero.Parent then hero:SetAttribute("GuardAllowDrop", 0) end
        end)
    end
end

local function onStandTriggered(stand: Model, player: Player)
	local plot = findPlot(stand); if not plot then return end
	-- block changes while waves are running
	if plot:GetAttribute("CombatLocked") == false then
		return
	end
	-- block unless hero is truly parked at idle anchor
	if plot:GetAttribute("AtIdle") ~= true then
		return
	end
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	if ownerId ~= 0 and player.UserId ~= ownerId then
		return -- only owner can change their hero
	end

	local hero = getHero(plot); if not hero then return end
	local style = styleFromStandName(stand.Name)

	setStyleOnHero(hero, style)
	player:SetAttribute("WeaponMain", hero:GetAttribute("WeaponMain"))
	player:SetAttribute("WeaponOff",  hero:GetAttribute("WeaponOff"))

	applyBaseMults(player, hero, style) -- apply multipliers immediately
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
	if not within(stand, PLOTS_CONTAINER) then return end

	local root = stand:FindFirstChild("StandRoot")
	if not (root and root:IsA("BasePart")) then return end
	stand.PrimaryPart = root
	root.CanTouch = false
    root.CollisionGroup = "Effects"  -- <<< safe bucket

	local prompt = stand:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "WeaponStandPrompt"
		prompt.MaxActivationDistance = 6
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false   -- start disabled; we’ll flip it on in syncPrompt()
		prompt.Parent = root
	end

	local style = styleFromStandName(stand.Name)
	prompt.ObjectText = "Weapon Stand"
	prompt.ActionText = (style == "SwordShield") and "Equip Sword & Shield"
		or (style == "Bow" and "Equip Bow")
		or "Equip Mace"

	-- ✅ compute once, capture it — DO NOT call findPlot(model)
	local plot = findPlot(stand)

	-- inside wireStand()
	-- do NOT compute plot once; always recompute inside sync
	local function syncPrompt()
		if not prompt or not prompt.Parent then return end
		local plot = findPlot(stand)

		-- Allow only when truly idle and not fighting
		local atIdle   = plot and (plot:GetAttribute("AtIdle") == true)
		local fighting = plot and (plot:GetAttribute("CombatLocked") == false)
		prompt.Enabled = (atIdle == true) and (fighting ~= true)
	end

	-- Keep trying until the plot exists, then hook signals
	local function hookWhenReady()
		local plot = findPlot(stand)
		if not plot then
			-- plot attrs not created yet; try again shortly
			task.delay(0.25, hookWhenReady)
			return
		end

		-- optional debug
		print(("[Stands] Wire %s | AtIdle=%s | CombatLocked=%s")
			:format(stand:GetFullName(), tostring(plot:GetAttribute("AtIdle")), tostring(plot:GetAttribute("CombatLocked"))))

		plot:GetAttributeChangedSignal("AtIdle"):Connect(syncPrompt)
		plot:GetAttributeChangedSignal("CombatLocked"):Connect(syncPrompt)
		syncPrompt() -- evaluate now that the attrs exist
	end

	-- start disabled; we’ll flip it on in syncPrompt()
	prompt.Enabled = false
	syncPrompt()      -- harmless first pass
	hookWhenReady()   -- ensures we hook once the plot is ready


	syncPrompt()
	if plot then
		plot:GetAttributeChangedSignal("AtIdle"):Connect(function()
			-- (optional) more debug
			-- print("[Stands] AtIdle ->", plot:GetAttribute("AtIdle"))
			syncPrompt()
		end)
		plot:GetAttributeChangedSignal("CombatLocked"):Connect(function()
			-- print("[Stands] CombatLocked ->", plot:GetAttribute("CombatLocked"))
			syncPrompt()
		end)
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
