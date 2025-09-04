-- HeroAnim.lua (simple idle/run loop scaffolding; replace IDs later)
local M = {}

local IDS = {
  idle = "rbxassetid://0", -- TODO: put your idle animation id
  run  = "rbxassetid://0", -- TODO: put your run animation id
}

function M.attach(humanoid: Humanoid)
  if not humanoid then return end
  local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

  local tracks = {}
  local function load(id)
    if not id or id == "rbxassetid://0" then return nil end
    local a = Instance.new("Animation"); a.AnimationId = id
    local t = animator:LoadAnimation(a)
    t.Priority = Enum.AnimationPriority.Action
    t.Looped = true
    return t
  end

  tracks.idle = load(IDS.idle)
  tracks.run  = load(IDS.run)

  -- default to idle if present
  if tracks.idle then tracks.idle:Play(0.2) end

  -- simple movement watcher
  local running = false
  task.spawn(function()
    while humanoid.Parent do
      local moving = (humanoid.MoveDirection.Magnitude > 0.05)
      if moving and not running then
        running = true
        if tracks.idle then tracks.idle:Stop(0.15) end
        if tracks.run  then tracks.run:Play(0.15) end
      elseif (not moving) and running then
        running = false
        if tracks.run  then tracks.run:Stop(0.15) end
        if tracks.idle then tracks.idle:Play(0.15) end
      end
      task.wait(0.1)
    end
  end)
end

return M
