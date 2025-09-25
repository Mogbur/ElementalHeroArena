-- ServerScriptService/Modules/ForgeService.lua
local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")

local Forge = {}
local Run   = setmetatable({}, {__mode="k"})   -- per-player run: { core={id,name,tier}, rerolls=int }
local ShrineByPlot = {}                        -- plot -> Model (shrine)

local ServerStorage = game:GetService("ServerStorage")
local Templates = ServerStorage:WaitForChild("Templates")

local function ensureRE(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent", Remotes); r.Name = name end
	return r
end

local RE_Open  = ensureRE("OpenForgeUI")
local RE_HUD   = ensureRE("ForgeHUD")
local RE_Close = ensureRE("CloseForgeUI") -- optional

-- ====== simple tuning (Zone1 base; scale later) ======
local CORE_POOL = {
    {id="ATK", name="+8% Attack", pct=8, t1=80,  t2=120, t3=180},
    {id="HP",  name="+6% Max HP", pct=6, t1=80,  t2=120, t3=180},
    {id="HST", name="+6% Haste",  pct=6, t1=80,  t2=120, t3=180},
}
local UTIL_POOL = {
    {id="RECOVER", name="Recover to 60% HP", price=120},
    {id="REROLL",  name="Reroll offers",     price=40, scaler=20},
}

local function moneyOf(plr)
    local ls = plr:FindFirstChild("leaderstats")
    return ls and ls:FindFirstChild("Money")
end

function Forge:GetRun(plr)
    Run[plr] = Run[plr] or { core=nil, rerolls=0 }
    return Run[plr]
end

-- Returns vertical offset from model pivot to its true bottom face
local function pivotToBottomOffset(model: Model)
	local pivotY = model:GetPivot().Position.Y
	local bottom: BasePart? = model:FindFirstChild("BottomPlate", true)
	if bottom and bottom:IsA("BasePart") then
		local bottomY = bottom.Position.Y - (bottom.Size.Y * 0.5)
		return pivotY - bottomY
	end
	-- fallback: bounding box
	local cf, size = model:GetBoundingBox()
	local bottomY = cf.Position.Y - (size.Y * 0.5)
	return pivotY - bottomY
end

function Forge:Offers(plr, wave)
    local run = self:GetRun(plr)

    -- start at tier 0 until first purchase
    run.core = run.core or { id = CORE_POOL[1].id, tier = 0, name = CORE_POOL[1].name }

    -- lookup the core def
    local def; for _,c in ipairs(CORE_POOL) do if c.id == run.core.id then def = c break end end
    if not def then def = CORE_POOL[1] end

    -- price is for the NEXT tier (1..3)
    local nextTier = math.clamp(run.core.tier + 1, 1, 3)
    local price = (nextTier == 1 and def.t1) or (nextTier == 2 and def.t2) or def.t3

    local coreOffer = {
        id    = run.core.id,
        name  = def.name,
        tier  = run.core.tier,  -- current (0..3)
        pct   = def.pct,        -- % per tier (client uses for now→next)
        price = price,          -- price for next tier
    }

    -- util caching (unchanged)
    if not run.offers or run.offersWave ~= wave then
        local util = table.clone(UTIL_POOL[math.random(1, #UTIL_POOL)])
        if util.id == "REROLL" then
            util.price += (run.rerolls * (util.scaler or 0))
        end
        run.offers     = { core = coreOffer, util = util }
        run.offersWave = wave
    else
        local util = run.offers.util
        if util and util.id == "REROLL" then
            util.price = (UTIL_POOL[2].price + (run.rerolls * (UTIL_POOL[2].scaler or 0)))
        end
        run.offers.core = coreOffer
    end

    return { core = table.clone(run.offers.core), util = table.clone(run.offers.util) }
end

local function ownerPlayer(plot)
    local uid = plot:GetAttribute("OwnerUserId")
    if not uid then return nil end
    return Players:GetPlayerByUserId(uid)
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
    else -- vanish: pulse then collapse
        TweenService:Create(ring, ti1, {Size=Vector3.new(10,0.2,10), Transparency=0.15}):Play()
        task.delay(1.2, function()
            TweenService:Create(ring, ti2, {Size=Vector3.new(0.2,0.2,0.2), Transparency=1}):Play()
            game:GetService("Debris"):AddItem(fx, 1.1)
        end)
    end
end

local function findAnchorInPlot(plot)
    local anchor = plot:FindFirstChild("ArenaCenter", true)
                 or plot:FindFirstChild("03_HeroAnchor",   true)
                 or plot:FindFirstChild("Arena",           true)
    if anchor and anchor:IsA("Model") then
        anchor = anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart")
    end
    return anchor
end

local function snapForgeToGround(m: Model)
	if not m or not m.Parent then return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { m }  -- ignore only the forge, not the whole plot

	local start = m:GetPivot().Position + Vector3.new(0, 200, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -1200, 0), rp)
	if not hit then return end

	local off = pivotToBottomOffset(m)
	local pv  = m:GetPivot()
	-- small fudge to avoid z-fighting on studs
	local targetY = hit.Position.Y + off + 0.05
	m:PivotTo(CFrame.new(pv.X, targetY, pv.Z) * CFrame.Angles(pv:ToOrientation()))
end

function Forge:SpawnElementalForge(plot: Model)
	-- already present?
	local existing = plot:FindFirstChild("ElementalForge")
	if existing then
		ShrineByPlot[plot] = existing
		return existing
	end

	-- template
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

	-- clone + parent first so bbox is valid
	local m = tpl:Clone()
	m.Name = "ElementalForge"
	m.Parent = plot

	-- place above the anchor (so we don't intersect), keep arena yaw,
	-- then snap perfectly to ground below
	local yaw = select(2, anchor.CFrame:ToOrientation())
	m:PivotTo(CFrame.new(anchor.Position + Vector3.new(0, 50, 0)) * CFrame.Angles(0, yaw, 0))
	snapForgeToGround(m)

    m.Parent = plot
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
    -- If the new forge is present, DO NOT destroy it (VFX handles hide).
    local ef = plot:FindFirstChild("ElementalForge")
    if ef then
        -- keep ShrineByPlot in sync but don’t delete the forge
        ShrineByPlot[plot] = ef
        return
    end

    -- legacy cleanup for the old shrine
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
	-- forget per-run state
	Run[plr] = nil

	-- clear plot mirrors used by balance/UI (if you set them)
	if plot then
		plot:SetAttribute("CoreId", nil)
		plot:SetAttribute("CoreTier", 0)
		plot:SetAttribute("CoreName", nil)
	end

	-- clear HUD / close UI just in case
	if plr then
		RE_HUD:FireClient(plr, nil)
		RE_Close:FireClient(plr, plot)
	end
end

-- ===== purchases =====
function Forge:Buy(plr, _waveFromClient, choice)
	-- Basic sanity
	if type(choice) ~= "table" or (choice.type ~= "CORE" and choice.type ~= "UTIL") then
		return false, "bad_choice"
	end

	-- Validate plot ownership + shrine presence (prevents remote spam)
	local plot = choice.plot
	if typeof(plot) ~= "Instance" or not plot.Parent then return false, "bad_plot" end
	if (plot:GetAttribute("OwnerUserId") or 0) ~= plr.UserId then return false, "not_owner" end
	-- Self-heal the link to the spawned forge/shrine, then verify
    local ef = plot:FindFirstChild("ElementalForge")
    if ef then
        ShrineByPlot[plot] = ShrineByPlot[plot] or ef
    end
    if not ShrineByPlot[plot] then
        return false, "no_shrine"
    end

	-- Money
	local money = moneyOf(plr)
	if not money then return false, "no_money" end

	-- Use the **cached** offers for consistency with the client UI
	local wave = plot:GetAttribute("CurrentWave") or 1
	local offers = self:Offers(plr, wave)  -- will reuse cached run.offers
	local run    = self:GetRun(plr)

	if choice.type == "CORE" then
		-- compute next tier & price from defs (supports tier 0 start)
		local runCore = (self:GetRun(plr).core) or { id = offers.core.id, name = offers.core.name, tier = 0 }
		local def; for _,c in ipairs(CORE_POOL) do if c.id == runCore.id then def = c break end end
		if not def then def = CORE_POOL[1] end

		-- **ADD THIS BLOCK**: block purchases at max
		if runCore.tier >= 3 then
			return false, "max"
		end

		local nextTier  = math.clamp(runCore.tier + 1, 1, 3)
		local nextPrice = (nextTier == 1 and def.t1) or (nextTier == 2 and def.t2) or def.t3
		if money.Value < nextPrice then return false, "poor" end
		money.Value -= nextPrice

		-- apply upgrade
		run.core = { id = runCore.id, name = runCore.name, tier = math.min(runCore.tier + 1, 3) }

		plot:SetAttribute("CoreId",   run.core.id)
		plot:SetAttribute("CoreTier", run.core.tier)
		plot:SetAttribute("CoreName", run.core.name)

		RE_HUD:FireClient(plr, { id = run.core.id, tier = run.core.tier, name = run.core.name })
		return true, { core = run.core }

	elseif choice.type == "UTIL" then
		local util = offers.util
		if not util then return false, "no_util" end
		if money.Value < util.price then return false, "poor" end
		money.Value -= util.price

		if util.id == "REROLL" then
			run.rerolls += 1
			-- force a fresh util next Offers() call (same wave is fine)
			run.offers = nil
			return true, { util = "REROLL" }

		elseif util.id == "RECOVER" then
			-- heal hero on this plot up to 60%
			local hero = plot:FindFirstChild("Hero", true)
			local hum  = hero and hero:FindFirstChildOfClass("Humanoid")
			if hum then
				local target = math.floor(hum.MaxHealth * 0.60 + 0.5)
				if hum.Health < target then hum.Health = target end
			end
			return true, { util = "RECOVER" }
		end

		return false, "bad_util"
	end
end

return Forge
