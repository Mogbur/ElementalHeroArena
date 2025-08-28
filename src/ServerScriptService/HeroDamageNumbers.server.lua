-- Minimal incoming-damage numbers (players + Hero models only).
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Remotes = RS:WaitForChild("Remotes")
local RE_DMG  = Remotes:WaitForChild("DamageNumbers")

local last = setmetatable({}, {__mode="k"}) -- weak keys so we don't leak hums

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function isEnemyModel(model)
	return model and (model:GetAttribute("IsEnemy") == true or model.Name == "Enemy")
end

local function attach(model, hum)
	if not (model and hum) then return end
	if isEnemyModel(model) then return end -- don't show for enemies here
	last[hum] = hum.Health

	hum.HealthChanged:Connect(function(h)
		local prev = last[hum] or h
		last[hum] = h
		local delta = prev - h
		if delta > 0 then
			local r = rootOf(model)
			if r then
				RE_DMG:FireAllClients({
					amount = math.floor(delta + 0.5),
					pos    = r.Position,
					color  = Color3.fromRGB(255, 80, 80),
					kind   = "incoming", -- stays SMALL in your SkillVFX
				})
			end
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

-- initial scan + future spawns
task.defer(function()
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, d in ipairs(plots:GetDescendants()) do tryAttachHero(d) end
		plots.DescendantAdded:Connect(tryAttachHero)
	end
end)
