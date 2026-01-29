local RS = game:GetService("ReplicatedStorage")
-- ---------- SINGLETON (prevents duplicate LocalScripts) ----------
if _G.__COMBATVFX_RUNNING then
	warn("[CombatVFX] duplicate client script; ignoring this copy:", script:GetFullName())
	return
end
print("[CombatVFX] boot:", script:GetFullName())
_G.__COMBATVFX_RUNNING = true
local Tween = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Run = game:GetService("RunService")
local Remotes = RS:WaitForChild("Remotes")
local RE = Remotes:WaitForChild("CombatVFX")

-- === SFX IDs (swap these for the ones you like) ===
local SFX = {
	bow_shot      = "rbxassetid://108298859110126",    -- light twang / whoosh
    sword_swing   = "rbxassetid://5763723309",     -- placeholder whoosh for light sword
	mace_swing    = "rbxassetid://74238153433253",    -- placeholder heavier whoosh/whump
	bow_surge     = "rbxassetid://103529362101351",   -- heavier impact (temporary)
	mace_stun     = "rbxassetid://9113225186",     -- bonk/glonk (replace later)
	block_clang   = "rbxassetid://136623299198321",    -- metal clash/clang
}

local function playAt(id, pos, volume)
	if not id then return end
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.Transparency = 1
	p.Size = Vector3.new(0.2,0.2,0.2); p.CFrame = CFrame.new(pos or Vector3.zero)
	p.Parent = workspace
	local s = Instance.new("Sound")
	s.SoundId = (string.find(id,"rbxassetid://") and id) or ("rbxassetid://"..tostring(id))
	s.Volume = volume or 0.85
	s.RollOffMode = Enum.RollOffMode.Inverse
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 80
	s.EmitterSize = 8
	s.Parent = p
	s:Play()
	s.Ended:Once(function() p:Destroy() end)
end

local function sparkBurst(partOrPos)
    local part
    if typeof(partOrPos) == "Vector3" then
        part = Instance.new("Part")
        part.Anchored = true; part.CanCollide = false; part.Transparency = 1
        part.Size = Vector3.new(0.2,0.2,0.2); part.CFrame = CFrame.new(partOrPos)
        part.Parent = workspace
    else
        part = partOrPos
    end
    local att = Instance.new("Attachment")
    att.Parent = (part:IsA("BasePart") and part) or workspace.Terrain

    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxassetid://258128463" -- sparks
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(0.12, 0.20)
    pe.Speed = NumberRange.new(8, 16)
    pe.SpreadAngle = Vector2.new(35, 35)
    pe.Rotation = NumberRange.new(0, 360)
    pe.Parent = att
    pe:Emit(22)

    Debris:AddItem(att, 0.5)
    if part ~= partOrPos then Debris:AddItem(part, 0.5) end
end

local function quickBeam(from, to)
    local container = Instance.new("Part")
    container.Anchored = true; container.CanCollide = false; container.Transparency = 1
    container.Size = Vector3.new(0.1,0.1,0.1)
    container.CFrame = CFrame.new((from + to) * 0.5)
    container.Parent = workspace

    local a0 = Instance.new("Attachment", container)
    local a1 = Instance.new("Attachment", container)
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0; beam.Attachment1 = a1
    beam.Width0 = 0.15; beam.Width1 = 0.6
    beam.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(255,220,160))
    beam.Transparency = NumberSequence.new(0.1)
    beam.Brightness = 3
    beam.Texture = "rbxassetid://446111271"
    beam.TextureSpeed = 2
    beam.FaceCamera = true
    beam.Parent = container

    a0.WorldPosition = from
    a1.WorldPosition = from
    Tween:Create(a1, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { WorldPosition = to }):Play()
    task.delay(0.16, function() if container then container:Destroy() end end)
end
-- === Bow tracer (short, fast) ===
local function bowTracer(from, to, surge)
	local container = Instance.new("Part")
	container.Anchored = true; container.CanCollide = false; container.Transparency = 1
	container.Size = Vector3.new(0.1,0.1,0.1)
	container.CFrame = CFrame.new((from + to) * 0.5)
	container.Parent = workspace

	local a0 = Instance.new("Attachment", container)
	local a1 = Instance.new("Attachment", container)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Brightness = surge and 5 or 3
	beam.LightInfluence = 0.4
	beam.Segments = surge and 14 or 10
	beam.Width0 = surge and 0.25 or 0.12
	beam.Width1 = surge and 0.35 or 0.18
	beam.Texture = "rbxassetid://446111271"
	beam.TextureLength = 1
	beam.TextureSpeed = surge and 4 or 3
	beam.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.10),
		NumberSequenceKeypoint.new(1, 0.35),
	}
	beam.Color = ColorSequence.new(
		surge and Color3.fromRGB(255,120,120) or Color3.fromRGB(255,240,220),
		surge and Color3.fromRGB(255, 60, 40) or Color3.fromRGB(240,200,160)
	)
	beam.FaceCamera = true
	beam.Parent = container

	a0.WorldPosition = from
	a1.WorldPosition = from

	-- very short life
	local TweenService = game:GetService("TweenService")
	TweenService:Create(a1, TweenInfo.new(surge and 0.12 or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ WorldPosition = to }):Play()

	task.delay(surge and 0.15 or 0.10, function()
		if container then container:Destroy() end
	end)
