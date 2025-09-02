-- ReplicatedStorage/Modules/Enemy/Brains/Runner.lua
local RS = game:GetService("ReplicatedStorage")
local Combat = require(RS:WaitForChild("Modules"):WaitForChild("Combat"))

local Runner = {}
local TICK = 0.12
local DEFAULTS = { WalkSpeed=18, AttackRange=6.5, Cooldown=1.0, RetreatTime=0.6, BackStep=2.5, SideStep=6.0 }

local function isMyHero(m, ownerId)
	return m and m:IsA("Model") and m:GetAttribute("IsHero") and (m:GetAttribute("OwnerUserId") or 0) == (ownerId or 0)
end
local function findHero(ownerId)
	for _, m in ipairs(workspace:GetDescendants()) do
		if isMyHero(m, ownerId) then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local hrp = m:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then return m, hum, hrp end
		end
	end
end
local function unit2D(v) local u=Vector3.new(v.X,0,v.Z); if u.Magnitude<1e-4 then return Vector3.new(1,0,0) end; return u.Unit end

function Runner.start(model, cfg)
	cfg = cfg or {}; for k,v in pairs(DEFAULTS) do if cfg[k]==nil then cfg[k]=v end end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root= model:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return function() end end
	hum.AutoRotate=true; hum.PlatformStand=false; hum.UseJumpPower=false; hum.JumpPower=0
	hum.WalkSpeed = math.max(hum.WalkSpeed, cfg.WalkSpeed)

	local BASE_DMG = (model:GetAttribute("BaseDamage") or 10) * 0.9
	local OWNER = model:GetAttribute("OwnerUserId") or 0
	local lastAtk = 0
	local retreatEnds = 0
	local strafeSide = (math.random()<0.5) and 1 or -1
	local running = true

	task.spawn(function()
		while running and model.Parent and hum.Health > 0 do
			local hero, hh, hr = findHero(OWNER)
			if hero then
				local toHero = hr.Position - root.Position
				local dir = unit2D(toHero)
				local dist = (Vector3.new(toHero.X,0,toHero.Z)).Magnitude
				local now = os.clock()

				if now < retreatEnds then
					local tangent = Vector3.new(-dir.Z,0,dir.X) * strafeSide
					local aim = root.Position - dir * cfg.BackStep + tangent * cfg.SideStep
					hum:MoveTo(aim)
				elseif dist > cfg.AttackRange then
					hum:MoveTo(hr.Position)
				else
					hum:Move(Vector3.zero)
					if (now - lastAtk) >= cfg.Cooldown then
						lastAtk = now
						retreatEnds = now + cfg.RetreatTime
						strafeSide = -strafeSide
						Combat.ApplyDamage(nil, hero, BASE_DMG, model:GetAttribute("Element"))
					end
				end
			end
			task.wait(TICK)
		end
	end)
	return function() running=false end
end

return Runner
