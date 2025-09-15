-- ServerScriptService/Modules/ForgeService.lua
local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")

local Forge = {}
local Run   = setmetatable({}, {__mode="k"})   -- per-player run: { core={id,name,tier}, rerolls=int }
local ShrineByPlot = {}                        -- plot -> Model (shrine)

-- ====== simple tuning (Zone1 base; scale later) ======
local CORE_POOL = {
    {id="ATK", name="+8% Attack", t1=80,  t2=120, t3=180},
    {id="HP",  name="+6% Max HP", t1=80,  t2=120, t3=180},
    {id="HST", name="+6% Haste",  t1=80,  t2=120, t3=180},
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

function Forge:Offers(plr, wave)
    local run = self:GetRun(plr)
    local core = run.core or {id=CORE_POOL[1].id, tier=1, name=CORE_POOL[1].name}
    local def; for _,c in ipairs(CORE_POOL) do if c.id==core.id then def=c; break end end
    local price = (core.tier==1 and def.t1) or (core.tier==2 and def.t2) or def.t3

    local util = table.clone(UTIL_POOL[math.random(1,#UTIL_POOL)])
    if util.id=="REROLL" then util.price += (run.rerolls * (util.scaler or 0)) end

    return { core={id=core.id, tier=core.tier, name=def.name, price=price}, util=util }
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
    local anchor = plot:FindFirstChild("06_BannerAnchor", true)
                 or plot:FindFirstChild("03_HeroAnchor",   true)
                 or plot:FindFirstChild("Arena",           true)
    if anchor and anchor:IsA("Model") then
        anchor = anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart")
    end
    return anchor
end

function Forge:SpawnShrine(plot)
    if ShrineByPlot[plot] then return ShrineByPlot[plot] end
    local m, base, orb, pp = mkShrineModel()
    local anchor = findAnchorInPlot(plot); if not anchor then return end

    local baseCf = anchor.CFrame * CFrame.new(0, 0.75, -6)
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
        Remotes.OpenForgeUI:FireClient(plr, plot)
    end)

    ShrineByPlot[plot] = m
    return m
end

function Forge:DespawnShrine(plot)
    local m = ShrineByPlot[plot]
    if not m then return end
    local base = m:FindFirstChild("Base")
    if base then
        portalFx(plot, base.CFrame, "vanish")
    end
    m:Destroy()
    ShrineByPlot[plot] = nil

    local plr = ownerPlayer(plot)
    if plr then Remotes.ForgeHUD:FireClient(plr, nil) end -- clear HUD chip
end

-- ===== purchases =====
function Forge:Buy(plr, wave, choice)
    local money = moneyOf(plr); if not money then return false,"no_money" end
    local offers = self:Offers(plr, wave)
    local run = self:GetRun(plr)

    if choice.type=="CORE" then
        if money.Value < offers.core.price then return false,"poor" end
        money.Value -= offers.core.price
        run.core = run.core or {id=offers.core.id, tier=1, name=offers.core.name}
        run.core.tier = math.min(run.core.tier + 1, 3)
        local plot = choice.plot
        if typeof(plot)=="Instance" and plot.Parent then
            plot:SetAttribute("CoreId",   run.core.id)
            plot:SetAttribute("CoreTier", run.core.tier)
            plot:SetAttribute("CoreName", run.core.name)
            Remotes.ForgeHUD:FireClient(plr, {id=run.core.id, tier=run.core.tier, name=run.core.name})
        end
        return true, {core=run.core}
    elseif choice.type=="UTIL" then
        if money.Value < offers.util.price then return false,"poor" end
        money.Value -= offers.util.price

        if offers.util.id == "REROLL" then
            run.rerolls += 1

        elseif offers.util.id == "RECOVER" then
            -- heal hero on this plot up to 60%
            local plot = choice.plot
            local hero = plot and plot:FindFirstChild("Hero", true)
            local hum  = hero and hero:FindFirstChildOfClass("Humanoid")
            if hum then
                local target = math.floor(hum.MaxHealth * 0.60 + 0.5)
                if hum.Health < target then hum.Health = target end
            end
        end

        return true, { util = offers.util.id }
    end
    return false,"bad_choice"
end

return Forge
