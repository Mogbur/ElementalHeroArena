-- ServerScriptService/EnemySpawner.lua
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local EnemySpawner = {}

-- Config: names in your map
local PLOTS_CONTAINER    = workspace:FindFirstChild("Plots") or workspace
local PLOT_NAME_PATTERN  = "^BasePlot%d+$"
local PORTAL_ANCHOR      = "05_PortalAnchor"

local ENEMY_TEMPLATE_NAME = "EnemyTemplate" -- Model with Humanoid + a visible Body/Head
local BOSS_HEALTH_MULT    = 2.5
local ELEMENTS = { "Fire", "Water", "Earth" }

local function findPlayersPlot(uid)
	for _, m in ipairs(PLOTS_CONTAINER:GetChildren()) do
		if m:IsA("Model") and m.Name:match(PLOT_NAME_PATTERN) then
			if (m:GetAttribute("OwnerUserId") or 0) == uid then
				return m
			end
		end
	end
end

local function pickElement()
	return ELEMENTS[math.random(1, #ELEMENTS)]
end

-- Spawns one enemy for player. Returns the enemy Model (or nil).
function EnemySpawner.Spawn(plr, waveCfg, isBoss: boolean?)
	local templ = ServerStorage:FindFirstChild(ENEMY_TEMPLATE_NAME)
	if not templ or not templ:IsA("Model") then return nil end

	local plot = findPlayersPlot(plr.UserId)
	if not plot then return nil end
	local portal = plot:FindFirstChild(PORTAL_ANCHOR, true)
	if not portal or not portal:IsA("BasePart") then return nil end

	local m = templ:Clone()
	m.Name = isBoss and ("Boss_W"..waveCfg.index) or ("Enemy_W"..waveCfg.index)
	m:SetAttribute("OwnerUserId", plr.UserId)
	m:SetAttribute("Element", pickElement())
	m:SetAttribute("IsBoss", isBoss and true or false)
	CollectionService:AddTag(m, "Enemy")

	-- Health scaling
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		local baseMax = hum.MaxHealth > 0 and hum.MaxHealth or 100
		local scaled = math.floor(baseMax * waveCfg.healthMul * (isBoss and BOSS_HEALTH_MULT or 1))
		hum.MaxHealth = math.max(1, scaled)
		hum.Health = hum.MaxHealth
	end

	-- Spawn position
	if not m.PrimaryPart then m.PrimaryPart = m:FindFirstChild("HumanoidRootPart") end
	local cf = portal.CFrame * CFrame.new(0, 2.5, -3)
	m:PivotTo(cf)
	m.Parent = workspace

	-- (Optional) your movement AI can read RootUntil attribute on the model

	return m
end

return EnemySpawner
