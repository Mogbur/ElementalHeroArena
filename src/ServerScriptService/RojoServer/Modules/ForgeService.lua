-- ServerScriptService/Modules/ForgeService.lua
local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local ServerStorage = game:GetService("ServerStorage")

local PlayerData = require(
	game:GetService("ServerScriptService")
		:WaitForChild("RojoServer")
		:WaitForChild("Data")
		:WaitForChild("PlayerData")
)

local Templates = ServerStorage:WaitForChild("Templates")

local Forge = {}
local Run   = setmetatable({}, {__mode="k"})   -- per-player run: state table
local ShrineByPlot = {}                        -- plot -> Model (shrine/forge)

local function ensureRE(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local RE_Open  = ensureRE("OpenForgeUI")
local RE_HUD   = ensureRE("ForgeHUD")
local RE_Close = ensureRE("CloseForgeUI") -- optional

-- ====== simple tuning (Zone1 base; scale later) ======
local CORE_POOL = {
	{id="ATK", name="+8% Attack", pct=8, t1=80, t2=120, t3=180},
	{id="HP",  name="+6% Max HP", pct=6, t1=80, t2=120, t3=180},
	{id="HST", name="+6% Haste",  pct=6, t1=80, t2=120, t3=180},
}

-- Utilities: lasts 1 segment (5 waves)
local UTIL_POOL = {
	{id="RECOVER",     name="Heal for 60% Max Health",     price=120},
	{id="SECOND_WIND", name="Second Wind (+1 life)",       price=160},
	{id="OVERCHARGE",  name="Overcharge (+20% Core)",      price=160},
	{id="AEGIS",       name="Aegis (Shield ~20% Max HP)",  price=120},
}

-- Reroll economy per segment
local REROLL_BASE = 40
local REROLL_STEP = 20

-- Segment id (0-based)
local function segIdFromWave(wave)
	wave = tonumber(wave) or 1
	return math.floor((wave - 1) / 5)
end

-- Elements cycle order for Blessing
local ELEMENTS = {"Fire", "Water", "Earth"}

local function groundSnap(pos: Vector3, ignore: {Instance}?)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore or {}

	local origin = pos + Vector3.new(0, 120, 0)
	local dir    = Vector3.new(0, -400, 0)

	local hit = workspace:Raycast(origin, dir, rp)
	if hit then
		return hit.Position
	end
	return pos
end

local function getFlux(plr: Player): number
	-- Your PlayerData has d.Flux mirrored to attribute too, but PlayerData is the source of truth.
	local d = PlayerData.Get(plr)
	if d and typeof(d.Flux) == "number" then
		return d.Flux
	end
	local a = plr:GetAttribute("Flux")
	if typeof(a) == "number" then
		return a
	end
	return 0
end

local function spendFlux(plr: Player, amount: number): boolean
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 then return true end
	return PlayerData.SpendFlux(plr, amount) == true
end

function Forge:GetRun(plr)
	Run[plr] = Run[plr] or {
		core = nil,
		rerolls = 0,
		segId = nil,

		-- blessing caching
		blessIndex = nil,
		blessWave = nil,
		blessOffer = nil,

		-- offer caching
		offers = nil,
		offersWave = nil,
		forceUtilRefresh = false,

		-- vip
		vipFreeLeft = false,
	}
	return Run[plr]
end

-- ===== Offers =====
function Forge:Offers(plr, wave)
	local run = self:GetRun(plr)
	local waveNum = tonumber(wave) or 1
	local segNow = segIdFromWave(waveNum)

	-- reset per-segment counters
	if run.segId ~= segNow then
		run.segId = segNow
		run.rerolls = 0
		run.vipFreeLeft = (plr:GetAttribute("VIP") == true)
		-- NOTE: we do NOT reset blessIndex here; rotation is run-persistent.
	end

	-- core init (tier 0 until first buy)
	run.core = run.core or { id = CORE_POOL[1].id, tier = 0, name = CORE_POOL[1].name }

	-- find core def
	local def = nil
	for _,c in ipairs(CORE_POOL) do
		if c.id == run.core.id then def = c; break end
	end
	def = def or CORE_POOL[1]

	-- next core price (tier 1..3)
	local nextTier = math.clamp(run.core.tier + 1, 1, 3)
	local nextPrice = (nextTier == 1 and def.t1) or (nextTier == 2 and def.t2) or def.t3

	local coreOffer = {
		id    = run.core.id,
		name  = def.name,
		tier  = run.core.tier, -- 0..3 current tier
		pct   = def.pct,
		price = nextPrice,     -- price to buy next tier
	}

	-- utility offer (cached per-wave unless rerolled)
	if not run.offers or run.offersWave ~= waveNum or run.forceUtilRefresh then
		run.forceUtilRefresh = false
		local util = table.clone(UTIL_POOL[math.random(1, #UTIL_POOL)])
		run.offers = { core = coreOffer, util = util }
		run.offersWave = waveNum
	else
		run.offers.core = coreOffer
	end

	-- Blessing micro-card (W15+), must NOT change when reopening UI on same wave.
	local bless = nil
	if waveNum >= 16 then
		-- If we already computed the blessing for THIS wave, reuse it.
		if run.blessWave == waveNum and run.blessOffer then
			bless = run.blessOffer
		else
			-- Advance rotation ONLY when wave changes to a new eligible wave.
			run.blessIndex = ((run.blessIndex or 0) % #ELEMENTS) + 1
			local elem = ELEMENTS[run.blessIndex]

			-- simple zone scaler: every 30 waves = +100
			local zone = 1 + math.floor((waveNum - 1) / 30)
			local blessPrice = 100 * zone

			bless = {
				id    = "BLESS",
				elem  = elem,
				name  = ("Elemental Blessing: %s"):format(elem),
				price = blessPrice,
			}

			run.blessWave = waveNum
			run.blessOffer = bless
		end
	else
		-- not eligible yet; clear cached blessing for safety
		run.blessWave = nil
		run.blessOffer = nil
	end

	-- Reroll pricing & free flag
	local rerollCost = REROLL_BASE + (run.rerolls * REROLL_STEP)
	local free = false
	if run.vipFreeLeft then free = true end
	if plr:GetAttribute("RerollVoucher") == true then free = true end

	return {
		core   = table.clone(run.offers.core),
		util   = table.clone(run.offers.util),
		bless  = bless and table.clone(bless) or nil,
		reroll = { cost = rerollCost, free = free, seg = run.segId },
	}
end

local function ownerPlayer(plot)
	local uid = plot:GetAttribute("OwnerUserId")
	if not uid then return nil end
	return Players:GetPlayerByUserId(uid)
end

-- Simple shield helper used by AEGIS
local function grantAegisShield(hero: Model, frac: number, seconds: number?)
	frac    = tonumber(frac) or 0.20   -- 20%
	seconds = tonumber(seconds) or 9000  -- optional duration if you want it timed

	local hum = hero and hero:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local max = math.max(1, math.floor(hum.MaxHealth + 0.5))
	local pool = math.max(1, math.floor(max * frac + 0.5))

	hero:SetAttribute("ShieldHP", pool)
	hero:SetAttribute("ShieldMax", pool)
	if seconds and seconds > 0 then
		hero:SetAttribute("ShieldExpireAt", os.clock() + seconds)
	else
		hero:SetAttribute("ShieldExpireAt", 0)
	end
end

local function rerollTarget(self, plr, plot, waveNum)
	local run = self:GetRun(plr)
	-- Before Tier 1: reroll CORE; After Tier 1: reroll UTIL
	if (run.core and run.core.tier >= 1) then
		-- reroll Util
		run.forceUtilRefresh = true
	else
		-- reroll Core id only (rotate to a different core)
		local cur = run.core and run.core.id or "ATK"
		local pool = {"ATK","HP","HST"}
		local choices = {}
		for _,id in ipairs(pool) do
			if id ~= cur then table.insert(choices, id) end
		end
		local newId = choices[math.random(1, #choices)]
		-- switch to the new core (keep same tier)
		for _,c in ipairs(CORE_POOL) do
			if c.id == newId then
				run.core = { id=newId, name=c.name, tier=run.core and run.core.tier or 0 }
				break
			end
		end
	end
end

-- ========= shrine model + VFX =========
local function mkShrineModel()
	local m = Instance.new("Model")
	m.Name = "ForgeShrine"

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(4,1,4)
	base.Anchored = true
	base.Material = Enum.Material.Slate
	base.Color = Color3.fromRGB(64,66,72)
	base.Parent = m

	local orb = Instance.new("Part")
	orb.Name = "Crystal"
	orb.Shape = Enum.PartType.Ball
	orb.Size  = Vector3.new(1.7,1.7,1.7)
	orb.Anchored = true
	orb.Material = Enum.Material.Glass
	orb.Color = Color3.fromRGB(135,206,235)
	orb.Transparency = 0.25
	orb.Parent = m

	local light = Instance.new("PointLight")
	light.Range = 12; light.Brightness = 2
	light.Parent = orb

	local pp = Instance.new("ProximityPrompt")
	pp.Name = "OpenPrompt"
	pp.ObjectText = "Elemental Forge"
	pp.ActionText = "Open"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 12
	pp.Parent = orb

	return m, base, orb, pp
end

local function portalFx(parent, cframe, mode) -- mode: "appear" or "vanish"
	local fx = Instance.new("Folder")
	fx.Name = "ForgePortalFX"
	fx.Parent = parent

	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(110, 180, 255)
	ring.Transparency = (mode=="appear") and 0.35 or 0.15
	ring.CFrame = cframe
	ring.Size = Vector3.new(0.2,0.2,0.2)
	ring.Parent = fx

	-- rotate so the cylinder faces you (vertical “portal” disc)
	ring.CFrame *= CFrame.Angles(0, math.rad(90), 0)

	local ti1 = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local ti2 = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	if mode=="appear" then
		TweenService:Create(ring, ti1, {Size=Vector3.new(10,0.2,10), Transparency=0.15}):Play()
		task.delay(1.2, function()
			TweenService:Create(ring, ti2, {Size=Vector3.new(12,0.2,12), Transparency=1}):Play()
			game:GetService("Debris"):AddItem(fx, 1.1)
		end)
	else
		TweenService:Create(ring, ti1, {Size=Vector3.new(10,0.2,10), Transparency=0.15}):Play()
		task.delay(1.2, function()
			TweenService:Create(ring, ti2, {Size=Vector3.new(0.2,0.2,0.2), Transparency=1}):Play()
			game:GetService("Debris"):AddItem(fx, 1.1)
		end)
	end
end

local function findAnchorInPlot(plot)
	local anchor = plot:FindFirstChild("ArenaCenter", true)
		or plot:FindFirstChild("03_HeroAnchor", true)
		or plot:FindFirstChild("Arena", true)
	if anchor and anchor:IsA("Model") then
		anchor = anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart")
	end
	return anchor
end

local function collectGroundParts(plot: Model)
	local list = {}

	-- IMPORTANT: scan the whole plot, because PlotGround is a sibling of Arena
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("BasePart") and d.CanQuery then
			-- Best: collision group "ArenaGround"
			if d.CollisionGroup == "ArenaGround" then
				table.insert(list, d)
			else
				-- Fallback naming (if you haven’t set ArenaGround everywhere)
				local n = d.Name:lower()
				if n:find("ground") or n:find("floor") or n:find("plotground") or n:find("sand") or n:find("baseplate") then
					table.insert(list, d)
				end
			end
		end
	end

	-- Only include Terrain if we found NOTHING in the plot (safety fallback)
	if #list == 0 and workspace:FindFirstChildOfClass("Terrain") then
		table.insert(list, workspace.Terrain)
	end

	return list
end

-- True world min-Y of an oriented box (Part or OBB)
local function partMinWorldY(p: BasePart): number
	local cf = p.CFrame
	local sx, sy, sz = p.Size.X, p.Size.Y, p.Size.Z

	-- project half-extents onto world Y axis
	local halfY =
		0.5 * (
			math.abs(cf.RightVector.Y) * sx +
			math.abs(cf.UpVector.Y)    * sy +
			math.abs(cf.LookVector.Y)  * sz
		)

	return p.Position.Y - halfY
end

local function obbMinWorldY(cf: CFrame, size: Vector3): number
	local sx, sy, sz = size.X, size.Y, size.Z
	local halfY =
		0.5 * (
			math.abs(cf.RightVector.Y) * sx +
			math.abs(cf.UpVector.Y)    * sy +
			math.abs(cf.LookVector.Y)  * sz
		)

	return cf.Position.Y - halfY
end

-- Returns the world Y of the model's true bottom face
local function modelBottomWorldY(m: Model): number?
	local bottom = m:FindFirstChild("BottomPlate", true)
	if bottom and bottom:IsA("BasePart") then
		return partMinWorldY(bottom)
	end

	-- fallback: oriented bounding box
	local cf, size = m:GetBoundingBox()
	return obbMinWorldY(cf, size)
end

local function snapForgeToGround(plot: Model, m: Model, startPos: Vector3?)
	if not (plot and m and m.Parent) then return end

	local rp = RaycastParams.new()
	local grounds = collectGroundParts(plot)

	if #grounds > 0 then
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = grounds
	else
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { m }
	end

	local origin = startPos or m:GetPivot().Position
	local start = origin + Vector3.new(0, 200, 0)

	local hit = workspace:Raycast(start, Vector3.new(0, -1200, 0), rp)
	if not hit then return end

	print("[ForgeSnap] hit=", hit.Instance:GetFullName(),
		"Y=", hit.Position.Y,
		"CanQuery=", hit.Instance.CanQuery,
		"CG=", hit.Instance.CollisionGroup)


	local bottomY = modelBottomWorldY(m)
	if not bottomY then return end

	local epsilon = 0.05 -- tiny lift so it never z-fights the sand
	local desiredBottomY = hit.Position.Y + epsilon

	local deltaY = desiredBottomY - bottomY
	if math.abs(deltaY) < 1e-4 then return end

	local pv = m:GetPivot()
	m:PivotTo(pv + Vector3.new(0, deltaY, 0))
end


function Forge:SpawnElementalForge(plot: Model)
	-- already present?
	local existing = plot:FindFirstChild("ElementalForge")
	if existing then
		ShrineByPlot[plot] = existing
		return existing
	end

	local tpl = Templates:FindFirstChild("ElementalForgeTemplate")
	if not tpl then
		warn("[ForgeService] No ElementalForgeTemplate in ServerStorage/Templates")
		return nil
	end

	-- choose anchor (prefer ArenaCenter)
	local anchor = plot:FindFirstChild("ArenaCenter", true)
		or plot:FindFirstChild("03_HeroAnchor", true)
		or plot:FindFirstChild("Arena", true)
	if anchor and anchor:IsA("Model") then
		anchor = anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart")
	end
	if not (anchor and anchor:IsA("BasePart")) then
		anchor = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart")
	end
	if not anchor then
		warn("[ForgeService] No suitable anchor found on plot:", plot.Name)
		return nil
	end

	local m = tpl:Clone()
	m.Name = "ElementalForge"
	m.Parent = plot
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			-- optional: keep groups tidy (doesn't affect snapping)
			-- d.CollisionGroup = "ArenaProps"
		end
	end

	local yaw = select(2, anchor.CFrame:ToOrientation())

	-- Start roughly at anchor XZ (no +50), keep yaw
	m:PivotTo(CFrame.new(anchor.Position) * CFrame.Angles(0, yaw, 0))

	-- Snap to ground using the anchor position
	snapForgeToGround(plot, m, anchor.Position)

	-- Optional: a second settle pass (helps if parts stream/assemble a frame late)
	task.delay(0.05, function()
		if m and m.Parent then
			snapForgeToGround(plot, m, anchor.Position)
		end
	end)

	plot:SetAttribute("ForgeUnlocked", true)
	ShrineByPlot[plot] = m
	return m
end

function Forge:SpawnShrine(plot)
	if ShrineByPlot[plot] then return ShrineByPlot[plot] end
	local m, base, orb, pp = mkShrineModel()
	local anchor = findAnchorInPlot(plot); if not anchor then return end

	local baseCf = anchor.CFrame * CFrame.new(0, 0.75, 0)
	base.CFrame = baseCf
	orb.CFrame  = baseCf * CFrame.new(0, 2.0, 0)

	-- fade in with portal
	base.Transparency, orb.Transparency = 1, 1
	m.Parent = plot
	portalFx(plot, baseCf, "appear")
	TweenService:Create(base, TweenInfo.new(0.6), {Transparency=0}):Play()
	TweenService:Create(orb,  TweenInfo.new(0.6), {Transparency=0.25}):Play()

	local uid = plot:GetAttribute("OwnerUserId")
	pp.Triggered:Connect(function(plr)
		if uid and plr.UserId ~= uid then return end
		RE_Open:FireClient(plr, plot)
	end)

	ShrineByPlot[plot] = m
	return m
end

function Forge:DespawnShrine(plot)
	-- If the new forge is present, DO NOT destroy it.
	local ef = plot:FindFirstChild("ElementalForge")
	if ef then
		ShrineByPlot[plot] = ef
		return
	end

	local m = ShrineByPlot[plot]
	if not m then return end
	local base = m:FindFirstChild("Base")
	if base then portalFx(plot, base.CFrame, "vanish") end
	m:Destroy()
	ShrineByPlot[plot] = nil

	local plr = ownerPlayer(plot)
	if plr then
		RE_HUD:FireClient(plr, nil)
		RE_Close:FireClient(plr, plot)
	end
end

function Forge:Reset(plr, plot)
	Run[plr] = nil

	if plot then
		plot:SetAttribute("CoreId", nil)
		plot:SetAttribute("CoreTier", 0)
		plot:SetAttribute("CoreName", nil)

		-- optional: clear blessing display
		plot:SetAttribute("BlessingElem", nil)
	end

	if plr then
		RE_HUD:FireClient(plr, nil)
		RE_Close:FireClient(plr, plot)
	end
end

-- ===== purchases =====
function Forge:Buy(plr, _waveFromClient, choice)
	if type(choice) ~= "table" then return false, "bad_choice" end
	local plot = choice.plot
	if typeof(plot) ~= "Instance" or not plot.Parent then return false, "bad_plot" end
	if (plot:GetAttribute("OwnerUserId") or 0) ~= plr.UserId then return false, "not_owner" end

	-- ensure forge presence
	local ef = plot:FindFirstChild("ElementalForge")
	if ef then ShrineByPlot[plot] = ShrineByPlot[plot] or ef end
	if not ShrineByPlot[plot] then return false, "no_shrine" end

	local waveNum = tonumber(plot:GetAttribute("CurrentWave")) or 1
	local offers = self:Offers(plr, waveNum) -- uses cached entries
	local run = self:GetRun(plr)

	-- REROLL
	if choice.type == "REROLL" then
		local cost = offers.reroll and offers.reroll.cost or REROLL_BASE
		local free = offers.reroll and offers.reroll.free

		if not free and getFlux(plr) < cost then return false, "poor" end

		-- consume voucher first if present
		if free and plr:GetAttribute("RerollVoucher") == true then
			plr:SetAttribute("RerollVoucher", false)
		elseif free and run.vipFreeLeft then
			run.vipFreeLeft = false
		else
			if not spendFlux(plr, cost) then return false, "poor" end
		end

		run.rerolls += 1
		rerollTarget(self, plr, plot, waveNum)
		return true, { util = "REROLL" }
	end

	-- CORE buy
	if choice.type == "CORE" then
		local def
		for _,c in ipairs(CORE_POOL) do
			if c.id == run.core.id then def = c; break end
		end
		def = def or CORE_POOL[1]

		if run.core.tier >= 3 then return false, "max" end
		local nextTier = math.clamp(run.core.tier + 1, 1, 3)
		local nextPrice = (nextTier == 1 and def.t1) or (nextTier == 2 and def.t2) or def.t3

		if getFlux(plr) < nextPrice then return false, "poor" end
		if not spendFlux(plr, nextPrice) then return false, "poor" end

		run.core = { id = run.core.id, name = def.name, tier = math.min(run.core.tier + 1, 3) }
		plot:SetAttribute("CoreId",   run.core.id)
		plot:SetAttribute("CoreTier", run.core.tier)
		plot:SetAttribute("CoreName", run.core.name)
		RE_HUD:FireClient(plr, { id = run.core.id, tier = run.core.tier, name = run.core.name })
		return true, { core = run.core }
	end

	-- UTIL buy
	if choice.type == "UTIL" then
		local util = offers.util
		if not util then return false, "no_util" end

		local segNow = segIdFromWave(waveNum)

		if util.id == "RECOVER" then
			local hero = plot:FindFirstChild("Hero", true)
			local hum  = hero and hero:FindFirstChildOfClass("Humanoid")
			if not hum then return false, "no_hero" end
			if hum.Health >= hum.MaxHealth then return false, "full" end
			if getFlux(plr) < util.price then return false, "poor" end
			if not spendFlux(plr, util.price) then return false, "poor" end

			local add = math.floor(hum.MaxHealth * 0.60 + 0.5)
			hum.Health = math.min(hum.MaxHealth, hum.Health + add)
			return true, { util = "RECOVER" }

		elseif util.id == "AEGIS" then
			local hero = plot:FindFirstChild("Hero", true)
			if not hero then return false, "no_hero" end

			local aegisSeg = tonumber(plot:GetAttribute("Util_AegisSeg")) or -999
			if aegisSeg == segNow then return false, "max" end
			if getFlux(plr) < util.price then return false, "poor" end
			if not spendFlux(plr, util.price) then return false, "poor" end

			grantAegisShield(hero, 0.20)
			plot:SetAttribute("Util_AegisSeg", segNow)
			plot:SetAttribute("UtilExpiresSegId", segNow)
			return true, { util = "AEGIS" }

		elseif util.id == "OVERCHARGE" then
			local activePct = tonumber(plot:GetAttribute("Util_OverchargePct")) or 0
			local segSet    = plot:GetAttribute("UtilExpiresSegId")
			if activePct > 0 and segSet == segNow then return false, "max" end
			if getFlux(plr) < util.price then return false, "poor" end
			if not spendFlux(plr, util.price) then return false, "poor" end

			plot:SetAttribute("Util_OverchargePct", 20)
			plot:SetAttribute("UtilExpiresSegId", segNow)
			return true, { util = "OVERCHARGE" }

		elseif util.id == "SECOND_WIND" then
			local swLeft = tonumber(plot:GetAttribute("Util_SecondWindLeft")) or 0
			local segSet = plot:GetAttribute("UtilExpiresSegId")
			if swLeft > 0 and segSet == segNow then return false, "max" end
			if getFlux(plr) < util.price then return false, "poor" end
			if not spendFlux(plr, util.price) then return false, "poor" end

			plot:SetAttribute("Util_SecondWindLeft", 1)
			plot:SetAttribute("UtilExpiresSegId", segNow)
			return true, { util = "SECOND_WIND" }
		end

		return false, "bad_util"
	end

	-- BLESS micro-card
	if choice.type == "BLESS" then
		local bless = offers.bless
		if not bless then return false, "bad_choice" end
		if getFlux(plr) < bless.price then return false, "poor" end
		if not spendFlux(plr, bless.price) then return false, "poor" end

		plot:SetAttribute("BlessingElem", bless.elem)
		plot:SetAttribute("BlessingExpiresSegId", run.segId)
		return true, { bless = bless.elem }
	end

	return false, "bad_choice"
end

return Forge
