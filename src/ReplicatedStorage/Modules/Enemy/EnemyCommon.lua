-- ReplicatedStorage/Modules/Enemy/EnemyCommon.lua
-- Updates:
--  - Adds AABB-based ground snap: M.flushToGround(model, groundY, epsilon)
--  - Tweaks sanitize() to use a safe HipHeight heuristic when no override is given
--    (fixes feet/toes slightly clipping into the floor on some rigs)
--  - Keeps all original functions for compatibility (no removals)

local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local M = {}

local function setDefaultCollidable()
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("Default", "Default", true)
	end)
end

-- NEW: get the model's full AABB height (more reliable than HRP.Size.Y)
local function modelHeight(model: Model): number
	local size = model:GetExtentsSize()
	return size and size.Y or 0
end

function M.sanitize(model: Model, opts)
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

	-- UPDATED: safer default HipHeight if no explicit override is provided
	local hh = opts.hipHeightOverride
	if typeof(hh) == "number" then
		hum.HipHeight = hh
	else
		-- 10–15% of the model's AABB height is a good general heuristic for R6/R15-style rigs.
		-- Keep a small floor so tiny mobs don't get forced to 0.
		local safeHH = math.max(0.8, modelHeight(model) * 0.12)
		hum.HipHeight = safeHH
	end

	hum.AutoRotate = true
	hum.PlatformStand = false
	hum.WalkSpeed = math.max(10, hum.WalkSpeed)
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
end

-- NEW: snap using the model's AABB (bottom of the whole model to groundY)
function M.flushToGround(model: Model, groundY: number, epsilon: number?)
	if not (model and groundY) then return end
	epsilon = epsilon or 0
	local pivot = model:GetPivot()
	local halfY = modelHeight(model) * 0.5
	if halfY <= 0 then return false end
	local bottomY = pivot.Position.Y - halfY
	local dy = (groundY + epsilon) - bottomY
	if math.abs(dy) > 1e-3 then
		model:PivotTo(pivot + Vector3.new(0, dy, 0))
		return true
	end
	return false
end

-- Kept for compatibility: root-size based snap (original behavior)
function M.flushToGroundByRoot(model: Model, groundY: number, epsilon)
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

function M.setOwner(model: Model, userId: number)
	if not model then return end
	model:SetAttribute("OwnerUserId", tonumber(userId) or 0)
end

function M.setRank(model: Model, rank: string?)
	if model and rank then model:SetAttribute("Rank", rank) end
end

function M.colorByElement(model: Model, elem: string?)
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

function M.tag(model: Model)
	if model and not CollectionService:HasTag(model, "Enemy") then
		CollectionService:AddTag(model, "Enemy")
	end
end

function M.ownToServer(model: Model)
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	if root then pcall(function() root:SetNetworkOwner(nil) end) end
end

return M
