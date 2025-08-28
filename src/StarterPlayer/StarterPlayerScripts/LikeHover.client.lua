-- StarterPlayerScripts/LikeHover.client.lua
-- Make the sign's studded like button "light up" on hover/press.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- attach hover behavior to one BoardGui
local function attach(gui: SurfaceGui)
	-- find the plate/button bits no matter how the tree is replicated
	local plate = gui:FindFirstChild("LikePlate", true)
	if not plate then return end

	local btn   = plate:FindFirstChild("LikeButton")
	local stud  = plate:FindFirstChild("StudBG")
	local stroke = plate:FindFirstChildOfClass("UIStroke")
	if not (btn and stud and stroke) then return end

	-- use our own tween instead of Roblox's default tint
	btn.AutoButtonColor = false

	-- colors: off → on
	local offColor = Color3.fromRGB(170,100,255)
	local onColor  = Color3.fromRGB(210,140,255)

	local tweenOn  = TweenService:Create(stud, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageColor3 = onColor })
	local tweenOff = TweenService:Create(stud, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageColor3 = offColor })

	local function toOn()
		stroke.Thickness = 4
		tweenOff:Cancel(); tweenOn:Play()
	end
	local function toOff()
		stroke.Thickness = 3
		tweenOn:Cancel(); tweenOff:Play()
	end

	-- hover (mouse), plus a simple touch fallback
	btn.MouseEnter:Connect(toOn)
	btn.MouseLeave:Connect(toOff)
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then toOn() end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then toOff() end
	end)
end

-- attach to all current and future sign UIs
local function scan()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SurfaceGui") and d.Name == "BoardGui" and not d:GetAttribute("HoverAttached") then
			attach(d)
			d:SetAttribute("HoverAttached", true)
		end
	end
end

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("SurfaceGui") and inst.Name == "BoardGui" then
		-- allow children (LikePlate etc.) to replicate in
		task.wait(0.05)
		attach(inst)
		inst:SetAttribute("HoverAttached", true)
	end
end)

scan()
