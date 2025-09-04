-- WeaponStandPanels.client.lua
-- Shows a floating info panel next to Weapon Stands when their prompt appears.
-- The panel is cloned from a BillboardGui named "StandPanel" if we can find one
-- (SkillBoard has a good one). Otherwise we build a simple default on the fly.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LOCAL = Players.LocalPlayer

-- UI offsets (relative to the stand's local axes)
local RIGHT_OFFSET = 2.2   -- to the stand's right side
local UP_OFFSET    = 3.0   -- above base height
local FWD_OFFSET   = 0.0   -- towards/away (usually 0)

-- Try to find a “StandPanel” template (BillboardGui) anywhere useful.
local function findPanelTemplate(): BillboardGui?
    -- Preferred: ReplicatedStorage.UI.StandPanel
    local uiFolder = ReplicatedStorage:FindFirstChild("UI")
    if uiFolder then
        local t = uiFolder:FindFirstChild("StandPanel")
        if t and t:IsA("BillboardGui") then return t end
    end
    -- Fallback: any BillboardGui named "StandPanel" under workspace (SkillBoard has one)
    local ws = workspace:FindFirstChild("StandPanel", true)
    if ws and ws:IsA("BillboardGui") then return ws end
    return nil
end

local Template = findPanelTemplate()

-- Bookkeeping
local panelsByRoot : {[BasePart]: BillboardGui} = {}
local connsByRoot  : {[BasePart]: RBXScriptConnection} = {}

-- Resolve a weapon style name from the stand model (by name)
local function styleFromModel(standModel: Instance): string
    if not standModel then return "SwordShield" end
    local n = string.lower(standModel.Name)
    if n:find("mace") then return "Mace" end
    if n:find("bow") then return "Bow" end
    -- “StandSwordShield”, “StandSword”, “swordshield”… all map to SwordShield
    return "SwordShield"
end

-- Load muls/notes from ReplicatedStorage.Modules.WeaponStyles
local WeaponStyles = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponStyles"))

-- Build/fetch a panel for a specific stand root + prompt
local function makePanelFor(root: BasePart, prompt: ProximityPrompt): BillboardGui
    if panelsByRoot[root] then return panelsByRoot[root] end

    local gui: BillboardGui
    if Template and Template:IsA("BillboardGui") then
        gui = Template:Clone()
    else
        -- Minimal default if no template found
        gui = Instance.new("BillboardGui")
        gui.Size = UDim2.fromOffset(260, 180)
        gui.AlwaysOnTop = true
        gui.LightInfluence = 1
        gui.MaxDistance = 60
        local card = Instance.new("Frame")
        card.Name = "Card"
        card.Size = UDim2.fromScale(1, 1)
        card.BackgroundColor3 = Color3.new(0, 0, 0)
        card.BackgroundTransparency = 0.6 -- more see-through
        card.Parent = gui
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, -16, 0, 42)
        title.Position = UDim2.fromOffset(8, 8)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBlack
        title.TextScaled = true
        title.TextColor3 = Color3.new(1,1,1)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = card
        local line1 = title:Clone(); line1.Name="Line1"; line1.Position = UDim2.fromOffset(8, 64); line1.TextScaled=true; line1.TextTransparency=0.05; line1.Parent = card
        local line2 = title:Clone(); line2.Name="Line2"; line2.Position = UDim2.fromOffset(8, 96); line2.TextScaled=true; line2.TextTransparency=0.05; line2.Parent = card
        local perk  = title:Clone(); perk.Name ="Perk";  perk.Position  = UDim2.fromOffset(8, 128); perk.TextScaled=false; perk.TextSize = 18; perk.TextTransparency=0.15; perk.Parent = card
    end

    gui.Parent = root
    gui.Adornee = root
    panelsByRoot[root] = gui

    -- Keep the panel to the RIGHT of the stand, at head height.
    -- We recompute each frame so it tracks the stand orientation.
    if connsByRoot[root] then connsByRoot[root]:Disconnect() end
    connsByRoot[root] = RunService.RenderStepped:Connect(function()
        if not root or not root.Parent or not gui.Parent then return end
        local cf = root.CFrame
        local worldOffset =
            cf.RightVector * RIGHT_OFFSET +
            cf.UpVector    * UP_OFFSET +
            cf.LookVector  * FWD_OFFSET
        gui.StudsOffsetWorldSpace = worldOffset
    end)

    -- Style the card: darker & more transparent background
    local card = gui:FindFirstChild("Card", true)
    if card and card:IsA("Frame") then
        card.BackgroundColor3 = Color3.new(0,0,0)
        card.BackgroundTransparency = 0.6 -- ~50% more transparent than earlier
    end

    return gui
