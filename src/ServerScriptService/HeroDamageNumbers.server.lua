-- ServerScriptService/HeroDamageNumbers.server.lua
-- Minimal incoming-damage numbers (players + Hero models only), rendered on the server.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DamageNumbers = require(RS:WaitForChild("Modules"):WaitForChild("DamageNumbers"))

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function popIncoming(model, amount)
	local r = rootOf(model)
	if not r then return end
	DamageNumbers.pop(r, math.floor(amount + 0.5), Color3.fromRGB(255, 80, 80), { sizeMul = 0.85 })
end

local function attach(model, hum)
	if not (model and hum) then return end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		local prev = last
		last = h
		local delta = prev - h
		if delta > 0 then
			popIncoming(model, delta)
		end
	end)
end

-- Players’ characters
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then attach(char, hum) end
	end)
	if plr.Character then
		local hum = plr.Character:FindFirstChildOfClass("Humanoid")
		if hum then attach(plr.Character, hum) end
	end
end)

-- Plot “Hero” models (Model named "Hero" with a Humanoid)
local function tryAttachHero(model)
	if model:IsA("Model") and model.Name == "Hero" then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then attach(model, hum) end
	end
end

task.defer(function()
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, d in ipairs(plots:GetDescendants()) do tryAttachHero(d) end
		plots.DescendantAdded:Connect(tryAttachHero)
	end
end)
