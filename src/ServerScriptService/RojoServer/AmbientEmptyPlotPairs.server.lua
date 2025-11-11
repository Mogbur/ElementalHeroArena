-- ServerScriptService/RojoServer/AmbientEmptyPlotPairs.server.lua
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PLOTS = workspace:FindFirstChild("Plots") or workspace

-- ---------- helpers ----------
local function root(m) return m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart") end
local function faceYaw(part, toPos)
	if not part then return end
	local p = part.Position
	part.CFrame = CFrame.lookAt(p, Vector3.new(toPos.X, p.Y, toPos.Z))
end
local function findCritters(plot: Instance)
	return plot:FindFirstChild("AmbientCritters")
	    or plot:FindFirstChild("AmbientCritters", true) -- ✅ look in descendants (e.g. 01_State_Vacant/AmbientCritters)
end
-- Lift/align a model to the ground directly below its PrimaryPart
local function snapToGround(model)
	local rp = model.PrimaryPart or root(model)
	if not rp then return end
	task.defer(function()
		task.wait(0.5) -- give the plot some time to load its parts
		local origin = rp.Position + Vector3.new(0, 50, 0)
		local dir    = Vector3.new(0, -500, 0)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {model}
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(origin, dir, params)
		if hit then
			local y = hit.Position.Y + (rp.Size.Y * 0.5) + 0.05
			model:PivotTo(CFrame.new(rp.Position.X, y, rp.Position.Z))
		else
			warn("[snapToGround] No hit for", model.Name, "– keeping original Y", rp.Position.Y)
		end
	end)
end


-- Tween the *whole model* with a hop arc, via PivotTo (works for anchored blobs)
local function pivotHop(model, destPos, hopHeight, upT, downT, boing)
	local rp = model.PrimaryPart or root(model); if not rp then return end
	local start = rp.Position
	local mid   = (start + destPos)/2 + Vector3.new(0, hopHeight, 0)

	if boing then boing:Play() end

	local function pivotToPos(pos)
		-- face direction of travel a bit
		local dir = (destPos - start)
		local yaw = math.atan2(dir.X, -dir.Z)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	end

	-- simple manual tween so we don't need TweenService here
	local stepDt = 0.03

	local function lerpVec(a, b, t)
		return a + (b - a) * t
	end

	-- up phase
	do
		local elapsed = 0
		while elapsed < upT do
			local alpha = math.clamp(elapsed / upT, 0, 1)
			local pos   = lerpVec(start, mid, alpha)
			pivotToPos(pos)
			task.wait(stepDt)
			elapsed += stepDt
		end
	end

	-- down phase
	do
		local elapsed = 0
		while elapsed < downT do
			local alpha = math.clamp(elapsed / downT, 0, 1)
			local pos   = lerpVec(mid, destPos, alpha)
			pivotToPos(pos)
			task.wait(stepDt)
			elapsed += stepDt
		end
	end

	-- snap to exact dest at the end
	pivotToPos(destPos)
end

local function sanitizeSlimeModel(m, keepNames)
	keepNames = keepNames or {}

	-- delete scripts/humanoid/rig motors/GUI AND any old body movers/aligners
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Humanoid") then
			d:Destroy()

		elseif d:IsA("Motor6D") then
			d:Destroy()

		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()

		-- 🔥 kill anything that can move/steer it from old AI rigs
		elseif d:IsA("BodyPosition")
			or d:IsA("BodyVelocity")
			or d:IsA("BodyGyro")
			or d:IsA("BodyAngularVelocity")
			or d:IsA("AlignPosition")
			or d:IsA("AlignOrientation")
			or d:IsA("LinearVelocity")
			or d:IsA("AngularVelocity")
			or d:IsA("VectorForce") then
			d:Destroy()
		end
	end

	-- PrimaryPart = visible shell
	local rp = m:FindFirstChild("SlimeOutside", true)
		or m.PrimaryPart
		or m:FindFirstChild("HumanoidRootPart")
		or m:FindFirstChildWhichIsA("BasePart")

	if not rp then return end
	m.PrimaryPart = rp

	-- hide & de-power everything except the root / allowed names
	for _, bp in ipairs(m:GetDescendants()) do
		if bp:IsA("BasePart") then
			local keep = (bp == rp) or keepNames[bp.Name]
			if not keep then
				bp.Transparency = 1
				bp.CanCollide   = false
				bp.CanQuery     = false
				bp.CastShadow   = false
				bp.Massless     = true
			end

			-- if there is an HRP and it isn't the root, nuke it so it can’t flip back visible
			if bp.Name == "HumanoidRootPart" and bp ~= rp then
				bp:Destroy()
			end
		end
	end
