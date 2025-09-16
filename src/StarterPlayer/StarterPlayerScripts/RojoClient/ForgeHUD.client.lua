local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local RE_HUD  = Remotes:WaitForChild("ForgeHUD")  -- <-- add this
local lp      = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ForgeHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = lp:WaitForChild("PlayerGui")

local chip = Instance.new("TextLabel")
chip.Size = UDim2.fromScale(0.32, 0.05)
chip.Position = UDim2.fromScale(0.02, 0.14)  -- top-left; adjust if you want it closer to the board
chip.BackgroundColor3 = Color3.fromRGB(20,24,36)
chip.TextColor3 = Color3.fromRGB(220,230,255)
chip.Font = Enum.Font.GothamBold
chip.TextScaled = true
chip.Text = ""
chip.Visible = false
Instance.new("UICorner", chip).CornerRadius = UDim.new(0,10)
local stroke = Instance.new("UIStroke", chip); stroke.Thickness=2; stroke.Transparency=0.4
chip.Parent = gui

local function setChip(data)
    if data and data.id then
        chip.Text = string.format("Core: %s  T%d", data.name or data.id, data.tier or 1)
        chip.Visible = true
    else
        chip.Visible = false
    end
end

-- server pushes new/clear
RE_HUD.OnClientEvent:Connect(setChip)
