-- ServerScriptService/CollisionGroups.server.lua (modern API)
local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")

local function ensureGroup(name)
	pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
end

ensureGroup("Player")
ensureGroup("Hero")
ensureGroup("Enemy")
ensureGroup("Effects")

-- Collisions: players pass through combat stuff
pcall(function() PhysicsService:CollisionGroupSetCollidable("Player","Hero",    false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Player","Enemy",   false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Player","Effects", false) end)

-- Combat collides with itself (tweak if you want heroes to pass through each other)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Hero","Enemy",  true) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Hero","Hero",   true) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Enemy","Enemy", true) end)

local function setGroupModel(model: Instance, group: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group -- <-- modern way
		end
	end
end

-- Tag player characters
local function onChar(char)
	setGroupModel(char, "Player")
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(onChar)
	if plr.Character then onChar(plr.Character) end
end)

-- Initial pass for any pre-placed heroes in Plots
local plots = workspace:FindFirstChild("Plots")
if plots then
	for _, d in ipairs(plots:GetDescendants()) do
		if d:IsA("Model") and d.Name == "Hero" then
			setGroupModel(d, "Hero")
		end
	end
end
