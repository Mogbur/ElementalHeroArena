local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local function ensureGroup(name)
	pcall(function() PhysicsService:CreateCollisionGroup(name) end)
end

ensureGroup("Player")
ensureGroup("Hero")
ensureGroup("Enemy")
ensureGroup("Effects")

-- Collisions: player passes through everything combat-y
PhysicsService:CollisionGroupSetCollidable("Player", "Hero",   false)
PhysicsService:CollisionGroupSetCollidable("Player", "Enemy",  false)
PhysicsService:CollisionGroupSetCollidable("Player", "Effects",false)

-- Combat collides with itself
PhysicsService:CollisionGroupSetCollidable("Hero",  "Enemy",   true)
PhysicsService:CollisionGroupSetCollidable("Hero",  "Hero",    true)
PhysicsService:CollisionGroupSetCollidable("Enemy", "Enemy",   true)

local function setGroupModel(model, group)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			PhysicsService:SetPartCollisionGroup(d, group)
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