end

-- === Quick metal spark for block ===
local function blockSpark(pos)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.Transparency = 1
	p.Size = Vector3.new(0.2,0.2,0.2); p.CFrame = CFrame.new(pos); p.Parent = workspace
	local a = Instance.new("Attachment", p)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxassetid://243664225"
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.15, 0.25)
	sparks.Speed = NumberRange.new(10, 18)
	sparks.SpreadAngle = Vector2.new(45, 45)
	sparks.Rotation = NumberRange.new(-30, 30)
	sparks.RotSpeed = NumberRange.new(-120, 120)
	sparks.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.1),
	}
	sparks.Color = ColorSequence.new(Color3.fromRGB(250, 250, 250), Color3.fromRGB(255, 200, 120))
	sparks.LightEmission = 0.7
	sparks.Parent = a
	sparks:Emit(12)

	game:GetService("Debris"):AddItem(p, 0.4)
end

local function ringPulse(pos, radius)
    radius = radius or 10
    local ring = Instance.new("Part")
    ring.Anchored = true; ring.CanCollide = false
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(120,180,255)
    ring.Transparency = 0.2
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(2, 0.12, 2)
    ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0)
    ring.Parent = workspace
    Tween:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(radius * 2, 0.12, radius * 2),
        Transparency = 1,
    }):Play()
    Debris:AddItem(ring, 0.3)
end

local function surgeImpact(pos)
	-- small spark burst at impact + heavier sound (enemy-side)
	blockSpark(pos)                 -- reuse your nice spark burst
	playAt(SFX.bow_surge, pos, 1.0) -- play at ENEMY impact, not shooter
end

RE.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	local kind = payload.kind
    if kind == "bow_shot" then
        print("[CVFX] bow_shot from=", payload.from, "to=", payload.to, "surge=", payload.surge)
    elseif kind == "bow_surge_hit" then
        print("[CVFX] bow_surge_hit pos=", payload.pos)
    elseif kind == "bow_surge_shot" then
        print("[CVFX] bow_surge_shot from=", payload.from, "to=", payload.to)
    end

	-- --- Bow surge impact (enemy-side) ---
	if kind == "bow_surge_hit" and payload.pos then
		surgeImpact(payload.pos)
		return
	end

	-- --- Bow tracer (from shooter -> target) ---
	if kind == "bow_shot" and payload.from and payload.to then
		local surge = payload.surge == true

		-- tracer visuals (you can keep surge affecting the beam visuals if you like)
		bowTracer(payload.from, payload.to, false) -- never surge-styled on shooter

		-- ALWAYS play the normal bow shot at the shooter
		playAt(SFX.bow_shot, payload.from, 0.7)
        
		return
	end


    if kind == "bow_surge_shot" and payload.from and payload.to then
        quickBeam(payload.from, payload.to)
        surgeImpact(payload.to) -- ✅ impact + heavy sound at TARGET
        return
    end

    -- --- mace stun pulse + glonk (new unified name) ---
    if kind == "mace_stun" and payload.pos then
        ringPulse(payload.pos, 8)
        playAt(SFX.mace_stun, payload.pos, 0.9)
        return
    end

    -- (back-compat) older name you had:
    if kind == "mace_stun_pulse" and payload.pos then
        ringPulse(payload.pos, 8)
        playAt(SFX.mace_stun, payload.pos, 0.9)
        return
    end

    -- --- shield/sword block clang ---
    if kind == "guard_block" and payload.pos then
        blockSpark(payload.pos)
        playAt(SFX.block_clang, payload.pos, 0.85)
        return
    end

    -- (back-compat) if server ever sent shield_block before:
    if kind == "shield_block" then
        local hero = payload.who
        local attachTo = hero and (hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart)
        if attachTo then
            sparkBurst(attachTo)
            playAt(SFX.block_clang, attachTo.Position, 0.85)
        end
        return
    end

    -- --- NEW: sword/mace swing whooshes ---
    if kind == "melee_swing" then
        local pos = payload.pos or Vector3.zero
        if payload.style == "Mace" then
            playAt(SFX.mace_swing, pos, 0.9)
        else
            -- default to sword-ish for SwordShield or any unknown
            playAt(SFX.sword_swing, pos, 0.8)
        end
        return
    end
end)
