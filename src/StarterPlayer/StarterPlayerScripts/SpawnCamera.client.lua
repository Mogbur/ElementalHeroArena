-- StarterPlayerScripts/SpawnCamera.client.lua
-- Snap the camera behind your character, looking into your plot on spawn.

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function snapCamera()
	local char = lp.Character or lp.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	-- Give the server time to claim/teleport/orient you at the gate
	task.wait(1.0)

	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom

	-- Position camera behind & slightly above the player, facing forward
	local back = -hrp.CFrame.LookVector
	local pos  = hrp.Position + back * 12 + Vector3.new(0, 4, 0)
	cam.CFrame = CFrame.new(pos, hrp.Position + hrp.CFrame.LookVector * 8)
end

lp.CharacterAdded:Connect(function()
	task.defer(snapCamera)
end)

if lp.Character then
	task.defer(snapCamera)
end
