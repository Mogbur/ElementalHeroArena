-- Owner-only loot orbs that home to the Player's *Character* (HRP) — not the Hero.
-- Private audio: server fires a client-only SFX event to the owner on pickup.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")
local RS           = game:GetService("ReplicatedStorage")
local SSS          = game:GetService("ServerScriptService")

local Remotes      = RS:WaitForChild("Remotes")
local RE_LootSFX   = Remotes:WaitForChild("LootPickupSFX") -- add in RemotesInit (section 2)

local PlayerData   = require(SSS.RojoServer.Data.PlayerData)

local DropService = {}

local ELEM_COLORS = {
	Fire  = Color3.fromRGB(255,70, 60),
	Water = Color3.fromRGB( 80,160,255),
	Earth = Color3.fromRGB(90,200,120),
	Flux  = Color3.fromRGB(170,90, 255),
}
-- === FX tuning ===
local HOVER_TIME      = 0.5   -- float before homing
local HOMING_SPEED    = 48    -- studs/sec
local TIMEOUT_SECONDS = 60    -- how long to chase owner

-- Trail look
local TRAIL_LIFETIME  = 0.6
local TRAIL_WIDTH     = 0.55

-- put near the top (after services)
local function groundAbove(pos: Vector3): Vector3
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { workspace.CurrentCamera }
-- (keep FilterType = Exclude and IgnoreWater = false)
    params.IgnoreWater = false

    -- cast from well above downwards
    local origin = pos + Vector3.new(0, 100, 0)
    local res = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
    if res then
        -- sit just above the surface (orb radius ~0.4)
        return Vector3.new(pos.X, res.Position.Y + 1.1, pos.Z)
    end
    return pos + Vector3.new(0, 3, 0) -- fallback: a little above given pos
end

local function hrpOfPlayer(plr)
	local char = plr and plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function makeOrb(pos, color, ownerUserId)
	local p = Instance.new("Part")
	p.Name = "LootOrb"
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.8,0.8,0.8)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(pos)
	p:SetAttribute("OwnerUserId", ownerUserId)

	-- light
	local pl = Instance.new("PointLight")
	pl.Brightness = 1.2
	pl.Range = 10
	pl.Color = color
	pl.Parent = p

	-- trail (two attachments)
	local a0 = Instance.new("Attachment"); a0.Name = "Trail0"; a0.Position = Vector3.new(0,  0.35, 0); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Name = "Trail1"; a1.Position = Vector3.new(0, -0.35, 0); a1.Parent = p

	local tr = Instance.new("Trail")
	tr.Attachment0   = a0
	tr.Attachment1   = a1
	tr.Lifetime      = TRAIL_LIFETIME
	tr.MinLength     = 0.08
	tr.LightEmission = 0.7
	tr.Transparency  = NumberSequence.new{
		NumberSequenceKeypoint.new(0.0, 0.15),
		NumberSequenceKeypoint.new(1.0, 1.00)
	}
	tr.WidthScale    = NumberSequence.new{
		NumberSequenceKeypoint.new(0.0, TRAIL_WIDTH),
		NumberSequenceKeypoint.new(1.0, 0.0)
	}
	tr.Color         = ColorSequence.new(color) -- <— same color as orb
	tr.Parent = p

	p.Parent = workspace
	return p
end

local function tweenTo(part, targetCF, dur)
	return TweenService:Create(part, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = targetCF})
end

local function award(plr, payload)
	if not (plr and payload) then return end
	local flux = tonumber(payload.flux) or 0
	if flux > 0 then PlayerData.AddFlux(plr, flux) end
	if type(payload.essence) == "table" then
		for elem, amt in pairs(payload.essence) do
			amt = math.max(0, math.floor(tonumber(amt) or 0))
			if amt > 0 then PlayerData.AddEssence(plr, elem, amt) end
		end
	end
	pcall(function() require(SSS.RojoServer.Data.PlayerData).SaveNow(plr) end)
end

local function hasEssence(payload)
	if type(payload) ~= "table" then return false end
	if type(payload.essence) ~= "table" then return false end
	for _,v in pairs(payload.essence) do
		if (tonumber(v) or 0) > 0 then return true end
	end
	return false
end

