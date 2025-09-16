-- ServerScriptService/RojoServer/CollisionGroups.server.lua
local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- helpers -------------
local function ensure(name)
	-- create only if missing
	if not pcall(function() PhysicsService:GetCollisionGroupId(name) end) then
		PhysicsService:CreateCollisionGroup(name)
	end
end

local function coll(a, b, tf)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(a, b, tf) end)
end

local function setPartGroup(p: BasePart, g: string)
	if p and p:IsA("BasePart") then
		PhysicsService:SetPartCollisionGroup(p, g)
	end
end

local function setModelGroup(m: Instance, g: string)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			PhysicsService:SetPartCollisionGroup(d, g)
		end
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
-- Make Effects not collide with anything (safest default)
for _, g in ipairs({"Player","Hero","Enemy","ArenaGround","ArenaProps","Effects"}) do
	coll("Effects", g, false)
end

-- props & ground ------
-- Props: let players & hero collide, but NOT enemies (prevents enemy pathing snag)
coll("ArenaProps","Player", true)
coll("ArenaProps","Hero",   true)
coll("ArenaProps","Enemy",  false)

-- Ground should collide normally with living things; keep Effects non-colliding.
for _, g in ipairs({"Player","Hero","Enemy","ArenaGround"}) do
	coll("ArenaGround", g, true)
end
-- do NOT include "Effects" here (Effects stays non-colliding)

-- auto-tag player chars
local function setCharGroup(char)
	-- set existing
	setModelGroup(char, "Player")
	-- catch late-added parts
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then setPartGroup(d, "Player") end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(setCharGroup)
	if plr.Character then setCharGroup(plr.Character) end
end)
-- Enemies
for _,e in ipairs(CollectionService:GetTagged("Enemy")) do setModelGroup(e, "Enemy") end
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(inst)
	if inst:IsA("Model") then
		setModelGroup(inst, "Enemy")
		inst.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then setPartGroup(d, "Enemy") end end)
	end
end)

-- Heroes (your AI hero rigs)
for _,h in ipairs(CollectionService:GetTagged("Hero")) do setModelGroup(h, "Hero") end
CollectionService:GetInstanceAddedSignal("Hero"):Connect(function(inst)
	if inst:IsA("Model") then
		setModelGroup(inst, "Hero")
		inst.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then setPartGroup(d, "Hero") end end)
	end
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
task.delay(3, function()
	-- log one hero/enemy part’s group
	local anyEnemy = CollectionService and CollectionService:GetTagged("Enemy")[1]
	local anyHero  = CollectionService and CollectionService:GetTagged("Hero")[1]
	local function grp(part)
		local ok,id = pcall(function() return PhysicsService:GetCollisionGroupName(part.CollisionGroupId) end)
		return ok and id or "?"
	end
	if anyEnemy then
		local pp = anyEnemy:FindFirstChildWhichIsA("BasePart", true)
		if pp then print("[CG] Enemy sample group:", grp(pp)) end
	end
	if anyHero then
		local pp = anyHero:FindFirstChildWhichIsA("BasePart", true)
		if pp then print("[CG] Hero sample group:", grp(pp)) end
	end
end)
