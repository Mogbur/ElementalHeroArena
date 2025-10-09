-- ServerScriptService/DropService.lua
-- Spawns loot orbs that home to a Player's Character (HRP), not the Hero model.
-- Awards Flux and/or Essence on pickup.

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local Debris         = game:GetService("Debris")
local RS             = game:GetService("ReplicatedStorage")
local SSS            = game:GetService("ServerScriptService")

local PlayerData     = require(SSS.RojoServer.Data.PlayerData)

local DropService = {}

-- Optional: small ping sound (server-side so everyone hears it lightly)
local PICKUP_SOUND_ID = "rbxassetid://13189443030" -- swap if you have a different one

-- Colors for element orbs
local ELEM_COLORS = {
	Fire  = Color3.fromRGB(255,140,80),
	Water = Color3.fromRGB(90,180,255),
	Earth = Color3.fromRGB(200,175,120),
	Flux  = Color3.fromRGB(240,240,80),
}

-- Make a simple neon sphere “orb”
local function makeOrb(pos : Vector3, color : Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.8, 0.8, 0.8)
	p.Anchored = true
	p.CanQuery = false
	p.CanCollide = false
	p.CanTouch = false
	p.CFrame = CFrame.new(pos)
	p.Name = "LootOrb"

	-- faint glow & bob
	local a0 = Instance.new("Attachment", p)
	local pl = Instance.new("PointLight", p)
	pl.Brightness = 1.2
	pl.Range = 12
	pl.Color = color

	-- pickup sound
	local s = Instance.new("Sound")
	s.SoundId = PICKUP_SOUND_ID
	s.Volume = 0.5
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 60
	s.Parent = p

	p.Parent = workspace
	return p, s
end

local function hrpOfPlayer(plr : Player)
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

-- Tween helper toward a moving target
local function tweenTo(part : BasePart, targetCF : CFrame, t : number)
	local ti = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(part, ti, {CFrame = targetCF})
	tw:Play()
	return tw
end

-- Award payload to a player (server-side)
local function award(plr : Player, payload)
	if not plr or not payload then return end
	local flux = tonumber(payload.flux) or 0
	if flux > 0 then
		PlayerData.AddFlux(plr, flux)
	end
	local ess = payload.essence
	if type(ess) == "table" then
		for elem, amt in pairs(ess) do
			local n = math.max(0, math.floor(tonumber(amt) or 0))
			if n > 0 then
				PlayerData.AddEssence(plr, elem, n)
			end
		end
	end
	pcall(function() require(SSS.RojoServer.Data.PlayerData).SaveNow(plr) end)
end

-- Single orb life-cycle: spawns, bobs up, then homes to player's HRP until collected
local function runOrb(plr : Player, startPos : Vector3, color : Color3, payloadPerOrb)
	local orb, sfx = makeOrb(startPos, color)
	if not orb then return end

	-- little pop-up tween first
	local peak = startPos + Vector3.new(0, math.random(2,4), 0)
	tweenTo(orb, CFrame.new(peak), 0.2).Completed:Wait()

	-- Track player HRP
	local collected = false
	local timeout = time() + 15 -- auto-timeout after 15s

	while orb.Parent and not collected do
		-- find target: player's character HRP (NOT hero)
		local hrp = hrpOfPlayer(plr)

		-- if player missing, try nearest character in 60 studs; otherwise fade out
		if not hrp then
			local best, bestDist = nil, 1e9
			for _, p in ipairs(Players:GetPlayers()) do
				local h = hrpOfPlayer(p)
				if h then
					local d = (h.Position - orb.Position).Magnitude
					if d < 60 and d < bestDist then best, bestDist = h, d end
				end
			end
			hrp = best
		end

		if not hrp then
			if time() > timeout then break end
			task.wait(0.1)
		else
			local dest = hrp.Position + Vector3.new(0, 1.2, 0)
			local d = (dest - orb.Position).Magnitude
			local dur = math.clamp(d / 40, 0.05, 0.25) -- faster when farther away
			local tw = tweenTo(orb, CFrame.new(dest), dur)

			-- check proximity while tweening
			local elapsed = 0
			while elapsed < dur do
				task.wait(0.03)
				elapsed += 0.03
				local nowd = (hrp.Position - orb.Position).Magnitude
				if nowd < 2.2 then
					collected = true
					break
				end
			end
			if collected then tw:Cancel() end
		end

		if time() > timeout then break end
	end

	-- collect or cleanup
	if collected then
		-- play pickup sound once on the orb, then destroy
		pcall(function() sfx:Play() end)
		award(plr, payloadPerOrb)
		-- quick shrink/fade
		local shrink = TweenService:Create(orb, TweenInfo.new(0.12), {Size = Vector3.new(0.1,0.1,0.1), Transparency = 1})
		shrink:Play()
		shrink.Completed:Wait()
	end

	if orb and orb.Parent then Debris:AddItem(orb, 0) end
end

---------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------

-- Spawns one or more orbs at 'pos' that home to 'plr' and award payload.
-- payload = { flux = number?, essence = {Fire=number?, Water=number?, Earth=number?} }
-- splitAcross = how many separate orbs to spawn (defaults to 1); each orb gets a fair share.
function DropService.SpawnLoot(plr : Player, pos : Vector3, payload : table, splitAcross : number?)
	if not (plr and pos and payload) then return end

	splitAcross = math.max(1, math.floor(tonumber(splitAcross or 1) or 1))

	-- compute per-orb amounts
	local per = { flux = 0, essence = {} }
	if payload.flux then per.flux = math.floor((tonumber(payload.flux) or 0) / splitAcross) end
	if type(payload.essence) == "table" then
		for k,v in pairs(payload.essence) do
			per.essence[k] = math.floor((tonumber(v) or 0) / splitAcross)
		end
	end

	-- Decide colors for visual flavor:
	--  - if single-orb: pick dominant resource color
	--  - if multiple orbs: rotate between Flux/Fire/Water/Earth visually
	local palette = {}
	local function push(c) table.insert(palette, c) end
	if splitAcross <= 1 then
		local dom = "Flux"
		local best = per.flux or 0
		for _,k in ipairs({"Fire","Water","Earth"}) do
			local v = per.essence[k] or 0
			if v > best then best, dom = v, k end
		end
		push(ELEM_COLORS[dom] or Color3.fromRGB(255,255,255))
	else
		push(ELEM_COLORS.Flux); push(ELEM_COLORS.Fire); push(ELEM_COLORS.Water); push(ELEM_COLORS.Earth)
	end

	for i = 1, splitAcross do
		-- small scatter around the start position
		local offset = Vector3.new(math.random(-2,2), 0, math.random(-2,2))
		local p = pos + offset
		local col = palette[((i-1) % #palette)+1]

		-- copy the per-orb payload (don’t mutate shared tables)
		local each = { flux = per.flux, essence = {} }
		for k,v in pairs(per.essence) do each.essence[k] = v end

		task.spawn(runOrb, plr, p, col, each)
	end
end

-- Helper: drop directly from a Model or BasePart (uses its pivot or position)
function DropService.SpawnLootFrom(inst : Instance, plr : Player, payload : table, splitAcross : number?)
	if not inst then return end
	local pos
	if inst:IsA("Model") then
		pos = inst:GetPivot().Position
	elseif inst:IsA("BasePart") then
		pos = inst.Position
	end
	if pos then
		DropService.SpawnLoot(plr, pos, payload, splitAcross)
	end
end

return DropService
