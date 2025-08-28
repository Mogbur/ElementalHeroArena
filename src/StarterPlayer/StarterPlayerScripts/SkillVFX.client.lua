-- SkillVFX.client.lua (sleeker)
-- Beams / quake ring / water bubble + floating numbers.
-- Safe: runs even if some Remotes or assets are missing.

local RS         = game:GetService("ReplicatedStorage")
local Tween      = game:GetService("TweenService")
local Run        = game:GetService("RunService")
local Debris     = game:GetService("Debris")
local Camera     = workspace.CurrentCamera

-- Optional Remotes (don’t hard-wait)
local Remotes = RS:FindFirstChild("Remotes")
local RE_VFX  = Remotes and Remotes:FindFirstChild("SkillVFX")
local RE_DMG  = Remotes and Remotes:FindFirstChild("DamageNumbers")

-- Track AquaBarrier visuals per-hero so we can clean them
-- [Model] = { highlight=Highlight?, bubble=BasePart?, conn=RBXScriptConnection?, shieldBar=BillboardGui?, barConn=RBXScriptConnection? }
local aquaFX = {}

local function cleanupAquaFX(model)
	local fx = aquaFX[model]
	if not fx then return end
	if fx.conn then fx.conn:Disconnect() end
	if fx.barConn then fx.barConn:Disconnect() end
	if fx.highlight then fx.highlight:Destroy() end
	if fx.bubble and fx.bubble.Parent then fx.bubble:Destroy() end
	if fx.shieldBar and fx.shieldBar.Parent then fx.shieldBar:Destroy() end
	aquaFX[model] = nil
end

-- ===================== SFX helpers =====================

local SFX = {
	default     = 911882310,        -- soft whoosh fallback
	firebolt    = 125088538822680,  -- replace with your actual firebolt sfx
	aquabarrier = 138495465899607,  -- replace with your shield/water sfx (placeholder)
	quakepulse  = 9118614058,       -- replace with your boom/earth sfx (placeholder)
	hit         = nil,              -- impact pop (optional)
}

local function normalizeId(id)
	if not id then return nil end
	if typeof(id) == "number" then id = tostring(id) end
	if not string.find(id, "rbxassetid://", 1, true) then
		id = "rbxassetid://" .. id
	end
	return id
end

-- 3D SFX at a world position
local function playSfx(kind, pos)
	local id = normalizeId(SFX[kind] or SFX.default); if not id then return end
	pos = pos or Vector3.zero

	local p = Instance.new("Part")
	p.Name = "SFX_" .. tostring(kind)
	p.Anchored, p.CanCollide, p.Transparency = true, false, 1
	p.Size = Vector3.new(0.2,0.2,0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace

	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.9
	s.RollOffMode = Enum.RollOffMode.Inverse
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 70
	s.EmitterSize = 8
	s.Parent = p

	s:Play()
	s.Ended:Once(function() p:Destroy() end)
	Debris:AddItem(p, 5)
end

-- micro camera jiggle (quake)
local function cameraJiggle(strength, dur)
	if not Camera then return end
	local t0 = os.clock()
	local conn; conn = Run.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= dur then conn:Disconnect(); return end
		local k = 1 - (t/dur)
		local dx = (math.noise(13.1*t) - 0.5) * strength * k
		local dy = (math.noise(97.7*t) - 0.5) * strength * k
		Camera.CFrame = Camera.CFrame * CFrame.new(dx, dy, 0)
	end)
end

-- ===================== numbers =====================

local function popNumber(amount, pos, color, kind)
	if not (amount and pos) then return end

	-- BIG for outgoing skill hits; small for incoming damage
	local isOutgoing = (kind == "skill")
	local guiSize    = isOutgoing and UDim2.fromOffset(260, 110) or UDim2.fromOffset(140, 60)
	local rise       = isOutgoing and 2.0 or 1.5

	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.Transparency = true, false, 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(pos + Vector3.new(0, isOutgoing and 2.0 or 1.0, 0))
	part.Parent = workspace

	local bg = Instance.new("BillboardGui")
	bg.Size = guiSize
	bg.AlwaysOnTop = true
	bg.LightInfluence = 0
	bg.Parent = part

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.Text = tostring(amount)
	text.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	text.TextStrokeColor3 = Color3.new(0,0,0)
	text.TextStrokeTransparency = 0.2
	text.Parent = bg

	local up   = Tween:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = part.CFrame + Vector3.new(0, rise, 0) })
	local fade = Tween:Create(text, TweenInfo.new(0.25),
		{ TextTransparency = 1, TextStrokeTransparency = 1 })

	up:Play()
	task.delay(0.4, function() fade:Play() end)
	task.delay(0.8, function() if part then part:Destroy() end end)
