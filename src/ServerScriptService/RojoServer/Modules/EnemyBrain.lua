-- ServerScriptService/RojoServer/Modules/EnemyBrain.lua
local CollectionService = game:GetService("CollectionService")
local SSS   = game:GetService("ServerScriptService")
local SMods = SSS:WaitForChild("RojoServer"):WaitForChild("Modules")

local Combat = require(SMods:WaitForChild("Combat"))
-- === per-owner hero cache (weak table) ===
local heroCache = setmetatable({}, { __mode = "v" }) -- [ownerId] = {hero=Model, hum=Humanoid, root=BasePart, conns={...}}

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
	-- 1) cached
	local rec = heroCache[ownerId]
	if cacheValid(rec) then return rec.hero, rec.hum, rec.root end

	-- 2) search only this owner's plot
	local plot = plotOfOwner(ownerId)
	if plot then
		local h = plot:FindFirstChild("Hero", true)
		if h then
			local hum = h:FindFirstChildOfClass("Humanoid")
			local root = h.PrimaryPart or h:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				-- cache & auto-invalidate
				rec = { hero = h, hum = hum, root = root, conns = {} }
				rec.conns[#rec.conns+1] = h.Destroying:Connect(function() heroCache[ownerId] = nil end)
				rec.conns[#rec.conns+1] = hum.Died:Connect(function() heroCache[ownerId] = nil end)
				heroCache[ownerId] = rec
				return h, hum, root
			end
		end
	end
	-- (no global fallback)
end

local Brain = {}
local ACTIVE = setmetatable({}, { __mode = "k" })

function Brain.attach(enemy: Model, ctx)
	if ACTIVE[enemy] then return ACTIVE[enemy] end
	if enemy:GetAttribute("UseLegacyBrain") == false then return end

	local hum = enemy:FindFirstChildOfClass("Humanoid")
	local hrp = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
	if not (hum and hrp) then
		warn("[EnemyBrain] Missing Humanoid/Root on", enemy:GetFullName())
		return
	end

	hum.AutoRotate = true
	hum.WalkSpeed = math.max(10, hum.WalkSpeed)
	hum.JumpPower = 0
	hum.UseJumpPower = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	task.defer(function() pcall(function() hrp:SetNetworkOwner(nil) end) end)

	if not CollectionService:HasTag(enemy,"Enemy") then CollectionService:AddTag(enemy,"Enemy") end

	local OWNER    = enemy:GetAttribute("OwnerUserId") or 0
	local BASE_DMG = enemy:GetAttribute("BaseDamage") or 10
	local ATK_RANGE= 6.0
	local TICK     = 0.15
	local COOLDOWN = 0.8
	local lastAtk  = 0

	local function stopPoint(fromPos, heroPos)
		local dir = (heroPos - fromPos); local d = dir.Magnitude
		if d < 1e-3 then return heroPos end
		return heroPos - (dir/d) * math.max(ATK_RANGE - 1.0, 2.0)
	end

	local conns = {}
	local running = true
	table.insert(conns, enemy.Destroying:Connect(function() Brain.detach(enemy) end))
	table.insert(conns, hum.Died:Connect(function() end))

	ACTIVE[enemy] = { conns = conns, hum = hum, hrp = hrp, running = running }

	task.spawn(function()
		while running and enemy.Parent do
			task.wait(TICK)
			if hum.Health <= 0 then break end

			local hero, hh, hr = findHero(OWNER)
			if not hero then continue end


			local dist = (hr.Position - hrp.Position).Magnitude
			if dist > ATK_RANGE then
				hum:MoveTo(stopPoint(hrp.Position, hr.Position))
			else
				hum:Move(Vector3.zero)
				local now = os.clock()
				if (now - lastAtk) >= COOLDOWN then
					lastAtk = now
					Combat.ApplyDamage(nil, hero, BASE_DMG, enemy:GetAttribute("Element"))
				end
			end
		end
	end)

	return ACTIVE[enemy]
end

function Brain.detach(enemy: Model)
	local s = ACTIVE[enemy]; if not s then return end
	for _,c in ipairs(s.conns or {}) do pcall(function() c:Disconnect() end) end
	ACTIVE[enemy] = nil
end

return Brain
