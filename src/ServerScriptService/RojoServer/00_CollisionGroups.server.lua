-- ServerScriptService/RojoServer/CollisionGroups.server.lua
local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")

-- helpers -------------
local function ensure(name) pcall(function() PhysicsService:RegisterCollisionGroup(name) end) end
local function coll(a,b,tf) pcall(function() PhysicsService:CollisionGroupSetCollidable(a,b,tf) end) end
local function setPartGroup(p, g) if p and p:IsA("BasePart") then p.CollisionGroup = g end end
local function setModelGroup(m, g)
	for _,d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = g end
	end
end

-- groups --------------
for _,g in ipairs({"Player","Hero","Enemy","Effects","ArenaGround","ArenaProps"}) do ensure(g) end
pcall(function() PhysicsService:CollisionGroupSetCollidable("Default","Default",true) end)

-- core rules ----------
coll("Player","Hero",   false)
coll("Player","Enemy",  false)
coll("Player","Effects",false)
coll("Hero","Effects",  false)
coll("Hero","Enemy",    true)
coll("Hero","Hero",     true)
coll("Enemy","Enemy",   true)

-- props & ground ------
-- Props: let players & hero collide, but NOT enemies (prevents enemy pathing snag)
coll("ArenaProps","Player", true)
coll("ArenaProps","Hero",   true)
coll("ArenaProps","Enemy",  false)

-- Ground should collide normally with everyone
for _,g in ipairs({"Player","Hero","Enemy","Effects","ArenaGround"}) do
	coll("ArenaGround", g, true)
end

-- auto-tag player chars
local function onChar(char) setModelGroup(char,"Player") end
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(onChar)
	if plr.Character then onChar(plr.Character) end
end)

-- configure plots (ground, anchor, portal, totem)
local plots = workspace:FindFirstChild("Plots")

local function configurePlot(plot)
	if not plot then return end

	-- ground pieces (add/adjust names to match your map)
	for _,name in ipairs({"Sand","PlotGround","ArenaFloor","HeroSpawn"}) do
		local p = plot:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			setPartGroup(p, "ArenaGround")
			p.CanTouch = false
		end
	end

	-- arena hero spawn anchor
	local anchor = plot:FindFirstChild("07_HeroArenaAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		setPartGroup(anchor, "Effects")
		anchor.CanTouch = false
		-- keep CanCollide = false (as you have it)
	end

	-- portal arches/pillars: mark as ArenaProps
	local portalModel = plot:FindFirstChild("Portal", true)
	if portalModel and portalModel:IsA("Model") then
		setModelGroup(portalModel, "ArenaProps")
		for _,d in ipairs(portalModel:GetDescendants()) do
			if d:IsA("BasePart") then
				-- black hole / VFX spheres should not collide at all
				local n = d.Name:lower()
				if n:find("blackhole") or n:find("fx") then
					d.CanCollide = false
					d.CanTouch   = false
				end
			end
		end
	end

	-- Totem gem acts like an effect (no touches/collisions)
	local totem = plot:FindFirstChild("ArenaTotem", true)
	if totem and totem:IsA("Model") then
		local gem = totem:FindFirstChild("Gem", true)
		if gem and gem:IsA("BasePart") then
			setPartGroup(gem, "Effects")
			gem.CanTouch = false
		end
	end
end

if plots then
	for _,plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") then configurePlot(plot) end
	end
	plots.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") then return end
		if d.Name == "Sand" or d.Name == "PlotGround" or d.Name == "ArenaFloor" or d.Name == "HeroSpawn" then
			setPartGroup(d, "ArenaGround"); d.CanTouch = false
		elseif d.Name == "07_HeroArenaAnchor" then
			setPartGroup(d, "Effects"); d.CanTouch = false
		elseif d.Parent and d.Parent:IsA("Model") and d.Parent.Name == "Portal" then
			setPartGroup(d, "ArenaProps")
		end
	end)
end