local function runOrb(plr, startPos, color, payloadPerOrb)
	local ownerId = plr and plr.UserId or 0
	local orb = makeOrb(startPos, color, ownerId)
	if not orb then return end

	-- in runOrb(), replace the pop + immediate home with:
	local peak = startPos + Vector3.new(0, math.random(2,4), 0)
	tweenTo(orb, CFrame.new(peak), 0.2)
	task.wait(HOVER_TIME)  -- <— this is the wait you’ll tweak later


	local collected, timeoutAt = false, (time() + TIMEOUT_SECONDS)

	while orb.Parent and not collected and time() < timeoutAt do
		local hrp = hrpOfPlayer(plr)
		if not hrp then
			-- Owner missing -> wait briefly, then give up on timeout (no chasing others)
			task.wait(0.15)
			continue
		end

		local dest = hrp.Position + Vector3.new(0, 1.2, 0)
		local d = (dest - orb.Position).Magnitude
		local dur = math.clamp(d / HOMING_SPEED, 0.06, 0.22)
		local tw = tweenTo(orb, CFrame.new(dest), dur)
		tw:Play()

		local t = 0
		while t < dur do
			task.wait(0.03)
			t += 0.03
			local now = hrp.Position
			if (now - orb.Position).Magnitude < 2.2 then
				collected = true
				tw:Cancel()
				break
			end
		end
	end

	if collected then
		award(plr, payloadPerOrb)
		-- SFX + UI pulse info: include the deltas so client knows what to bounce
		local hasEss = type(payloadPerOrb.essence) == "table"
					and ((payloadPerOrb.essence.Fire or 0) > 0
					or (payloadPerOrb.essence.Water or 0) > 0
					or (payloadPerOrb.essence.Earth or 0) > 0)
		local sfxKind = hasEss and "essence" or "flux"

		-- keep it tiny: only send the deltas we just awarded
		local payload = {
			flux = payloadPerOrb.flux or 0,
			essence = {
				Fire  = (payloadPerOrb.essence and payloadPerOrb.essence.Fire)  or 0,
				Water = (payloadPerOrb.essence and payloadPerOrb.essence.Water) or 0,
				Earth = (payloadPerOrb.essence and payloadPerOrb.essence.Earth) or 0,
			}
		}

		RE_LootSFX:FireClient(plr, sfxKind, orb.Position, payload)
		-- shrink+fade
		local shrink = TweenService:Create(orb, TweenInfo.new(0.12), {
			Size = Vector3.new(0.1,0.1,0.1), Transparency = 1
		})
		shrink:Play()
		shrink.Completed:Wait()
	end

	if orb and orb.Parent then Debris:AddItem(orb, 0) end
end

-- Public API ---------------------------------------------------------

function DropService.SpawnLoot(plr, pos, payload, splitAcross)
	if not (plr and pos and payload) then return end
	splitAcross = math.max(1, math.floor(tonumber(splitAcross or 1) or 1))

	local per = { flux = 0, essence = {} }
	if payload.flux then per.flux = math.floor((tonumber(payload.flux) or 0) / splitAcross) end
	if type(payload.essence) == "table" then
		for k,v in pairs(payload.essence) do
			per.essence[k] = math.floor((tonumber(v) or 0) / splitAcross)
		end
	end

	local palette = {}
	local function push(c) table.insert(palette, c) end
	if splitAcross <= 1 then
		local dom, best = "Flux", (per.flux or 0)
		for _,k in ipairs({"Fire","Water","Earth"}) do
			local v = per.essence[k] or 0
			if v > best then best, dom = v, k end
		end
		push(ELEM_COLORS[dom] or Color3.new(1,1,1))
	else
		push(ELEM_COLORS.Flux); push(ELEM_COLORS.Fire); push(ELEM_COLORS.Water); push(ELEM_COLORS.Earth)
	end

	for i = 1, splitAcross do
		local offset = Vector3.new(math.random(-2,2), 0, math.random(-2,2))
		local col = palette[((i-1) % #palette) + 1]
		local start = groundAbove(pos + offset)         -- << clamp to surface here

		local each = { flux = per.flux, essence = {} }
		for k,v in pairs(per.essence) do each.essence[k] = v end

		task.spawn(runOrb, plr, start, col, each)
	end
end

function DropService.SpawnLootFrom(inst, plr, payload, splitAcross)
	if not inst then return end
	local pos
	if inst:IsA("Model") then pos = inst:GetPivot().Position
	elseif inst:IsA("BasePart") then pos = inst.Position end
	if pos then DropService.SpawnLoot(plr, pos, payload, splitAcross) end
end

return DropService
