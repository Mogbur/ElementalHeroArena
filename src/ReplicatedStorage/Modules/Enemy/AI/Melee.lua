-- ReplicatedStorage/Enemy/Brains/Melee.lua
local Melee = {}

local TICK       = 0.15
local DEFAULTS = {
	WalkSpeed   = 12,
	AttackRange = 6.0,
	Cooldown    = 0.8,
	StopPad     = 4.0, -- aim to arrive just short of the hero
}

local function isMyHero(m, ownerId)
	return m
		and m:IsA("Model")
		and m:GetAttribute("IsHero")
		and (m:GetAttribute("OwnerUserId") or 0) == (ownerId or 0)
end

local function findHero(ownerId)
	for _, m in ipairs(workspace:GetDescendants()) do
		if isMyHero(m, ownerId) then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local hrp = m:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				return m, hum, hrp
			end
		end
	end
end

local function stopPoint(fromPos, heroPos, stopDist)
	local dir = (heroPos - fromPos)
	local d   = dir.Magnitude
	if d < 1e-3 then return heroPos end
	return heroPos - dir.Unit * stopDist
end

function Melee.start(model, cfg)
	cfg = cfg or {}
	for k,v in pairs(DEFAULTS) do if cfg[k] == nil then cfg[k] = v end end

	local hum  = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return function() end end

	-- bring the rig to life
	hum.AutoRotate = true
	hum.PlatformStand = false
	hum.UseJumpPower = false
	hum.JumpPower = 0
	hum.WalkSpeed = math.max(hum.WalkSpeed, cfg.WalkSpeed)

	local BASE_DMG = model:GetAttribute("BaseDamage") or 10
	local OWNER    = model:GetAttribute("OwnerUserId") or 0
	local lastAtk  = 0
	local running  = true

	task.spawn(function()
		while running and model.Parent and hum.Health > 0 do
			local hero, hh, hr = findHero(OWNER)
			if hero then
				local toHero = (hr.Position - root.Position)
				local dist   = toHero.Magnitude

				if dist > cfg.AttackRange then
					hum:MoveTo(stopPoint(root.Position, hr.Position, math.max(cfg.AttackRange - 1.0, 2.0)))
				else
					hum:Move(Vector3.zero)
					local now = os.clock()
					if (now - lastAtk) >= cfg.Cooldown then
						lastAtk = now
						hh:TakeDamage(BASE_DMG)
					end
				end
			end
			task.wait(TICK)
		end
	end)

	return function() running = false end
end

return Melee
