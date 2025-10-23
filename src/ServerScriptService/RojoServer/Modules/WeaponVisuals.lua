-- Visual equipper for Sword&Shield / Bow / Mace. Server-authoritative.
-- Drop-in module. Tweak OFFSETS at the top if something needs a tiny nudge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponsFolder     = ReplicatedStorage:WaitForChild("Weapons")
local PhysicsService = game:GetService("PhysicsService")

local M = {}

----------------------------------------------------------------
-- TUNING: per-weapon offsets FROM the hand coordinate frame
-- (units in studs; rotations in radians via math.rad())
-- We intentionally keep these small so models don't need editing.
----------------------------------------------------------------
local OFFSETS_R15 = {
	-- Right-hand items
	W_Sword = {
		hand = "Right",
		pos  = Vector3.new(0.00, -0.30, -0.10),
		rot  = CFrame.Angles(0, math.rad(90), math.rad(-90)), -- blade up, tip forward
	},

	-- 2H mace: you added OffGrip, so let's actually use it
	W_Mace = {
		hand = "Right",
		pos  = Vector3.new(0.00, -0.35, -0.10),
		rot  = CFrame.Angles(0, math.rad(90), math.rad(-90)),
		twoHand = true,  -- <- flip to true so left hand welds to OffGrip
	},

	-- Left-hand items
	W_Shield = {
		hand = "Left",
		-- slight in toward forearm, tiny down/forward so hand doesn't poke through
		pos  = Vector3.new(0.08, -0.05, -0.20),
		-- face outward, TIP down (roll 90). If the emblem looks upside-down, add yaw 180 below.
		rot = CFrame.Angles(0, math.rad(90), math.rad(-50)),
		-- If you want the bottom tip to rotate toward the ground more/less:
		-- rot = CFrame.Angles(0, math.rad(180), math.rad(90)) -- (adds a 180° yaw flip)
	},

	-- Bow (string faces the hero; only pitched up, NO roll)
	W_Bow = {
		hand = "Right",
		pos  = Vector3.new(0.02, 0.05, -0.05),
		rot = CFrame.Angles(math.rad(10), math.rad(80), math.rad(80)), -- up a bit, 180 yaw so string toward hero
	},
}

-- If you still use any R6 rigs for testing, you can clone the same offsets:
local OFFSETS_R6 = OFFSETS_R15

----------------------------------------------------------------
-- utilities
----------------------------------------------------------------
local function firstPart(inst: Instance): BasePart?
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function ensurePrimary(model: Model): BasePart?
	if not model.PrimaryPart then
		local p = firstPart(model)
		if p then model.PrimaryPart = p end
	end
	return model.PrimaryPart
end

local function setNoCollide(inst: Instance)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch   = false          -- <<< add
            d.Anchored   = false
            PhysicsService:SetPartCollisionGroup(d, "Effects")
		end
	end
end

-- find best "grip" inside a weapon model
local function bestGrip(model: Model): BasePart?
	-- Prefer an explicit Grip if present (most of your models use this)
	local g = model:FindFirstChild("Grip", true)
	if g and g:IsA("BasePart") then return g end

	-- Fallback to a Roblox-style Handle if that’s what the model has
	local h = model:FindFirstChild("Handle", true)
	if h and h:IsA("BasePart") then return h end

	-- Absolute last resort: primary/base part
	return ensurePrimary(model)
end

-- snap a whole model so that a PART inside it matches target CFrame
local function pivotPartTo(partInModel: BasePart, targetCF: CFrame)
	local model = partInModel:FindFirstAncestorOfClass("Model")
	if not model then return end
	local delta = partInModel.CFrame:ToObjectSpace(targetCF)
	model:PivotTo(model:GetPivot() * delta)
end

local function getRigType(hero: Model)
	local hum = hero:FindFirstChildOfClass("Humanoid")
	return (hum and hum.RigType == Enum.HumanoidRigType.R15) and "R15" or "R6"
end

local function getHand(hero: Model, which: "Right"|"Left"): BasePart?
	-- R15 first
	local p = hero:FindFirstChild(which.."Hand", true)
	if p and p:IsA("BasePart") then return p end
	-- R6 fallback
	p = hero:FindFirstChild(which.." Arm", true)
	if p and p:IsA("BasePart") then return p end
	return nil
end

local function clearFolder(folder: Instance)
	for _, c in ipairs(folder:GetChildren()) do c:Destroy() end
end

local function equippedFolder(hero: Model)
	local f = hero:FindFirstChild("EquippedVisuals")
	if not f then
		f = Instance.new("Folder")
		f.Name = "EquippedVisuals"
		f.Parent = hero
	end
	return f
end

local function offsetsFor(hero)
	return (getRigType(hero) == "R15") and OFFSETS_R15 or OFFSETS_R6
end

----------------------------------------------------------------
-- core placement
----------------------------------------------------------------
local function attachOne(hero: Model, modelName: string, handSide: "Right"|"Left", pos: Vector3, rot: CFrame)
	local src = WeaponsFolder:FindFirstChild(modelName)
	if not (src and src:IsA("Model")) then return nil end

	local clone = src:Clone()
	local hand  = getHand(hero, handSide)
	if not (hand and clone) then if clone then clone:Destroy() end; return nil end

	setNoCollide(clone)
	local grip = bestGrip(clone)
	if not grip then clone:Destroy(); return nil end

	-- place: hand CFrame * rot then position offset in hand space
	local placeCF = hand.CFrame * rot * CFrame.new(pos)
	-- snap the model by aligning its internal 'grip' to the desired place
	pivotPartTo(grip, placeCF)

	-- weld the actual grip to the hand so it stays locked
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = hand, grip
	w.Parent = grip

	clone.Parent = equippedFolder(hero)
	return clone
