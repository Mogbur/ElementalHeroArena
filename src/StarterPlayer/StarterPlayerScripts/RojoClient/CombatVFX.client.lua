local RS = game:GetService("ReplicatedStorage")
local Tween = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Run = game:GetService("RunService")
local Remotes = RS:WaitForChild("Remotes")
local RE = Remotes:WaitForChild("CombatVFX")

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

RE.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then return end
    local kind = payload.kind

    if kind == "shield_block" then
        local hero = payload.who
        if not (hero and hero.Parent) then return end
        local shield = hero:FindFirstChild("W_Shield", true)
        local attachTo = (shield and shield:IsA("BasePart")) and shield
            or hero:FindFirstChild("HumanoidRootPart") or hero.PrimaryPart
        if attachTo then sparkBurst(attachTo) end
        return
    end

    if kind == "bow_surge_shot" and payload.from and payload.to then
        quickBeam(payload.from, payload.to)
        return
    end

    if kind == "mace_stun_pulse" and payload.pos then
        ringPulse(payload.pos, 8)
        return
    end

    -- add more handlers here (weapon trails, hit-puffs, etc.)
end)
