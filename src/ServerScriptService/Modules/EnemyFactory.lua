-- ServerScriptService/RojoServer/Modules/EnemyFactory.lua
local RS  = game:GetService("ReplicatedStorage")
local SS  = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")

local Mods       = RS:WaitForChild("Modules")
local EnemyMods  = Mods:WaitForChild("Enemy")

-- shared data
local Common   = require(EnemyMods:WaitForChild("EnemyCommon"))
local Catalog  = require(EnemyMods:WaitForChild("EnemyCatalog"))

-- where legacy brains / archetypes live (if you still use them)
local BrainRoot   = EnemyMods:FindFirstChild("Brains") or EnemyMods:FindFirstChild("AI")
local Archetypes  = EnemyMods:FindFirstChild("Archetypes")

-- Rojo server-side brains/tagger (unchanged)
local EnemyBrain do
	local ok, mod = pcall(function()
		return require(SSS:WaitForChild("RojoServer"):WaitForChild("Modules"):WaitForChild("EnemyBrain"))
	end)
	EnemyBrain = ok and mod or nil
end

local EnemyTag do
	local ok, mod = pcall(function()
		return require(SSS:WaitForChild("RojoServer"):WaitForChild("Modules"):WaitForChild("EnemyTag"))
	end)
	EnemyTag = ok and mod or nil
end

local EnemyFactory = {}

local function splitPath(p) local t={}; for s in string.gmatch(p,"[^/]+") do t[#t+1]=s end; return t end
local function resolveTemplate(pathStr)
	if type(pathStr) ~= "string" then return nil end
	local parts = splitPath(pathStr); if #parts < 2 then return nil end
	local root = (parts[1]=="ServerStorage" and SS)
		or (parts[1]=="ReplicatedStorage" and RS)
		or (parts[1]=="Workspace" or parts[1]=="workspace") and workspace
		or game:GetService(parts[1])
	local node = root
	for i=2,#parts do if not node then return nil end; node = node:FindFirstChild(parts[i]) end
	return node
end

-- opts: { elem, rank, attributes, wave:number?, ctx:any? }
function EnemyFactory.spawn(kind, ownerUserId, lookCF, groundY, parentFolder, opts)
	opts = opts or {}
	local def  = Catalog.get(kind)         -- <-- uses your rich shape
	local wave = tonumber(opts.wave) or 1

	local template = resolveTemplate(def.templatePath) or SS:FindFirstChild("EnemyTemplate")
	assert(template, "[EnemyFactory] Missing EnemyTemplate")

	-- clone + parent first
	local m = template:Clone()
	m.Name = ("Enemy_%s"):format(kind or "Basic")
	m:SetAttribute("Kind", kind or "Basic")
	if opts.elem  then m:SetAttribute("Element", opts.elem) end
	if def.rank   then m:SetAttribute("Rank", def.rank) end
	if opts.rank  then m:SetAttribute("Rank", opts.rank) end
	m.Parent = parentFolder or workspace

	-- core tagging/ownership
	Common.setOwner(m, ownerUserId)
	if type(opts.attributes) == "table" then
		for k,v in pairs(opts.attributes) do m:SetAttribute(k,v) end
	end

	-- place + sanitize + color + flush
	m:PivotTo(lookCF)
	Common.sanitize(m, { hipHeightOverride = def.hipHeightOverride or 0.1 })
	Common.colorByElement(m, opts.elem)
	Common.flushToGroundByRoot(m, groundY, 0.01)
	Common.ownToServer(m)
	Common.tag(m) -- keep your original tag call

	-- (optional) also run the tiny Rojo tag module (idempotent)
	if EnemyTag and EnemyTag.attach then
		pcall(EnemyTag.attach, m)
		-- note: EnemyTag.detach available if you need it later
	end

	-- stat scaling (single source of truth)
	local base, growth = def.base or {}, def.growth or {}
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		local hp0  = tonumber(base.hp) or hum.MaxHealth
		local hmul = (tonumber(growth.hp) or 1.0) ^ (wave-1)
		hum.MaxHealth = math.max(1, math.floor(hp0 * hmul))
		hum.Health    = hum.MaxHealth
	end
	local dmg0 = tonumber(base.dmg) or (tonumber(m:GetAttribute("BaseDamage")) or 10)
	local dmul = (tonumber(growth.dmg) or 1.0) ^ (wave-1)
	m:SetAttribute("BaseDamage", math.max(1, math.floor(dmg0 * dmul)))

	-- defensive: HRP is collider
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CanCollide = true; hrp.Massless = false end

	-- ============================
	-- Attach brain (prefer Rojo module; fall back to old system)
	-- ============================
	local stopFn

	-- Prefer the new Rojo EnemyBrain module
	if EnemyBrain and type(EnemyBrain.attach) == "function" then
		local ctx = {
			owner = ownerUserId,
			elem  = opts.elem,
			wave  = wave,
			def   = def,
			base  = base,
			growth = growth,
			extra = opts.ctx, -- pass-through for callers
		}
		local ok = pcall(function() EnemyBrain.attach(m, ctx) end)
		if ok then
			m:SetAttribute("BrainAttached", true)
			stopFn = function()
				pcall(function() EnemyBrain.detach(m) end)
			end
		end
	end

	-- Fallback: legacy per-archetype brains in ReplicatedStorage.Enemy.Brains/AI
	if not stopFn and BrainRoot and BrainRoot:IsA("Folder") then
		local arche    = (def.archetype or "melee"):lower()
		local brainName = (arche=="melee" and "Melee")
			or (arche=="runner" and "Runner")
			or (arche=="ranged" and "Ranged") or "Melee"

		local brainMod = BrainRoot:FindFirstChild(brainName) or EnemyFolder:FindFirstChild(brainName)
		if brainMod then
			local ok, brain = pcall(require, brainMod)
			if ok and type(brain) == "table" and type(brain.start) == "function" then
				m:SetAttribute("BrainAttached", true)
				stopFn = brain.start(m, {
					WalkSpeed   = tonumber(base.speed),
					AttackRange = tonumber(base.range),
					Cooldown    = tonumber(base.cd),
					KeepMin = (arche=="ranged" and math.max(6, (tonumber(base.range) or 12) - 3)) or nil,
					KeepMax = (arche=="ranged" and (tonumber(base.range) or 12)) or nil,
					ProjectileSpeed = (arche=="ranged" and def.projectile and tonumber(def.projectile.speed)) or nil,
					ProjectileLife  = (arche=="ranged" and def.projectile and tonumber(def.projectile.life))  or nil,
				})
			end
		end
	end

	-- Fallback: adapter module (unchanged)
	if not stopFn and Archetypes then
		local ok, A = pcall(require, Archetypes)
		if ok and type(A.attach) == "function" then
			m:SetAttribute("BrainAttached", true)
			stopFn = A.attach(m, def)
		end
	end

	-- Stop on death if a stopFn was provided by legacy systems
	if hum and stopFn then
		hum.Died:Connect(function() pcall(stopFn) end)
	end

	return m
end

return EnemyFactory
