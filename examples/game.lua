--[[
"Real game" integration example: a field of drifting circles the player can
click to select or drag, plus an imlove debug panel to inspect and tweak
them. Run from the repo root with:

    love . game

This is the example to read if you want to see the WantCaptureMouse pattern
used for real: clicking or dragging inside the "Debug" window must never
move a circle underneath it. love.mousepressed below checks imlove's return
value before the game does anything with the click.

v1.3: right-click a row in the "Entities" list for a BeginPopupContextItem()
context menu (Clone / Reset position / Delete) — the canonical debug-UI use
for it.
]]

local imlove = require "imlove"

local WORLD_W, WORLD_H = 900, 700

local entities = {}
local selected = nil
local dragging = nil   -- entity currently being dragged, or nil
local dragDX, dragDY = 0, 0
local paused = false
local nextId = 1

local function spawn()
  local e = {
    id = nextId,
    x = math.random(40, WORLD_W - 40),
    y = math.random(40, WORLD_H - 40),
    angle = math.random() * 2 * math.pi,
    speed = math.random(20, 80),
    radius = math.random(10, 24),
    hue = math.random(),
  }
  nextId = nextId + 1
  entities[#entities + 1] = e
  return e
end

local function hsvToRgb(h, s, v)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v else return v, p, q end
end

local function entityAt(x, y)
  -- last-spawned-first, so newer circles win overlap ties.
  for i = #entities, 1, -1 do
    local e = entities[i]
    local dx, dy = x - e.x, y - e.y
    if dx * dx + dy * dy <= (e.radius + 3) ^ 2 then return e end
  end
  return nil
end

local function debugPanel()
  imlove.SetNextWindowPos(20, 20, "once")
  if imlove.Begin("Debug") then
    imlove.Text("FPS: %d", love.timer.getFPS())
    imlove.Text("entities: %d", #entities)
    paused = imlove.Checkbox("Paused", paused)
    if imlove.Button("Spawn") then selected = spawn() end
    imlove.Separator()

    if imlove.TreeNode("Entities") then
      -- Deferred instead of acted on immediately: mutating `entities` (or
      -- spawning into it) mid-ipairs() would be visible to this same
      -- loop's remaining iterations.
      local action, actionEntity
      for i, e in ipairs(entities) do
        imlove.PushID(e.id)
        if imlove.Selectable("circle " .. e.id, selected == e) then
          selected = e
        end
        -- v1.3: BeginPopupContextItem() — right-click this row for a
        -- context menu, scoped to this entity by the PushID(e.id) above.
        if imlove.BeginPopupContextItem() then
          -- Each pick closes the menu itself instead of leaving it open
          -- until an outside click dismisses it.
          if imlove.Selectable("Clone", false) then
            action, actionEntity = "clone", e
            imlove.CloseCurrentPopup()
          end
          if imlove.Selectable("Reset position", false) then
            action, actionEntity = "reset", e
            imlove.CloseCurrentPopup()
          end
          if imlove.Selectable("Delete", false) then
            action, actionEntity = "delete", e
            imlove.CloseCurrentPopup()
          end
          imlove.EndPopup()
        end
        imlove.PopID()
      end
      imlove.TreePop()

      if action == "clone" then
        local clone = spawn()
        clone.x, clone.y = actionEntity.x, actionEntity.y
        clone.radius, clone.speed, clone.hue =
          actionEntity.radius, actionEntity.speed, actionEntity.hue
        selected = clone
      elseif action == "reset" then
        actionEntity.x = math.random(40, WORLD_W - 40)
        actionEntity.y = math.random(40, WORLD_H - 40)
      elseif action == "delete" then
        for i, e in ipairs(entities) do
          if e == actionEntity then table.remove(entities, i) break end
        end
        if selected == actionEntity then selected = nil end
        if dragging == actionEntity then dragging = nil end
      end
    end
    imlove.Separator()

    if selected then
      imlove.Text("circle %d", selected.id)
      selected.speed = imlove.SliderFloat("speed", selected.speed, 0, 200)
      selected.radius = imlove.SliderFloat("radius", selected.radius, 4, 40)
    else
      imlove.Text("Click a circle to select it.")
    end
  end
  imlove.End()
end

-- ---------------------------------------------------------- module callbacks

local M = {}

function M.load()
  math.randomseed(os.time())
  love.graphics.setBackgroundColor(0.11, 0.12, 0.15)
  entities = {}
  for i = 1, 8 do spawn() end
end

function M.update(dt)
  imlove.NewFrame()   -- first imlove call of the frame
  debugPanel()

  if dragging and love.mouse.isDown(1) then
    local mx, my = love.mouse.getPosition()
    dragging.x, dragging.y = mx - dragDX, my - dragDY
  elseif not paused then
    for _, e in ipairs(entities) do
      if e ~= dragging then
        e.x = (e.x + math.cos(e.angle) * e.speed * dt) % WORLD_W
        e.y = (e.y + math.sin(e.angle) * e.speed * dt) % WORLD_H
      end
    end
  end
end

function M.draw()
  for _, e in ipairs(entities) do
    love.graphics.setColor(hsvToRgb(e.hue, 0.55, 0.9))
    love.graphics.circle("fill", e.x, e.y, e.radius)
    if e == selected then
      love.graphics.setColor(1, 1, 1, 0.9)
      love.graphics.circle("line", e.x, e.y, e.radius + 4)
    end
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print(
    "click a circle to select, drag to move  |  space = pause", 10,
    WORLD_H - 22)
  imlove.Render()   -- last: draws the UI on top
end

function M.mousepressed(x, y, button)
  if imlove.mousepressed(x, y, button) then return end
  -- Reaching here means the click was NOT on the UI.
  if button ~= 1 then return end
  local e = entityAt(x, y)
  selected = e
  if e then
    dragging = e
    dragDX, dragDY = x - e.x, y - e.y
  end
end

function M.mousereleased(x, y, button)
  imlove.mousereleased(x, y, button)
  if button == 1 then dragging = nil end
end

function M.wheelmoved(dx, dy)
  imlove.wheelmoved(dx, dy)
end

function M.keypressed(key)
  if imlove.keypressed(key) then return end
  if key == "space" then paused = not paused end
  if key == "escape" then love.event.quit() end
end

return M