end

if RE_DMG then
	RE_DMG.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		local kind = payload.kind
		if kind == "heal" then
			popNumber(payload.amount or "+", payload.pos, Color3.fromRGB(95, 220, 110), "skill")
			return
		elseif kind == "shield" then
			popNumber(payload.amount or "Shield", payload.pos, Color3.fromRGB(120, 220, 255), "skill")
			return
		end
		-- default: damage numbers
		popNumber(payload.amount, payload.pos, payload.color, payload.kind)
	end)
end

-- ===================== firebolt (beam + tiny impact puff) =====================

local function impactBurst(pos, color)
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.Transparency = true, false, 1
	part.Size = Vector3.new(0.2,0.2,0.2)
	part.CFrame = CFrame.new(pos)
	part.Parent = workspace

	local a = Instance.new("Attachment", part)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxassetid://2418761467"
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.22, 0.34)
	dust.Speed = NumberRange.new(7, 12)
	dust.SpreadAngle = Vector2.new(15, 15)
	dust.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0.25),
	}
	dust.Color = ColorSequence.new(color or Color3.fromRGB(255,210,120))
	dust.Parent = a
	dust:Emit(14)
	Debris:AddItem(part, 0.6)
end

local BEAM_W0, BEAM_W1   = 0.9, 1.5
local BEAM_TIME          = 0.20
local BEAM_TEX           = "rbxassetid://446111271"
local BEAM_TEX_SPEED     = 2
local BEAM_COLOR1        = Color3.fromRGB(255, 170, 90)
local BEAM_COLOR2        = Color3.fromRGB(255,  70, 40)

local function fireboltBeam(from, to)
	local container = Instance.new("Part")
	container.Anchored, container.CanCollide, container.Transparency = true, false, 1
	container.Size = Vector3.new(0.1, 0.1, 0.1)
	container.CFrame = CFrame.new((from + to) * 0.5)
	container.Parent = workspace

	local a0 = Instance.new("Attachment", container)
	local a1 = Instance.new("Attachment", container)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = BEAM_W0
	beam.Width1 = BEAM_W1
	beam.LightEmission = 1
	beam.Brightness = 3
	beam.LightInfluence = 0.4
	beam.Segments = 10
	beam.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.25),
	}
	beam.Color = ColorSequence.new(BEAM_COLOR1, BEAM_COLOR2)
	beam.Texture = BEAM_TEX
	beam.TextureSpeed = BEAM_TEX_SPEED
	beam.TextureLength = 1
	beam.FaceCamera = true
	beam.Parent = container

	a0.WorldPosition = from
	a1.WorldPosition = from

	local t = Tween:Create(a1, TweenInfo.new(BEAM_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ WorldPosition = to })
	t:Play()
	t.Completed:Once(function()
		impactBurst(to, Color3.fromRGB(255,190,120))
		playSfx("hit", to)
		task.delay(0.05, function() if container then container:Destroy() end end)
	end)
end

-- ===================== AquaBarrier (FOLLOWING water bubble) =====================

-- smaller bubble (about 2× smaller than before)
local BUBBLE_RADIUS = 7.5  -- studs (diameter ~15)

local function findNearestHeroRoot(pos, searchR)
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, searchR or 20)) do
		if part:IsA("BasePart") and part.Name == "HumanoidRootPart" then
			local mdl = part.Parent
			if mdl and mdl:IsA("Model") and mdl.Name == "Hero" then
				return part
			end
		end
	end
	return nil
end

local function aquaBubble(pos, dur)
	local root = findNearestHeroRoot(pos, 25)

	local bubble = Instance.new("Part")
	bubble.Name = "AquaBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.Glass
	bubble.Color = Color3.fromRGB(140, 200, 255)
	bubble.Transparency = 0.5
	bubble.Reflectance = 0
	bubble.CanCollide = false
	bubble.Anchored = true
	bubble.Size = Vector3.new(1,1,1)
	bubble.CFrame = CFrame.new(pos)
	bubble.Parent = workspace

	-- soft magical light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 200, 255)
	light.Brightness = 0.7
	light.Range = BUBBLE_RADIUS * 2
	light.Parent = bubble

	-- gentle pulse
	local growTo = BUBBLE_RADIUS * 2
	Tween:Create(bubble, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(growTo, growTo, growTo) }):Play()

	-- follow the hero if we found the root
	local t0 = os.clock()
	local conn; conn = Run.Heartbeat:Connect(function()
		if not bubble.Parent then if conn then conn:Disconnect() end return end
		if root and root.Parent then
			bubble.CFrame = root.CFrame
		end
		if (os.clock() - t0) >= (dur or 4) then
			-- fade out
			Tween:Create(bubble, TweenInfo.new(0.2), {Transparency = 1}):Play()
			task.delay(0.22, function() if bubble then bubble:Destroy() end end)
			if conn then conn:Disconnect() end
		end
	end)

	playSfx("aquabarrier", pos)
	return bubble
