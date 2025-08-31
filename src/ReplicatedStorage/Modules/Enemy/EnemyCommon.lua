-- ReplicatedStorage/Modules/Enemy/EnemyCommon.lua
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local M = {}

local function setDefaultCollidable()
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("Default", "Default", true)
	end)
end

function M.sanitize(model : Model, opts)
	if not model then return end
	opts = opts or {}

	local hum = model:FindFirstChildOfClass("Humanoid"); if not hum then return end
	local hrp = model:FindFirstChild("HumanoidRootPart") or hum.RootPart; if not hrp then return end
	local body = model:FindFirstChild("Body")
	if model.PrimaryPart ~= hrp then model.PrimaryPart = hrp end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
			d.CollisionGroup = "Default"
		end
	end
	setDefaultCollidable()

	hrp.CanCollide = true
	hrp.Massless = false

	if body then
		body.CanCollide = false
		body.Massless = true
		for _,w in ipairs(body:GetChildren()) do
			if w:IsA("WeldConstraint") then w:Destroy() end
		end
		local dy = (hrp.Size.Y - body.Size.Y) * 0.5
		body.CFrame = hrp.CFrame * CFrame.new(0, -dy, 0)
		body.AssemblyLinearVelocity = Vector3.zero
		body.AssemblyAngularVelocity = Vector3.zero
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = hrp, body
		weld.Parent = body
	end

	local hh = opts.hipHeightOverride
	if typeof(hh) == "number" then
		hum.HipHeight = hh
	else
		hum.HipHeight = 0
	end

	hum.AutoRotate = true
	hum.PlatformStand = false
	hum.WalkSpeed = math.max(10, hum.WalkSpeed)
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
end

function M.flushToGroundByRoot(model : Model, groundY : number, epsilon)
	if not (model and groundY) then return end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end
	epsilon = epsilon or 0
	local bottomY = root.Position.Y - (root.Size.Y * 0.5)
	local dy = (groundY + epsilon) - bottomY
	if math.abs(dy) > 1e-3 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, dy, 0))
		return true
	end
	return false
end

function M.setOwner(model : Model, userId : number)
	if not model then return end
	model:SetAttribute("OwnerUserId", tonumber(userId) or 0)
end

function M.setRank(model : Model, rank : string?)
	if model and rank then model:SetAttribute("Rank", rank) end
end

function M.colorByElement(model : Model, elem : string?)
	if not elem then return end
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then return end
	if elem == "Fire" then
		body.Color = Color3.fromRGB(255,120,60)
	elseif elem == "Water" then
		body.Color = Color3.fromRGB(80,140,255)
	elseif elem == "Earth" then
		body.Color = Color3.fromRGB(170,130,90)
	else
		body.Color = Color3.fromRGB(180,40,40)
	end
end

function M.tag(model : Model)
	if model and not CollectionService:HasTag(model, "Enemy") then
		CollectionService:AddTag(model, "Enemy")
	end
end

function M.ownToServer(model : Model)
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	if root then pcall(function() root:SetNetworkOwner(nil) end) end
end

return M
