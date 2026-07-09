--[[
Kitchen-sink example for imlove. Run from the repo root with:

    love .
    love . kitchensink

There is a tiny "game" (drifting circles standing in for entities) plus
three imlove windows:

  * "Widget gallery"   — every widget in the library, once.
  * "Entity Inspector" — the realistic use case: a tree of entities where
                         selecting one exposes its fields as live sliders.
  * "World"            — pause/step-style controls for the game itself.

Click a circle in the world to select it, and notice that clicks on the UI
never reach the game: mousepressed below checks imlove's return value.
]]

local imlove = require "imlove"

-- ----------------------------------------------------------------- the game

local WORLD_W, WORLD_H = 900, 600
local KINDS = { "goblin", "slime", "wisp" }

local entities = {}
local selected = nil
local world = { paused = false, timescale = 1.0 }

local function load()
  math.randomseed(42)
  entities = {}
  for i = 1, 10 do
    entities[i] = {
      name = KINDS[(i - 1) % #KINDS + 1] .. " " .. i,
      x = math.random(60, WORLD_W - 60),
      y = math.random(60, WORLD_H - 60),
      angle = math.random() * 2 * math.pi,
      speed = math.random(20, 90),
      radius = math.random(8, 22),
      hue = math.random(),
      alive = true,
    }
  end
  love.graphics.setBackgroundColor(0.13, 0.13, 0.16)
end

local function updateWorld(dt)
  if world.paused then return end
  dt = dt * world.timescale
  for _, e in ipairs(entities) do
    if e.alive then
      e.x = (e.x + math.cos(e.angle) * e.speed * dt) % WORLD_W
      e.y = (e.y + math.sin(e.angle) * e.speed * dt) % WORLD_H
    end
  end
end

local function hsvToRgb(h, s, v)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v else return v, p, q end
end

local function drawWorld()
  for _, e in ipairs(entities) do
    if e.alive then
      love.graphics.setColor(hsvToRgb(e.hue, 0.55, 0.9))
      love.graphics.circle("fill", e.x, e.y, e.radius)
      if e == selected then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("line", e.x, e.y, e.radius + 4)
      end
    end
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print("click a circle to select it  |  space = pause", 10,
    WORLD_H - 22)
end

-- ------------------------------------------------------------- demo windows

local gallery = {
  clicks = 0,
  checked = true,
  value = 0.5,
  fruit = 2,
  fruits = { "apple", "banana", "cherry" },
}

local function widgetGallery()
  imlove.SetNextWindowPos(20, 20, "once")
  if imlove.Begin("Widget gallery") then
    imlove.Text("Every imlove widget, once.")
    imlove.Text("FPS: %d", love.timer.getFPS())
    imlove.Separator()

    if imlove.Button("Click me") then
      gallery.clicks = gallery.clicks + 1
    end
    imlove.SameLine()
    imlove.Text("clicked %d times", gallery.clicks)

    gallery.checked = imlove.Checkbox("A checkbox", gallery.checked)
    gallery.value = imlove.SliderFloat("a slider", gallery.value, 0, 1)

    if imlove.TreeNode("A tree node") then
      imlove.Text("Nodes indent children and\nremember being open.")
      if imlove.TreeNode("Selectables") then
        for i, name in ipairs(gallery.fruits) do
          if imlove.Selectable(name, gallery.fruit == i) then
            gallery.fruit = i
          end
        end
        imlove.TreePop()
      end
      imlove.TreePop()
    end

    imlove.Separator()
    imlove.Text("WantCaptureMouse: %s",
      tostring(imlove.io.WantCaptureMouse))
  end
  imlove.End()
end

-- The primary use case: an inspector over a list of plain tables.
local function entityInspector()
  imlove.SetNextWindowPos(560, 20, "once")
  if imlove.Begin("Entity Inspector") then
    if imlove.TreeNode("Entities") then
      for i, e in ipairs(entities) do
        imlove.PushID(i)
        if imlove.Selectable(e.name, selected == e) then selected = e end
        imlove.PopID()
      end
      imlove.TreePop()
    end
    imlove.Separator()
    if selected then
      imlove.Text("%s", selected.name)
      selected.x = imlove.SliderFloat("x", selected.x, 0, WORLD_W)
      selected.y = imlove.SliderFloat("y", selected.y, 0, WORLD_H)
      selected.speed = imlove.SliderFloat("speed", selected.speed, 0, 200)
      selected.radius = imlove.SliderFloat("radius", selected.radius, 2, 40)
      selected.alive = imlove.Checkbox("alive", selected.alive)
      if imlove.Button("Deselect") then selected = nil end
    else
      imlove.Text("Select an entity above, or\nclick a circle in the world.")
    end
  end
  imlove.End()
end

local function worldControls()
  imlove.SetNextWindowPos(20, 420, "once")
  if imlove.Begin("World") then
    world.paused = imlove.Checkbox("Paused", world.paused)
    world.timescale = imlove.SliderFloat("time scale", world.timescale, 0, 3)
    if imlove.Button("Reset world") then
      load()
      selected = nil
    end
  end
  imlove.End()
end

-- ---------------------------------------------------------- module callbacks

local M = {}

function M.load()
  load()
end

function M.update(dt)
  imlove.NewFrame()      -- start the UI frame first...
  widgetGallery()        -- ...then declare the UI anywhere you like...
  entityInspector()
  worldControls()
  updateWorld(dt)
end

function M.draw()
  drawWorld()
  imlove.Render()        -- ...and draw it on top of everything.
end

function M.mousepressed(x, y, button)
  if imlove.mousepressed(x, y, button) then return end
  -- The UI didn't want this click, so it belongs to the game.
  for _, e in ipairs(entities) do
    local dx, dy = x - e.x, y - e.y
    if e.alive and dx * dx + dy * dy <= (e.radius + 3) ^ 2 then
      selected = e
      return
    end
  end
  selected = nil
end

function M.mousereleased(x, y, button)
  imlove.mousereleased(x, y, button)
end

function M.wheelmoved(dx, dy)
  imlove.wheelmoved(dx, dy)
end

function M.keypressed(key)
  if imlove.keypressed(key) then return end
  if key == "space" then world.paused = not world.paused end
  if key == "escape" then love.event.quit() end
end

return M