end

local function updatePanelText(gui: BillboardGui, styleName: string, standModel: Model)
    -- Normalise/capitalize title
    local titleText = (styleName == "SwordShield") and "Sword & Shield" or styleName

    local style = WeaponStyles and WeaponStyles[styleName]
    local atkMul = style and style.atkMul or 1.0
    local spdMul = style and style.spdMul or 1.0
    local note   = style and style.note   or ""

    -- Fill known fields if present on template
    local function setText(pathName: string, txt: string)
        local inst = gui:FindFirstChild(pathName, true)
        if inst and inst:IsA("TextLabel") then inst.Text = txt end
    end
    setText("Title", titleText)
    setText("Line1", ("Damage x%.2f    Speed x%.2f"):format(atkMul, spdMul))
    setText("Line2", "") -- we’re not duplicating “Press [E] to equip” here
    setText("Perk",  note)
end

-- Helper: get the BasePart root that owns this prompt (handles StandRoot or Attachment)
local function getRootFromPrompt(prompt: ProximityPrompt): BasePart?
    if not prompt then return nil end
    local p = prompt.Parent
    if not p then return nil end
    if p:IsA("BasePart") then return p end
    if p:IsA("Attachment") and p.Parent and p.Parent:IsA("BasePart") then
        return p.Parent
    end
    return p:FindFirstAncestorOfClass("BasePart")
end

-- Only show panels for real WEAPON STANDS (ignore SkillBoard prompts etc.)
local function isWeaponStandPrompt(prompt: ProximityPrompt): (boolean, BasePart?, Model?)
    -- Cheap check first: ObjectText "Weapon Stand" is set on your stand prompts
    if (prompt.ObjectText or "") ~= "Weapon Stand" then
        return false
    end
    local root = getRootFromPrompt(prompt)
    if not root then return false end
    local standModel = root:FindFirstAncestorOfClass("Model")
    if not standModel then return false end
    -- We expect the model to be named something like: StandMace / StandBow / StandSwordShield
    if not string.lower(standModel.Name):find("stand") then return false end
    return true, root, standModel
end

-- Show / hide
local function onPromptShown(prompt: ProximityPrompt)
    local ok, root, standModel = isWeaponStandPrompt(prompt)
    if not ok then return end

    local gui = makePanelFor(root :: BasePart, prompt)

    -- Fill text for this stand
    local styleName = styleFromModel(standModel :: Model)
    updatePanelText(gui, styleName, standModel)

    gui.Enabled = true
end

local function onPromptHidden(prompt: ProximityPrompt)
    local ok, root = isWeaponStandPrompt(prompt)
    if not ok then return end
    local gui = panelsByRoot[root :: BasePart]
    if gui then gui.Enabled = false end
end

ProximityPromptService.PromptShown:Connect(onPromptShown)
ProximityPromptService.PromptHidden:Connect(onPromptHidden)

-- Safety cleanup on character respawn
LOCAL.CharacterAdded:Connect(function()
    for root, conn in pairs(connsByRoot) do
        conn:Disconnect()
        connsByRoot[root] = nil
    end
    for root, gui in pairs(panelsByRoot) do
        if gui then gui:Destroy() end
        panelsByRoot[root] = nil
    end
end)
