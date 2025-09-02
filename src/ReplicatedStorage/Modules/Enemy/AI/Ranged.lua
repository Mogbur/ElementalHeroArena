-- ReplicatedStorage/Modules/Enemy/Brains/Ranged.lua
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")
local Combat = require(RS:WaitForChild("Modules"):WaitForChild("Combat"))

local Ranged = {}
local TICK = 0.12
local DEFAULTS = {
	WalkSpeed=10, KeepMin=7.0, KeepMax=12.0, Cooldown=1.6,
	ProjectileSpeed=90, ProjectileLife=3, HardMin=7.0, PinTime=2, StrafeStep=5.0, BackStepClamp=3.0,
}

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

local function fireProjectile(fromRoot, targetPos, dmg, cfg, elem)
	local p = Instance.new("Part")
	p.Name = "EnemyShot"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.6, 0.6, 0.6)
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(120, 200, 255)
	p.CanCollide = false
	p.Massless = true
	p.CFrame = CFrame.new(fromRoot.Position + Vector3.new(0, 2.8, 0))
	p.Parent = workspace
	p:SetNetworkOwner(nil)

	local speed = cfg.ProjectileSpeed or 90
	local g = workspace.Gravity
	local to = targetPos - p.Position
	local horiz = Vector3.new(to.X, 0, to.Z)
	local t = horiz.Magnitude / speed
	local drop = 0.5 * g * t * t
	local aimPos = targetPos + Vector3.new(0, drop, 0)
	local dir = (aimPos - p.Position); if dir.Magnitude < 1e-3 then dir = Vector3.new(0,0,-1) end
	p.AssemblyLinearVelocity = dir.Unit * speed

	local conn
	conn = p.Touched:Connect(function(hit)
		local heroModel = hit and hit:FindFirstAncestorWhichIsA("Model")
		if heroModel and heroModel:GetAttribute("IsHero") then
			local hh = heroModel:FindFirstChildOfClass("Humanoid")
			if hh and hh.Health > 0 then
				Combat.ApplyDamage(nil, heroModel, dmg, elem)
				if conn then conn:Disconnect() end
				p:Destroy()
			end
		end
	end)
	Debris:AddItem(p, cfg.ProjectileLife or 2.0)
end

function Ranged.start(model, cfg)
	cfg = cfg or {}; for k,v in pairs(DEFAULTS) do if cfg[k]==nil then cfg[k]=v end end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root= model:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return function() end end
	hum.AutoRotate=true; hum.PlatformStand=false; hum.UseJumpPower=false; hum.JumpPower=0
	hum.WalkSpeed = math.max(hum.WalkSpeed, cfg.WalkSpeed)

	local BASE_DMG = model:GetAttribute("BaseDamage") or 10
	local OWNER = model:GetAttribute("OwnerUserId") or 0
	local lastAtk = 0
	local strafeDir = (math.random() < 0.5) and 1 or -1
	local running = true
	local pinnedUntil= 0

	task.spawn(function()
		while running and model.Parent and hum.Health > 0 do
			local hero, hh, hr = findHero(OWNER)
			if hero then
				local toHero = hr.Position - root.Position
				local dir = unit2D(toHero)
				local dist = Vector3.new(toHero.X,0,toHero.Z).Magnitude
				local now = os.clock()
				if now < pinnedUntil then
					hum:Move(Vector3.zero)
					if (now - lastAtk) >= cfg.Cooldown then
						lastAtk = now
						fireProjectile(root, hr.Position, BASE_DMG, cfg, model:GetAttribute("Element"))
					end
				else
					local hardMin = cfg.HardMin or math.max(6, (cfg.KeepMin or 9) - 3)
					if dist <= hardMin then pinnedUntil = now + (cfg.PinTime or 0.4) end
					if dist < (cfg.KeepMin or 9) then
						local tangent = Vector3.new(-dir.Z, 0, dir.X) * strafeDir
						local aim = root.Position + tangent * (cfg.StrafeStep or 8) - dir * (cfg.BackStepClamp or 3)
						hum:MoveTo(aim)
					elseif dist > (cfg.KeepMax or 14) then
						hum:MoveTo(hr.Position)
					else
						hum:Move(Vector3.zero)
						if (now - lastAtk) >= cfg.Cooldown then
							lastAtk = now
							strafeDir = -strafeDir
							fireProjectile(root, hr.Position, BASE_DMG, cfg, model:GetAttribute("Element"))
						end
					end
				end
			end
			task.wait(TICK)
		end
	end)

	return function() running=false end
end

return Ranged
