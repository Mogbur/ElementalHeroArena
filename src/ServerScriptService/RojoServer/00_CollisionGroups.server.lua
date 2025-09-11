-- ServerScriptService/CollisionGroups.server.lua (modern API)
local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")

-- ========== helpers ==========
local function ensureGroup(name)
	pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
end

local function setCollidable(a, b, tf)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(a, b, tf) end)
end

local function setGroupPart(part: Instance, group: string)
	if part and part:IsA("BasePart") then
		part.CollisionGroup = group
	end
end

local function setGroupModel(model: Instance, group: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

-- ========== groups ==========
ensureGroup("Player")
ensureGroup("Hero")
ensureGroup("Enemy")
ensureGroup("Effects")
ensureGroup("ArenaGround") -- NEW: ground/floor parts go here

-- Keep your original rules (unchanged)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Player","Hero",    false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Player","Enemy",   false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Player","Effects", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Hero","Effects", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Hero","Enemy",  true)  end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Hero","Hero",   true)  end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Enemy","Enemy", true)  end)

-- Explicit, normal collisions with ground (so physics feels normal)
setCollidable("ArenaGround","Player",      true)
setCollidable("ArenaGround","Hero",        true)
setCollidable("ArenaGround","Enemy",       true)
setCollidable("ArenaGround","Effects",     true)
setCollidable("ArenaGround","ArenaGround", true)

-- ========== auto-tag characters ==========
local function onChar(char: Model)
	setGroupModel(char, "Player")
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(onChar)
	if plr.Character then onChar(plr.Character) end
end)

-- ========== ground + anchor configuration ==========
local function configureGroundAndAnchor(root: Instance)
	if not root then return end
	-- Sand and HeroSpawn should never fire touches (they were causing damage)
	local sand      = root:FindFirstChild("Sand", true)
	local heroSpawn = root:FindFirstChild("HeroSpawn", true)

	if sand and sand:IsA("BasePart") then
		setGroupPart(sand, "ArenaGround")
		sand.CanTouch = false
	end
	if heroSpawn and heroSpawn:IsA("BasePart") then
		setGroupPart(heroSpawn, "ArenaGround")
		heroSpawn.CanTouch = false
	end

	-- Your transparent anchor
	local anchor = root:FindFirstChild("07_HeroArenaAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		setGroupPart(anchor, "Effects")  -- harmless group
		anchor.CanTouch   = false
		-- anchor.CanCollide stays false per your properties
	end
end

-- Initial pass for any pre-placed heroes in Plots (keep your original bit)
local plots = workspace:FindFirstChild("Plots")
if plots then
	for _, d in ipairs(plots:GetDescendants()) do
		if d:IsA("Model") and d.Name == "Hero" then
			setGroupModel(d, "Hero")
		end
	end

	-- NEW: tag the ground & anchor now
	for _, plot in ipairs(plots:GetChildren()) do
		configureGroundAndAnchor(plot)
	end

	-- NEW: keep it robust if parts get replaced during play
	plots.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") then return end
		if d.Name == "Sand" or d.Name == "HeroSpawn" then
			setGroupPart(d, "ArenaGround")
			d.CanTouch = false
		elseif d.Name == "07_HeroArenaAnchor" then
			setGroupPart(d, "Effects")
			d.CanTouch = false
		end
	end)
end