end

local function nearestPlayerPos(pos)
	local best, dist = nil, math.huge
	for _,plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < dist then dist, best = d, hrp.Position end
		end
	end
	return best, dist
end
local function mountHat(slimeModel, hatAsset)
	if slimeModel:FindFirstChild(hatAsset.Name) then
		warn("Hat already mounted on", slimeModel.Name)
		return
	end
    local rp = root(slimeModel); if not (slimeModel and rp and hatAsset) then return end
    local hat = hatAsset:Clone()
    hat.Parent = slimeModel
	print("Mounting hat on", slimeModel:GetFullName())

    -- choose a base part (Accessory.Handle or any BasePart)
    local base =
        (hat:IsA("Accessory") and hat:FindFirstChild("Handle")) or
        (hat:IsA("Model") and (hat.PrimaryPart or hat:FindFirstChildWhichIsA("BasePart"))) or
        hat:FindFirstChildWhichIsA("BasePart")

    if not base then
        warn("[AmbientCritters] mountHat: no BasePart/Handle in hat:", hat:GetFullName())
        hat:Destroy()
        return
    end

	base.Transparency = 0       -- force it visible
	base.CanTouch     = false   -- don't steal touches
	base.CanQuery     = false
    base.CanCollide = false
    base.Massless   = true

    -- position offset (tweak if needed)
    local hatHeightFactor = (slimeModel.Name == "SlimePushable") and 0.40 or 0.55
	local yOff            = (rp.Size and rp.Size.Y or 3) * hatHeightFactor
    local offset = CFrame.new(0, yOff, 0) * CFrame.Angles(0, 0, math.rad(math.random(-10, 10)))

    if rp.Anchored then
        -- anchored slime (orbiter/jumper/passive): just keep the hat anchored
        base.Anchored = true
        -- follow RP each frame
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if not (slimeModel.Parent and rp.Parent and base.Parent) then
                if conn then conn:Disconnect() end
                return
            end
            base.CFrame = rp.CFrame * offset
        end)
        base.CFrame = rp.CFrame * offset
    else
        -- unanchored slime (pushable): weld the hat to the root
        base.Anchored = false
        local weld = Instance.new("WeldConstraint")
        weld.Part0, weld.Part1, weld.Parent = rp, base, rp
        base.CFrame = rp.CFrame * offset
    end
end

local function makePushable(model)
	-- keep only the slime shell visible
	sanitizeSlimeModel(model, { SlimeOutside = true })

	-- root = shell (SlimeOutside after sanitize)
	local rp = model.PrimaryPart or root(model)
	if not rp then return end
	rp.Massless = false

	-- weld everything to root & set physics flags
	for _,bp in ipairs(model:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			if bp ~= rp then
				bp.CanCollide = false  -- limbs / extra bits never collide
				if not bp:FindFirstChild("WeldToRoot") then
					local w = Instance.new("WeldConstraint")
					w.Name  = "WeldToRoot"
					w.Part0 = rp
					w.Part1 = bp
					w.Parent = rp
				end
			else
				bp.CanCollide = true   -- ✅ only root collides
			end
		end
	end
	snapToGround(model)

	-- light & slightly bouncy
	rp.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.2, 0, 1, 1)

	-- keep upright (lock pitch/roll; free yaw)
	local gyro = Instance.new("BodyGyro")
	gyro.Name       = "UprightGyro"
	gyro.MaxTorque  = Vector3.new(1e5, 0, 1e5)
	gyro.P          = 3e4
	gyro.D          = 600
	gyro.CFrame     = CFrame.new()
	gyro.Parent     = rp

	-- touch-to-kick
	local lastKickBy = {}
	rp.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit and hit.Parent)
		if not plr then return end
		local now = os.clock()
		if (now - (lastKickBy[plr] or 0)) < 0.25 then return end
		lastKickBy[plr] = now

		local dir = rp.Position - (hit.Position or rp.Position)
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 1e-3 then dir = Vector3.new(1,0,0) end
		dir = dir.Unit

		local m = rp:GetMass()
		rp:ApplyImpulse(dir * (m*80) + Vector3.new(0, m*25, 0))

		local kick = model:FindFirstChild("Kick") or model:FindFirstChild("Squeak") or model:FindFirstChild("Boing")
		if kick and kick:IsA("Sound") then kick:Play() end
	end)

	-- extra squeak on any contact (ground hits throttled)
	do
		local lastAnyTouch = 0
		rp.Touched:Connect(function(hit)
			if not hit or not hit:IsA("BasePart") then return end
			local now = os.clock()
			if now - lastAnyTouch < 0.15 then return end
			lastAnyTouch = now
			local s = model:FindFirstChild("Kick") or model:FindFirstChild("Squeak") or model:FindFirstChild("Boing")
			if s and s:IsA("Sound") then s:Play() end
		end)
	end
