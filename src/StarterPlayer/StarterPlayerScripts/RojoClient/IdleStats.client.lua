-- RojoClient/IdleStats.client.lua (always visible; live updates)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Styles = require(RS.Modules.WeaponStyles)

local plr = Players.LocalPlayer

-- === UI ===
local gui = Instance.new("ScreenGui")
gui.Name = "IdleStats"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = plr:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.fromScale(0.985, 0.06)
frame.Size = UDim2.fromOffset(260, 160)
frame.BackgroundTransparency = 0.15
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
frame.BorderSizePixel = 0
frame.Parent = gui
local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 12)

-- Drag handle so you can move it out of the way during tests
local drag = Instance.new("TextLabel")
drag.BackgroundTransparency = 1
drag.Text = "Hero Stats"
drag.Font = Enum.Font.GothamBold
drag.TextSize = 16
drag.TextColor3 = Color3.fromRGB(235,235,235)
drag.TextXAlignment = Enum.TextXAlignment.Left
drag.Position = UDim2.fromOffset(12, 10)
drag.Size = UDim2.fromOffset(200, 20)
drag.Parent = frame

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Font = Enum.Font.Gotham
body.TextSize = 15
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.RichText = true
body.TextWrapped = true
body.Position = UDim2.fromOffset(12, 34)
body.Size = UDim2.new(1, -24, 1, -46)
body.TextColor3 = Color3.fromRGB(220,220,220)
body.Text = "…"
body.Parent = frame

-- Simple drag logic
do
    local UIS = game:GetService("UserInputService")
    local dragging, startPos, startInputPos
    local function begin(input)
        dragging = true
        startPos = frame.Position
        startInputPos = input.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
    drag.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            begin(input)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startInputPos
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- === helpers ===
local function currentStyleId()
    local main = string.lower(plr:GetAttribute("WeaponMain") or "sword")
    local off  = string.lower(plr:GetAttribute("WeaponOff")  or "")
    if main == "mace" then return "Mace"
    elseif main == "bow" then return "Bow"
    elseif main == "sword" and off == "shield" then return "SwordShield"
    end
    return "SwordShield"
end

local function findOwnPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, p in ipairs(plots:GetChildren()) do
        if p:IsA("Model") and (p:GetAttribute("OwnerUserId") or 0) == plr.UserId then
            return p
        end
    end
end

local function clamp01(x) return math.max(0, math.min(1, x)) end

local function snapStats()
    local plot = findOwnPlot()
    if not plot then return end
    local hero = plot:FindFirstChild("Hero", true)
    if not (hero and hero:IsA("Model")) then return end
    local hum = hero:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local styleId = currentStyleId()
    local S = Styles[styleId] or { atkMul = 1, spdMul = 1, hpMul = 1 }

    local plot = findOwnPlot()
    local coreId = plot and plot:GetAttribute("CoreId")
    local coreTier = tonumber(plot and plot:GetAttribute("CoreTier")) or 0
    local bonus = 1 + 0.06 * coreTier
    local coreHpMul  = (coreId == "HP")  and bonus or 1
    local coreSpdMul = (coreId == "HST") and bonus or 1

    local baseSwing = 0.60
    local swing = baseSwing / math.max(0.2, (S.spdMul or 1) * coreSpdMul)
    local lastOut   = plr:GetAttribute("Dbg_LastOutDmg")
    local lastFinal = plr:GetAttribute("Dbg_LastFinalDmg")
    local lastApply = plr:GetAttribute("Dbg_LastApplied")
    local lastElem  = plr:GetAttribute("Dbg_LastElem")
    local lastBasic = plr:GetAttribute("Dbg_LastIsBasic")

    local lastMul = math.max(0.01, plr:GetAttribute("LastHpMul") or 1)
    local baseMax = hero:GetAttribute("BaseMaxHealth") or hero:GetAttribute("BaseMax") or hum.MaxHealth
    local maxHP = math.floor(baseMax * (S.hpMul or 1) * coreHpMul + 0.5)

    local lvl = plr:GetAttribute("Level") or 1
    local cc  = plr:GetAttribute("CritChance") or (plot and (plot:GetAttribute("CritChance") or 0)) or 0
    local cm  = plr:GetAttribute("CritMult")  or (plot and (plot:GetAttribute("CritMult")  or 2)) or 2
    local flux = plr:GetAttribute("Flux") or 0
    local lastOut     = plr:GetAttribute("Dbg_LastOutDmg") or 0
    local lastFinal   = plr:GetAttribute("Dbg_LastFinalDmg") or 0
    local lastApplied = plr:GetAttribute("Dbg_LastApplied") or 0
    local lastElem    = plr:GetAttribute("Dbg_LastElem") or "Neutral"

    body.Text = string.format(
        "<b>Level %d</b>  |  <b>Style:</b> %s  |  <b>E.Flux:</b> %d\nMax HP: %d\nBasic Swing: %.2fs\nCrit: %d%%%%  x%.2f\n<b>Last DMG</b>: %d (applied) | %d (final) | %d (pre-elem) | %s",
        lvl, styleId, flux, maxHP, swing, math.floor(cc * 100 + 0.5), cm,
        lastApplied, lastFinal, lastOut, tostring(lastElem)
    )

end

-- Live updates
plr.CharacterAdded:Connect(function()
    task.delay(0.25, snapStats)
end)

for _, attr in ipairs({
	"Level","WeaponMain","WeaponOff","LastHpMul","CritChance","CritMult","Flux",
	"Dbg_LastOutDmg","Dbg_LastFinalDmg","Dbg_LastApplied","Dbg_LastElem"
}) do
    plr:GetAttributeChangedSignal(attr):Connect(snapStats)
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
    acc += dt
    if acc >= 0.35 then
        acc = 0
        snapStats()
    end
end)

-- Initial draw
snapStats()