end

local function tryTwoHand(hero: Model, modelName: string, cfg)
	local src = WeaponsFolder:FindFirstChild(modelName)
	if not (src and src:IsA("Model")) then return nil end

	local right = getHand(hero, "Right")
	local left  = getHand(hero,  "Left")
	if not (right and left) then return nil end

	local clone = src:Clone()
	setNoCollide(clone)

	local grip   = bestGrip(clone)
	local off    = clone:FindFirstChild("OffGrip", true) -- optional
	if not (grip and off and off:IsA("BasePart")) then
		clone:Destroy()
		return nil
	end

	-- place by the right hand with the same offsets as 1H
	local placeCF = right.CFrame * (cfg.rot or CFrame.new()) * CFrame.new(cfg.pos or Vector3.zero)
	pivotPartTo(grip, placeCF)

	-- weld right hand to Grip
	local wr = Instance.new("WeldConstraint"); wr.Part0, wr.Part1 = right, grip; wr.Parent = grip
	-- weld left hand to OffGrip (keeps pose solid)
	local wl = Instance.new("WeldConstraint"); wl.Part0, wl.Part1 = left,  off;  wl.Parent = off

	clone.Parent = equippedFolder(hero)
	return clone
end

----------------------------------------------------------------
-- public API
----------------------------------------------------------------
function M.clear(hero: Model)
	local f = hero and hero:FindFirstChild("EquippedVisuals")
	if f then clearFolder(f) end
end

function M.apply(hero: Model)
	if not (hero and hero.Parent) then return end
	M.clear(hero)

	local rigOffsets = offsetsFor(hero)

	local main = string.lower(tostring(hero:GetAttribute("WeaponMain") or "sword"))
	local off  = string.lower(tostring(hero:GetAttribute("WeaponOff")  or ""))

	if main == "bow" then
		local cfg = rigOffsets.W_Bow
		attachOne(hero, "W_Bow", cfg.hand, cfg.pos, cfg.rot)

	elseif main == "mace" then
		local cfg = rigOffsets.W_Mace
		if cfg.twoHand then
			tryTwoHand(hero, "W_Mace", cfg)
		else
			attachOne(hero, "W_Mace", cfg.hand, cfg.pos, cfg.rot)
		end

	else
		-- default Sword & Shield
		do
			local cfg = rigOffsets.W_Sword
			attachOne(hero, "W_Sword", cfg.hand, cfg.pos, cfg.rot)
		end
		if main == "sword" and (off == "shield" or off == "") then
			local cfg = rigOffsets.W_Shield
			attachOne(hero, "W_Shield", cfg.hand, cfg.pos, cfg.rot)
		end
		-- safety: ensure no shield remains on non-sword styles (just in case)
		if main ~= "sword" then
			for _,d in ipairs(hero:GetDescendants()) do
				if d.Name == "W_Shield" then
					d:Destroy()
				end
			end
		end
	end
end

-- live re-apply when attributes change
function M.hook(hero: Model)
	if not hero then return end
	local function reapply() task.defer(M.apply, hero) end
	hero:GetAttributeChangedSignal("WeaponMain"):Connect(reapply)
	hero:GetAttributeChangedSignal("WeaponOff"):Connect(reapply)
end

-- === Two-hand IK helpers (Left hand to weapon) ===
local function findEquipped(hero: Model, modelName: string): Model?
	local f = hero:FindFirstChild("EquippedVisuals")
	if not f then return nil end
	for _, m in ipairs(f:GetChildren()) do
		if m:IsA("Model") and m.Name == modelName then return m end
	end
	return nil
end

local function ensureTargetAttachment(weaponModel: Model): Attachment?
	-- Prefer an Attachment named LeftHandTarget. Fallback to OffGrip (wrap in Attachment).
	local att = weaponModel:FindFirstChild("LeftHandTarget", true)
	if att and att:IsA("Attachment") then return att end

	local off = weaponModel:FindFirstChild("OffGrip", true)
	if off and off:IsA("BasePart") then
		local a = Instance.new("Attachment")
		a.Name = "LeftHandTarget"
		a.CFrame = CFrame.new() -- adjust in Studio if you need to nudge
		a.Parent = off
		return a
	end
	-- Last resort: stick it on PrimaryPart
	local root = weaponModel.PrimaryPart
	if root and root:IsA("BasePart") then
		local a = Instance.new("Attachment")
		a.Name = "LeftHandTarget"
		a.Parent = root
		return a
	end
	return nil
end

function M.enableTwoHandIK(hero: Model)
	local leftHand     = hero:FindFirstChild("LeftHand", true)
	local leftUpperArm = hero:FindFirstChild("LeftUpperArm", true)
	if not (leftHand and leftUpperArm) then return end -- needs R15

	local mace = findEquipped(hero, "W_Mace"); if not mace then return end
	local target = ensureTargetAttachment(mace); if not target then return end

	local ik = hero:FindFirstChild("TwoHandIKLeft")
	if not ik then
		ik = Instance.new("IKControl")
		ik.Name        = "TwoHandIKLeft"
		ik.ChainRoot   = leftUpperArm
		ik.EndEffector = leftHand
		ik.Type        = Enum.IKControlType.Position
		ik.Weight      = 1
		ik.Parent      = hero
	end
	ik.Target  = target
	ik.Enabled = true
end

function M.disableTwoHandIK(hero: Model)
	local ik = hero:FindFirstChild("TwoHandIKLeft")
	if ik then ik.Enabled = false end
end

return M
