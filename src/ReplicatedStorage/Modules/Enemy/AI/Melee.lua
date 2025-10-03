-- ReplicatedStorage/Modules/Enemy/Brains/Melee.lua
local RS = game:GetService("ReplicatedStorage")
local Combat = require(RS:WaitForChild("Modules"):WaitForChild("Combat"))

local Melee = {}
local TICK = 0.15
local DEFAULTS = { WalkSpeed=12, AttackRange=6.0, Cooldown=0.8, StopPad=4.0 }
-- === per-owner hero cache (weak) ===
local heroCache = setmetatable({}, { __mode = "v" }) -- [ownerId] = {hero, hum, root, conns}

local function cacheValid(rec)
	return rec and rec.hero and rec.hero.Parent and rec.hum and rec.hum.Health > 0 and rec.root
end

local function plotOfOwner(ownerId)
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _,p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and (p:GetAttribute("OwnerUserId") or 0) == ownerId then
			return p
		end
	end
end

local function findHero(ownerId)
	local rec = heroCache[ownerId]
	if cacheValid(rec) then return rec.hero, rec.hum, rec.root end

	local plot = plotOfOwner(ownerId)
	if plot then
		local h = plot:FindFirstChild("Hero", true)
		if h then
			local hum = h:FindFirstChildOfClass("Humanoid")
			local root = h.PrimaryPart or h:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				rec = { hero = h, hum = hum, root = root, conns = {} }
				rec.conns[#rec.conns+1] = h.Destroying:Connect(function() heroCache[ownerId] = nil end)
				rec.conns[#rec.conns+1] = hum.Died:Connect(function() heroCache[ownerId] = nil end)
				heroCache[ownerId] = rec
				return h, hum, root
			end
		end
	end
end

local function isMyHero(m, ownerId)
	return m and m:IsA("Model") and m:GetAttribute("IsHero") and (m:GetAttribute("OwnerUserId") or 0) == (ownerId or 0)
end
local function stopPoint(fromPos, heroPos, stopDist)
	local dir = (heroPos - fromPos); if dir.Magnitude < 1e-3 then return heroPos end
	return heroPos - dir.Unit * stopDist
end

function Melee.start(model, cfg)
	cfg = cfg or {}; for k,v in pairs(DEFAULTS) do if cfg[k]==nil then cfg[k]=v end end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root= model:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return function() end end
	hum.AutoRotate=true; hum.PlatformStand=false; hum.UseJumpPower=false; hum.JumpPower=0
	hum.WalkSpeed = math.max(hum.WalkSpeed, cfg.WalkSpeed)

	local BASE_DMG = model:GetAttribute("BaseDamage") or 10
	local OWNER = model:GetAttribute("OwnerUserId") or 0
	local lastAtk = 0
	local running = true

	task.spawn(function()
		while running and model.Parent and hum.Health > 0 do
			local hero, hh, hr = findHero(OWNER)
			if hero then
				local dist = (hr.Position - root.Position).Magnitude
				if dist > cfg.AttackRange then
					hum:MoveTo(stopPoint(root.Position, hr.Position, math.max(cfg.AttackRange - 1.0, 2.0)))
				else
					hum:Move(Vector3.zero)
					local now = os.clock()
					if (now - lastAtk) >= cfg.Cooldown then
						lastAtk = now
						Combat.ApplyDamage(nil, hero, BASE_DMG, model:GetAttribute("Element"))
					end
				end
			end
			task.wait(TICK)
		end
	end)

	return function() running=false end
end

return Melee
