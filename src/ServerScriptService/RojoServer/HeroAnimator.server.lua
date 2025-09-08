-- ServerScriptService/HeroAnimator.server.lua
local RunService = game:GetService("RunService")

local function findShoulder(model)
	-- R15
	local rs = model:FindFirstChild("RightUpperArm", true)
	if rs then
		local sh = rs:FindFirstChildWhichIsA("Motor6D")
		if sh then return sh, "R15" end
	end
	-- R6
	local rarm = model:FindFirstChild("Right Arm", true)
	if rarm then
		local torso = model:FindFirstChild("Torso", true)
		if torso then
			for _,m in ipairs(torso:GetChildren()) do
				if m:IsA("Motor6D") and m.Part1 == rarm then
					return m, "R6"
				end
			end
		end
	end
	return nil
end

local function safeC0(m6) return m6 and m6.C0 or CFrame.new() end

local function swingOnce(hero)
	local sh, rig = findShoulder(hero)
	if not sh then return end
	if hero:GetAttribute("_Swinging") then return end
	hero:SetAttribute("_Swinging", true)

	local base = safeC0(sh)
	local t0 = tick()
	local dur = 0.32
	local function curve(a) -- ease
		return math.sin(a*math.pi)
	end
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = tick() - t0
		local a = math.clamp(t/dur, 0, 1)
		local angle = math.rad(100) * curve(a)
		sh.C0 = base * CFrame.Angles(0, 0, -angle)
		if a >= 1 then
			sh.C0 = base
			hero:SetAttribute("_Swinging", false)
			conn:Disconnect()
		end
	end)

	-- play slash SFX if exists
	local sfx = hero:FindFirstChild("SFX", true)
	local slash = sfx and sfx:FindFirstChild("Slash")
	if slash and slash:IsA("Sound") then slash:Play() end
end

local function castPose(hero)
	local sh, rig = findShoulder(hero)
	if not sh then return end
	local base = safeC0(sh)
	local up = base * CFrame.Angles(0, 0, math.rad(-65))
	sh.C0 = up
	task.delay(0.25, function() if sh.Parent then sh.C0 = base end end)

	local sfx = hero:FindFirstChild("SFX", true)
	local cast = sfx and sfx:FindFirstChild("Cast")
	if cast and cast:IsA("Sound") then cast:Play() end
end

local function watchHero(hero)
	if not hero:IsDescendantOf(workspace) then return end
	local hum = hero:FindFirstChildOfClass("Humanoid"); if not hum then return end

	-- footsteps (optional)
	hum.Running:Connect(function(speed)
		if speed > 2 then
			local sfx = hero:FindFirstChild("SFX", true)
			local step = sfx and sfx:FindFirstChild("Step")
			if step and not step.IsPlaying then step:Play() end
		end
	end)

	-- triggers from the brain via attributes
	hero:GetAttributeChangedSignal("MeleeTick"):Connect(function()
		swingOnce(hero)
	end)
	hero:GetAttributeChangedSignal("CastTick"):Connect(function()
		local id = hero:GetAttribute("CastTick")
		if id and id ~= "" then castPose(hero) end
	end)
end

-- attach to any "Hero" that appears
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d.Name == "Hero" and d:FindFirstChildOfClass("Humanoid") then
		task.defer(watchHero, d)
	end
end)
for _,d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and d.Name == "Hero" and d:FindFirstChildOfClass("Humanoid") then
		task.defer(watchHero, d)
	end
end
