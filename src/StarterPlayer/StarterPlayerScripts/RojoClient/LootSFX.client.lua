local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local RE      = Remotes:WaitForChild("LootPickupSFX")
local lp      = Players.LocalPlayer

local SFX = {
    flux    = "rbxassetid://13189443030",   -- replace with your flux sound
    essence = "rbxassetid://8561934524",    -- make this different (more “important”)
}

RE.OnClientEvent:Connect(function(kind, pos)
    local id = SFX[kind] or SFX.flux
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(0.2,0.2,0.2)
    part.CFrame = CFrame.new(pos)
    part.Parent = workspace

    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = 0.7
    s.RollOffMode = Enum.RollOffMode.InverseTapered
    s.RollOffMinDistance = 6     -- tighter falloff; only you hear it
    s.RollOffMaxDistance = 28
    s.Parent = part
    s:Play()
    s.Ended:Connect(function() if part then part:Destroy() end end)
    game:GetService("Debris"):AddItem(part, 6)
end)