end

-- Simple blue SHIELD BAR that mirrors ShieldHP while the bubble is up.
local function attachShieldBar(model, duration)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ShieldBar"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(120, 12)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.Parent = hrp

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1,1)
	bg.BackgroundColor3 = Color3.fromRGB(20,25,35)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = gui
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)

	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0,0)
	fill.Position = UDim2.fromScale(0,0)
	fill.Size = UDim2.fromScale(0,1)
	fill.BackgroundColor3 = Color3.fromRGB(90,180,255)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

	local maxShield = 0
	local function refresh()
		local cur = math.max(0, model:GetAttribute("ShieldHP") or 0)
		if cur > maxShield then maxShield = cur end
		local frac = (maxShield > 0) and (cur / maxShield) or 0
		fill.Size = UDim2.fromScale(frac, 1)
		if cur <= 0 then
			if gui.Parent then gui:Destroy() end
		end
	end

	refresh()
	local conn = model:GetAttributeChangedSignal("ShieldHP"):Connect(refresh)
	task.delay(duration or 6, function()
		if conn then conn:Disconnect() end
		if gui and gui.Parent then gui:Destroy() end
	end)

	return gui, conn
end

-- ===================== QuakePulse (neon ring + jiggle) =====================

local function quakeRing(pos, radius)
	radius = radius or 22

	local ring = Instance.new("Part")
	ring.Name = "QuakeRing"
	ring.Anchored, ring.CanCollide = true, false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 210, 120)
	ring.Transparency = 0.15
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(2, 0.25, 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Parent = workspace

	local tween = Tween:Create(ring, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 2, 0.25, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, 0.35)

	cameraJiggle(0.08, 0.15)
	playSfx("quakepulse", pos)
end

-- ===================== wire-up =====================

if RE_VFX then
	RE_VFX.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end

		-- FIREBOLT (beam)
		if payload.kind == "firebolt" and payload.from and payload.to then
			fireboltBeam(payload.from, payload.to)
			playSfx("firebolt", payload.from)
			return
		end

		-- AQUABARRIER (spawn + follow bubble + highlight, auto-clean)
		if payload.kind == "aquabarrier" then
			local model    = payload.who
			local duration = tonumber(payload.duration) or 6
			local pos      = payload.pos
			if not (model and model.Parent) then return end

			-- kill any previous FX for this model first
			cleanupAquaFX(model)
			aquaFX[model] = {}

			-- 1) Highlight that hugs the model (+ subtle outline pulse)
			do
				local h = Instance.new("Highlight")
				h.FillColor = Color3.fromRGB(90, 180, 255)
				h.FillTransparency = 0.6
				h.OutlineTransparency = 0.1
				h.Adornee = model
				h.Parent = model
				aquaFX[model].highlight = h

				-- pulse loop (BUGFIX: keep 'h' in-scope)
				task.spawn(function()
					local t0 = os.clock()
					while h.Parent and (model:GetAttribute("ShieldHP") or 0) > 0 do
						local t = os.clock() - t0
						h.OutlineTransparency = 0.05 + 0.05 * (0.5 + 0.5 * math.sin(t*4))
						task.wait(0.1)
					end
				end)
			end

			-- 2) Glass bubble (follows hero)
			do
				local root = model:FindFirstChild("HumanoidRootPart")
				local bubblePart = aquaBubble(root and root.Position or pos, duration)
				aquaFX[model].bubble = bubblePart
			end

			-- 3) Shield bar (tracks ShieldHP)
			do
				local bar, barConn = attachShieldBar(model, duration)
				aquaFX[model].shieldBar = bar
				aquaFX[model].barConn   = barConn
			end

			-- Cleanup when ShieldHP runs out
			aquaFX[model].conn = model:GetAttributeChangedSignal("ShieldHP"):Connect(function()
				if (model:GetAttribute("ShieldHP") or 0) <= 0 then
					cleanupAquaFX(model)
				end
			end)

			-- Safety timeout (duration)
			task.delay(duration, function()
				cleanupAquaFX(model)
			end)

			return
		end

		-- AQUABARRIER early-kill (server tells us to pop immediately)
		if payload.kind == "aquabarrier_kill" then
			local m = payload.who
			if m then cleanupAquaFX(m) end
			return
		end

		-- QUAKEPULSE (ring + camera jiggle)
		if payload.kind == "quakepulse" and payload.pos then
			quakeRing(payload.pos, payload.radius or 22)
			return
		end
	end)
end