end

local function makeOrbiter(model)
	-- strip rig bits; keep SlimeOutside visible
	sanitizeSlimeModel(model, { SlimeOutside = true })

	-- anchored decorative blob, no collisions
	for _,bp in ipairs(model:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored   = true
			bp.CanCollide = false
			bp.Massless   = true
		end
	end

	-- make sure PrimaryPart is the shell
	local rp = (model:FindFirstChild("SlimeOutside", true) :: BasePart) or model.PrimaryPart or root(model)
	if rp then model.PrimaryPart = rp end

	-- place it sitting on the ground
	snapToGround(model)
end


-- consider a plot "empty" if PlotState == "Empty"
-- OR if PlotStateEmpty exists (bool true, or string "true"/"empty")
-- OR if no OwnerUserId yet.
local function plotIsEmpty(plot)
	local state = plot:GetAttribute("PlotState")
	if state == "Empty" then return true end
	local pse = plot:GetAttribute("PlotStateEmpty")
	if pse ~= nil then
		if typeof(pse) == "boolean" then return pse end
		local s = tostring(pse):lower()
		if s == "true" or s == "empty" then return true end
	end
	local owner = plot:GetAttribute("OwnerUserId")
	return owner == nil or owner == 0
end

local function childrenByPrefix(folder, prefix)
	local out = {}
	for _,c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") and c.Name:sub(1, #prefix) == prefix then table.insert(out, c) end
	end
	return out
end
local function getHat(name)
    local h = ReplicatedStorage:FindFirstChild("Hats")
    if h then return h:FindFirstChild(name) end
    return ReplicatedStorage:FindFirstChild(name)
end

local function activatePairOnPlot(plot)
	task.wait(1)  -- 🕐 give Roblox a second to finish loading models + terrain
	local critters = findCritters(plot)
	if not critters then
		warn("[AmbientCritters] No AmbientCritters under", plot:GetFullName())
		return
	end
	-- hat source: you put the Accessory at ReplicatedStorage/ChristmasHat
	local XmasHat = getHat("ChristmasHat")
	print("Hat?", XmasHat, "on", plot:GetFullName())

	-- 1) Pushables (bouncy football slimes)
	for _, pus in ipairs(childrenByPrefix(critters, "SlimePushable")) do
		makePushable(pus)
		task.wait(1) -- before mounting hats
		if XmasHat then mountHat(pus, XmasHat) end
		local prp = root(pus)

		task.spawn(function()
			task.wait(math.random(0.8, 1.3))  -- ⏱️ random startup delay per slime
			local Squeak = pus:FindFirstChild("Squeak") or pus:FindFirstChild("Boing") or pus:FindFirstChild("Kick")

			local IDLE_MIN, IDLE_MAX       = 3.0, 6.0   -- idle hop every 3–6s
			local ALERT_RADIUS             = 7.0        -- "player is near" distance
			local NEAR_NOISE_COOLDOWN      = 2.0        -- seconds between near squeaks

			local nextIdleAt     = os.clock() + math.random()*(IDLE_MAX-IDLE_MIN)+IDLE_MIN
			local lastNearNoiseT = -1e9

			while pus.Parent and plot.Parent do
				local now = os.clock()

				-- check nearest player distance
				local _, d = nearestPlayerPos(prp.Position)
				local playerClose = (d ~= math.huge and d < ALERT_RADIUS)

				if playerClose then
					-- player nearby → stop idle hopping
					nextIdleAt = now + 1.0

					-- but occasionally squeak while they’re hanging around
					if Squeak and (now - lastNearNoiseT) > NEAR_NOISE_COOLDOWN then
						lastNearNoiseT = now
						Squeak:Play()
					end
				else
					-- no player close → idle vertical hops
					if now >= nextIdleAt then
						nextIdleAt = now + math.random()*(IDLE_MAX-IDLE_MIN)+IDLE_MIN
						if Squeak then Squeak:Play() end

						local m = prp:GetMass()
						-- straight up impulse (no circles)
						prp:ApplyImpulse(Vector3.new(0, m * 45, 0))
					end
				end

				task.wait(0.1)
			end
		end)
	end


	-- 2) Orbiters (plain cute hoppers in place, no circles)
	for _, orb in ipairs(childrenByPrefix(critters, "Slime")) do
		-- Skip pushables & jumpers/passives we handle below
		if orb.Name:sub(1,12) == "SlimePushable"
			or orb.Name:sub(1,12) == "SlimeJumper"
			or orb.Name:sub(1,12) == "SlimePassive" then
			continue
		end

		makeOrbiter(orb)
		task.wait(1) -- before mounting hats
		if XmasHat then mountHat(orb, XmasHat) end

		local orp   = root(orb)
		local Boing = orb:FindFirstChild("Boing")
		local home  = orp.Position

		task.spawn(function()
			task.wait(math.random(0.8, 1.3))  -- ⏱️ random startup delay per slime
			local HOP_HEIGHT = 1.2
			local UP_T, DN_T = 0.22, 0.26
			local RADIUS     = 2.0

			while orb.Parent and plot.Parent do
				-- pick small random offset around its home spot
				local offset = Vector3.new(
					math.random(-RADIUS*100, RADIUS*100) / 100,
					0,
					math.random(-RADIUS*100, RADIUS*100) / 100
				)
				local dest = home + offset
				pivotHop(orb, dest, HOP_HEIGHT, UP_T, DN_T, Boing)
				task.wait(math.random(30, 70) / 100) -- 0.30–0.70 seconds between hops
			end
		end)
	end


	-- 3) Jumpers (random hops in place)
	for _, j in ipairs(childrenByPrefix(critters, "SlimeJumper")) do
		makeOrbiter(j)
		task.wait(1) -- before mounting hats
		if XmasHat then mountHat(j, XmasHat) end
		local jp = root(j); local Boing = j:FindFirstChild("Boing")
		local home = jp.Position
		task.spawn(function()
			task.wait(math.random(0.8, 1.3))  -- ⏱️ random startup delay per slime
			while j.Parent and plot.Parent do
				local offset = Vector3.new(math.random(-4,4), 0, math.random(-4,4))
				pivotHop(j, home + offset, 1.6, 0.22, 0.26, Boing)
				task.wait(math.random(0.3, 0.8))
			end
		end)
	end

	-- 4) Passive (subtle idle bob + occasional squeak; face player if present)
	for _, p in ipairs(childrenByPrefix(critters, "SlimePassive")) do
		makeOrbiter(p)
		task.wait(1) -- before mounting hats
		if XmasHat then mountHat(p, XmasHat) end
		local pp = root(p)
		local basePos = pp.Position
		task.spawn(function()
			task.wait(math.random(0.8, 1.3))  -- ⏱️ random startup delay per slime
			while p.Parent and plot.Parent do
				-- tiny sine bob
				local t = os.clock()
				local y = math.sin(t*4) * 0.05
				pp.CFrame = CFrame.new(basePos + Vector3.new(0, y, 0))

				-- face nearest player if any
				local pos, d = nearestPlayerPos(pp.Position)
				if pos and d < 20 then faceYaw(pp, pos) end

				-- occasional idle squeak
				if math.random() < 0.08 then
					local s = p:FindFirstChild("Boing") or p:FindFirstChild("Squeak")
					if s and s:IsA("Sound") then s:Play() end
				end

				task.wait(0.25)
			end
		end)
	end
end

local function wirePlot(plot)
	if not plot:IsA("Model") then return end

	-- ✅ check if this plot (or any subfolder like 01_State_Vacant) actually has AmbientCritters
	local hasCritters = (findCritters(plot) ~= nil)

	-- if the plot is empty OR it at least has critters, wire it
	if plotIsEmpty(plot) or hasCritters then
		activatePairOnPlot(plot)
	end

	-- cleanup when claimed / removed
	local a
	a = plot.AttributeChanged:Connect(function(n)
		if n == "PlotState" or n == "PlotStateEmpty" or n == "OwnerUserId" then
			if not plotIsEmpty(plot) then
				-- plot got claimed → remove ambient slimes
				local crit = findCritters(plot)
				if crit then crit:Destroy() end
				if a then a:Disconnect() end
			end
		end
	end)

	plot.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			if a then a:Disconnect() end
		end
	end)
end

-- wire existing + future plots
for _,m in ipairs(PLOTS:GetChildren()) do wirePlot(m) end
PLOTS.ChildAdded:Connect(function(m) task.wait(0.05); wirePlot(m) end)
